defmodule Crit.DeviceCodes do
  @moduledoc """
  Context for OAuth Device Flow (RFC 8628).

  Manages device codes that allow CLI clients to authenticate via a browser-based
  OAuth flow. Device codes are short-lived (15 minutes) and go through the
  lifecycle: pending -> authorized -> redeemed.
  """

  import Ecto.Query

  alias Crit.{Repo, DeviceCode, Accounts}
  alias Ecto.Multi

  @expires_in_seconds 900
  @poll_interval_seconds 5
  # Consonants + unambiguous digits (no 0/O, 1/I/L)
  @user_code_chars ~c"BCDFGHJKMNPQRSTVWXYZ2346789"
  @user_code_length 8
  @max_retries 5

  @doc """
  Returns the standard poll interval in seconds.
  """
  def poll_interval, do: @poll_interval_seconds

  @doc """
  Returns the expiration duration in seconds.
  """
  def expires_in, do: @expires_in_seconds

  @doc """
  Generates a new device code and user code pair.

  The device_code is stored as a SHA256 hash; the raw value is returned to the caller.
  The user_code is stored in plaintext (it's short-lived and needs exact-match lookup).

  Retries on user_code unique constraint violations (up to #{@max_retries} times).

  Returns `{:ok, %{device_code: raw_device_code, user_code: formatted_code, record: %DeviceCode{}}}`.
  """
  def create_device_code, do: create_device_code(0)

  defp create_device_code(retry) when retry >= @max_retries do
    {:error, :too_many_retries}
  end

  defp create_device_code(retry) do
    raw_device_code = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    device_code_hash = hash_device_code(raw_device_code)
    user_code = generate_user_code()

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, @expires_in_seconds, :second)

    changeset =
      %DeviceCode{}
      |> DeviceCode.changeset(%{
        device_code: device_code_hash,
        user_code: user_code,
        status: :pending,
        expires_at: expires_at
      })

    case Repo.insert(changeset) do
      {:ok, record} ->
        {:ok,
         %{
           device_code: raw_device_code,
           user_code: format_user_code(user_code),
           record: record
         }}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :user_code) do
          create_device_code(retry + 1)
        else
          {:error, :insert_failed}
        end
    end
  end

  @doc """
  Looks up a pending, non-expired device code by user_code.

  Returns `{:ok, %DeviceCode{}}` or `{:error, :not_found}`.
  """
  def verify_user_code(user_code) do
    # Normalize: strip hyphens and upcase
    normalized = user_code |> String.replace("-", "") |> String.upcase() |> String.trim()
    now = DateTime.utc_now()

    case Repo.one(
           from d in DeviceCode,
             where: d.user_code == ^normalized and d.status == :pending and d.expires_at > ^now
         ) do
      nil -> {:error, :not_found}
      device_code -> {:ok, device_code}
    end
  end

  @doc """
  Authorizes a device code after the user completes OAuth.

  In a single transaction:
  1. Updates the device code status to :authorized and sets user_id
  2. Creates an API token for the user
  3. Stores the plaintext API token on the device code row

  Returns `{:ok, %DeviceCode{}}` or `{:error, reason}`.
  """
  def authorize_device_code(device_code_id, user) do
    Multi.new()
    |> Multi.one(:device_code, fn _ ->
      from(d in DeviceCode,
        where: d.id == ^device_code_id and d.status == :pending,
        lock: "FOR UPDATE"
      )
    end)
    |> Multi.run(:validate, fn _repo, %{device_code: dc} ->
      cond do
        is_nil(dc) -> {:error, :not_found}
        DateTime.compare(dc.expires_at, DateTime.utc_now()) == :lt -> {:error, :expired}
        true -> {:ok, dc}
      end
    end)
    |> Multi.run(:api_token, fn _repo, _changes ->
      Accounts.create_token(user, "crit CLI (device flow)")
    end)
    |> Multi.run(:authorize, fn _repo, %{validate: dc, api_token: {plaintext, _token_record}} ->
      dc
      |> Ecto.Changeset.change(
        status: :authorized,
        user_id: user.id,
        access_token: plaintext
      )
      |> Repo.update()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{authorize: device_code}} -> {:ok, device_code}
      {:error, :validate, reason, _} -> {:error, reason}
      {:error, _step, _reason, _} -> {:error, :transaction_failed}
    end
  end

  @doc """
  Polls for the token associated with a raw device code.

  Returns one of:
  - `{:ok, access_token, user_name}` — success, token redeemed
  - `{:error, :authorization_pending}` — user hasn't authorized yet
  - `{:error, :slow_down}` — client is polling too fast
  - `{:error, :expired_token}` — device code has expired
  - `{:error, :not_found}` — unknown device code
  """
  def poll_device_code(raw_device_code) do
    device_code_hash = hash_device_code(raw_device_code)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.one(
           from d in DeviceCode,
             where: d.device_code == ^device_code_hash,
             preload: [:user]
         ) do
      nil ->
        {:error, :not_found}

      %DeviceCode{} = dc ->
        cond do
          dc.status == :redeemed ->
            {:error, :expired_token}

          DateTime.compare(dc.expires_at, now) == :lt ->
            {:error, :expired_token}

          polling_too_fast?(dc, now) ->
            # Still update last_polled_at so the next poll also has a reference
            dc
            |> Ecto.Changeset.change(last_polled_at: now)
            |> Repo.update()

            {:error, :slow_down}

          dc.status == :pending ->
            dc
            |> Ecto.Changeset.change(last_polled_at: now)
            |> Repo.update()

            {:error, :authorization_pending}

          dc.status == :authorized ->
            # Atomic redemption: only update if still :authorized to prevent
            # concurrent polls from both redeeming the same token.
            {count, _} =
              Repo.update_all(
                from(d in DeviceCode,
                  where: d.id == ^dc.id and d.status == :authorized
                ),
                set: [status: :redeemed, access_token: nil, last_polled_at: now]
              )

            if count == 1 do
              {:ok, dc.access_token, display_name(dc.user)}
            else
              # Another poll beat us — token already redeemed
              {:error, :expired_token}
            end
        end
    end
  end

  @doc """
  Deletes expired, redeemed, or stale authorized device codes.

  - Expired: `expires_at` < now
  - Redeemed: `status = 'redeemed'`
  - Stale authorized: `status = 'authorized'` and inserted_at > 1 hour ago
  """
  def cleanup_expired do
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -3600, :second)

    {count, _} =
      Repo.delete_all(
        from d in DeviceCode,
          where:
            d.expires_at < ^now or
              d.status == :redeemed or
              (d.status == :authorized and d.inserted_at < ^one_hour_ago)
      )

    {:ok, count}
  end

  # --- Private helpers ---

  defp hash_device_code(raw) do
    Base.url_encode64(:crypto.hash(:sha256, raw), padding: false)
  end

  defp generate_user_code do
    1..@user_code_length
    |> Enum.map(fn _ -> Enum.random(@user_code_chars) end)
    |> List.to_string()
  end

  defp format_user_code(code) when byte_size(code) == @user_code_length do
    first = String.slice(code, 0, 4)
    second = String.slice(code, 4, 4)
    "#{first}-#{second}"
  end

  defp polling_too_fast?(%DeviceCode{last_polled_at: nil}, _now), do: false

  defp polling_too_fast?(%DeviceCode{last_polled_at: last_polled_at}, now) do
    diff = DateTime.diff(now, last_polled_at, :second)
    diff < @poll_interval_seconds
  end

  defp display_name(nil), do: nil

  defp display_name(%Crit.User{} = user) do
    user.name || user.email || user.provider_uid
  end
end
