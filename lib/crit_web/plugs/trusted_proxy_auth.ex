defmodule CritWeb.Plugs.TrustedProxyAuth do
  @moduledoc """
  Plug that authenticates users via a trusted reverse-proxy header.

  Runs after `CritWeb.UserAuth.fetch_current_scope_for_user/2` in the browser
  pipeline. When the operator has configured both
  `CRIT_TRUSTED_PROXY_USER_HEADER` and `CRIT_TRUSTED_PROXY_CIDRS`, this plug:

    1. Skips if a session-authenticated user is already on the scope.
    2. Verifies the request originates from a trusted proxy (CIDR check).
    3. Reads the configured header and finds-or-creates a user from the email.
    4. Replaces the anonymous scope with one for the resolved user, and writes
       `user_id` into the session so subsequent LiveView mounts see it via the
       normal session path.

  Setting the header without a CIDR list is rejected at boot by
  `Crit.Config.validate_trusted_proxy!/0`. See `lib/crit/config.ex` for the
  threat model.
  """

  require Logger

  import Plug.Conn

  alias Crit.Accounts
  alias Crit.Accounts.Scope
  alias Crit.Config

  # Cap email header length to discourage abuse / pathological inputs.
  @max_email_length 320
  @email_re ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  def init(opts), do: opts

  def call(conn, _opts) do
    with header_name when is_binary(header_name) <- get_header_config(),
         :ok <- ensure_no_session_user(conn),
         :ok <- ensure_trusted_source(conn),
         {:ok, email} <- read_header(conn, header_name),
         {:ok, email} <- validate_email(email),
         {:ok, user} <- upsert_user(email) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> put_session("user_id", user.id)
    else
      _ -> conn
    end
  end

  defp get_header_config do
    case Application.get_env(:crit, :trusted_proxy_user_header) do
      nil -> :skip
      "" -> :skip
      header when is_binary(header) -> String.downcase(header)
    end
  end

  defp ensure_no_session_user(conn) do
    case conn.assigns[:current_scope] do
      %Scope{user: %_{}} -> :skip
      _ -> :ok
    end
  end

  defp ensure_trusted_source(conn) do
    cidrs = Application.get_env(:crit, :trusted_proxy_cidrs, [])

    if Config.ip_in_cidrs?(conn.remote_ip, cidrs) do
      :ok
    else
      :skip
    end
  end

  defp read_header(conn, header_name) do
    case get_req_header(conn, header_name) do
      [value] when is_binary(value) ->
        {:ok, value}

      [] ->
        :skip

      multiple when is_list(multiple) ->
        Logger.warning(
          "trusted-proxy: header #{inspect(header_name)} present #{length(multiple)} times; ignoring"
        )

        :skip
    end
  end

  defp validate_email(value) do
    trimmed = String.trim(value)
    lowered = String.downcase(trimmed)

    cond do
      lowered == "" ->
        Logger.warning("trusted-proxy: empty email header value")
        :skip

      String.length(lowered) > @max_email_length ->
        Logger.warning("trusted-proxy: email header value exceeds #{@max_email_length} chars")
        :skip

      not Regex.match?(@email_re, lowered) ->
        Logger.warning("trusted-proxy: malformed email in header: #{inspect(trimmed)}")
        :skip

      true ->
        {:ok, lowered}
    end
  end

  defp upsert_user(email) do
    case Accounts.upsert_user_by_email(email) do
      {:ok, user} ->
        {:ok, user}

      {:error, reason} ->
        Logger.warning("trusted-proxy: upsert_user_by_email failed: #{inspect(reason)}")
        :skip
    end
  end
end
