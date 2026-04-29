defmodule Crit.DeviceCodesTest do
  use Crit.DataCase, async: true

  alias Crit.{DeviceCodes, DeviceCode, Accounts}

  @oauth_params %{
    "sub" => "device-codes-test-uid",
    "name" => "Test User",
    "email" => "device@example.com",
    "picture" => nil
  }

  defp create_user do
    {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
    user
  end

  describe "create_device_code/0" do
    test "creates a device code with pending status and session_code" do
      assert {:ok, %{device_code: dc, session_code: sc, record: record}} =
               DeviceCodes.create_device_code()

      assert is_binary(dc)
      assert String.length(dc) > 0
      assert is_binary(sc)
      assert String.length(sc) > 20

      assert record.status == :pending
      assert record.expires_at != nil
      assert record.user_id == nil
    end

    test "stores device_code as SHA256 hash, not plaintext" do
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()
      refute record.device_code == raw
      expected_hash = Base.url_encode64(:crypto.hash(:sha256, raw), padding: false)
      assert record.device_code == expected_hash
    end

    test "stores session_code as SHA256 hash, not plaintext" do
      {:ok, %{session_code: raw, record: record}} = DeviceCodes.create_device_code()
      refute record.session_code == raw
      expected_hash = Base.url_encode64(:crypto.hash(:sha256, raw), padding: false)
      assert record.session_code == expected_hash
    end

    test "sets expires_at to approximately 15 minutes from now" do
      {:ok, %{record: record}} = DeviceCodes.create_device_code()
      diff = DateTime.diff(record.expires_at, DateTime.utc_now(), :second)
      assert diff >= 898 and diff <= 901
    end
  end

  describe "verify_session_code/1" do
    test "finds a pending, non-expired device code by session_code" do
      {:ok, %{session_code: session_code, record: original}} = DeviceCodes.create_device_code()
      assert {:ok, found} = DeviceCodes.verify_session_code(session_code)
      assert found.id == original.id
    end

    test "returns error for non-existent session_code" do
      assert {:error, :not_found} = DeviceCodes.verify_session_code("nonexistent")
    end

    test "returns error for expired device code" do
      {:ok, %{session_code: session_code, record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      assert {:error, :not_found} = DeviceCodes.verify_session_code(session_code)
    end

    test "returns error for authorized (non-pending) device code" do
      {:ok, %{session_code: session_code, record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(status: :authorized)
      |> Repo.update!()

      assert {:error, :not_found} = DeviceCodes.verify_session_code(session_code)
    end
  end

  describe "authorize_device_code/2" do
    test "authorizes a pending device code and creates an API token" do
      user = create_user()
      {:ok, %{record: record}} = DeviceCodes.create_device_code()

      assert {:ok, authorized} = DeviceCodes.authorize_device_code(record.id, user)
      assert authorized.status == :authorized
      assert authorized.user_id == user.id
      assert authorized.access_token != nil
      assert String.starts_with?(authorized.access_token, "crit_")
    end

    test "returns error for non-existent device code" do
      user = create_user()
      assert {:error, :not_found} = DeviceCodes.authorize_device_code(Ecto.UUID.generate(), user)
    end

    test "returns error for expired device code" do
      user = create_user()
      {:ok, %{record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      assert {:error, :expired} = DeviceCodes.authorize_device_code(record.id, user)
    end

    test "returns error for already-authorized device code" do
      user = create_user()
      {:ok, %{record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(status: :authorized)
      |> Repo.update!()

      assert {:error, :not_found} = DeviceCodes.authorize_device_code(record.id, user)
    end
  end

  describe "poll_device_code/1" do
    test "returns authorization_pending for a pending device code" do
      {:ok, %{device_code: raw}} = DeviceCodes.create_device_code()
      assert {:error, :authorization_pending} = DeviceCodes.poll_device_code(raw)
    end

    test "returns the access_token and user info for an authorized device code" do
      user = create_user()
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()
      {:ok, _authorized} = DeviceCodes.authorize_device_code(record.id, user)

      assert {:ok, access_token, user_info} = DeviceCodes.poll_device_code(raw)
      assert String.starts_with?(access_token, "crit_")
      assert user_info.id == user.id
      assert user_info.name == "Test User"
      assert user_info.email == user.email
    end

    test "marks device code as redeemed and clears access_token after successful poll" do
      user = create_user()
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()
      {:ok, _authorized} = DeviceCodes.authorize_device_code(record.id, user)

      {:ok, _token, _info} = DeviceCodes.poll_device_code(raw)

      redeemed = Repo.get!(DeviceCode, record.id)
      assert redeemed.status == :redeemed
      assert redeemed.access_token == nil
    end

    test "returns expired_token after redemption" do
      user = create_user()
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()
      {:ok, _authorized} = DeviceCodes.authorize_device_code(record.id, user)

      {:ok, _token, _info} = DeviceCodes.poll_device_code(raw)
      assert {:error, :expired_token} = DeviceCodes.poll_device_code(raw)
    end

    test "returns expired_token for an expired device code" do
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      assert {:error, :expired_token} = DeviceCodes.poll_device_code(raw)
    end

    test "returns not_found for unknown device code" do
      assert {:error, :not_found} = DeviceCodes.poll_device_code("nonexistent")
    end

    test "returns slow_down when polling too fast" do
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()

      # Set last_polled_at to just now
      record
      |> Ecto.Changeset.change(last_polled_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      assert {:error, :slow_down} = DeviceCodes.poll_device_code(raw)
    end

    test "updates last_polled_at on each poll" do
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()
      assert is_nil(Repo.get!(DeviceCode, record.id).last_polled_at)

      DeviceCodes.poll_device_code(raw)

      updated = Repo.get!(DeviceCode, record.id)
      assert updated.last_polled_at != nil
    end
  end

  describe "cleanup_expired/0" do
    test "deletes expired device codes" do
      {:ok, %{record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      {:ok, count} = DeviceCodes.cleanup_expired()
      assert count == 1
      assert is_nil(Repo.get(DeviceCode, record.id))
    end

    test "deletes redeemed device codes" do
      {:ok, %{record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(status: :redeemed)
      |> Repo.update!()

      {:ok, count} = DeviceCodes.cleanup_expired()
      assert count == 1
    end

    test "deletes stale authorized device codes (older than 1 hour)" do
      {:ok, %{record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(status: :authorized)
      |> Repo.update!()

      # Manually backdate inserted_at
      Repo.update_all(
        from(d in DeviceCode, where: d.id == ^record.id),
        set: [
          inserted_at:
            DateTime.utc_now() |> DateTime.add(-3601, :second) |> DateTime.truncate(:second)
        ]
      )

      {:ok, count} = DeviceCodes.cleanup_expired()
      assert count == 1
    end

    test "does not delete fresh pending device codes" do
      {:ok, %{record: record}} = DeviceCodes.create_device_code()
      {:ok, count} = DeviceCodes.cleanup_expired()
      assert count == 0
      assert Repo.get(DeviceCode, record.id)
    end

    test "does not delete recently authorized device codes" do
      {:ok, %{record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(status: :authorized)
      |> Repo.update!()

      {:ok, count} = DeviceCodes.cleanup_expired()
      assert count == 0
    end
  end
end
