defmodule CritWeb.DeviceApiControllerTest do
  use CritWeb.ConnCase, async: true

  alias Crit.{DeviceCodes, Accounts, Repo}

  @oauth_params %{
    "sub" => "device-api-test-uid",
    "name" => "API Test User",
    "email" => "apitest@example.com",
    "picture" => nil
  }

  describe "POST /api/device/code" do
    test "creates a device code and returns response with verification_uri_complete", %{
      conn: conn
    } do
      conn = post(conn, "/api/device/code")

      assert %{
               "device_code" => dc,
               "verification_uri_complete" => uri_complete,
               "interval" => interval,
               "expires_in" => expires_in
             } = json_response(conn, 201)

      assert is_binary(dc)
      assert String.contains?(uri_complete, "/auth/cli?code=")
      assert interval == 5
      assert expires_in == 900
      refute Map.has_key?(json_response(conn, 201), "user_code")
      refute Map.has_key?(json_response(conn, 201), "verification_uri")
    end

    test "returns 404 when no OAuth provider is configured", %{conn: conn} do
      original = Application.get_env(:crit, :oauth_provider)
      Application.delete_env(:crit, :oauth_provider)

      on_exit(fn ->
        if original do
          Application.put_env(:crit, :oauth_provider, original)
        end
      end)

      conn = post(conn, "/api/device/code")
      assert %{"error" => error} = json_response(conn, 404)
      assert error =~ "not configured"
    end
  end

  describe "POST /api/device/token" do
    test "returns authorization_pending for a pending device code", %{conn: conn} do
      {:ok, %{device_code: raw}} = DeviceCodes.create_device_code()

      conn = post(conn, "/api/device/token", %{device_code: raw})
      assert %{"error" => "authorization_pending"} = json_response(conn, 400)
    end

    test "returns access_token and user identity for an authorized device code", %{conn: conn} do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()
      {:ok, _authorized} = DeviceCodes.authorize_device_code(record.id, user)

      conn = post(conn, "/api/device/token", %{device_code: raw})

      assert %{
               "access_token" => token,
               "token_type" => "bearer",
               "user_id" => user_id,
               "user_name" => "API Test User",
               "user_email" => "apitest@example.com"
             } = json_response(conn, 200)

      assert user_id == user.id
      assert String.starts_with?(token, "crit_")
    end

    test "returns expired_token for an expired device code", %{conn: conn} do
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()

      record
      |> Ecto.Changeset.change(
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      conn = post(conn, "/api/device/token", %{device_code: raw})
      assert %{"error" => "expired_token"} = json_response(conn, 400)
    end

    test "returns expired_token for unknown device code", %{conn: conn} do
      conn = post(conn, "/api/device/token", %{device_code: "nonexistent"})
      assert %{"error" => "expired_token"} = json_response(conn, 400)
    end

    test "returns slow_down when polling too fast", %{conn: conn} do
      {:ok, %{device_code: raw, record: record}} = DeviceCodes.create_device_code()

      # Set last_polled_at to just now
      record
      |> Ecto.Changeset.change(last_polled_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      conn = post(conn, "/api/device/token", %{device_code: raw})
      assert %{"error" => "slow_down"} = json_response(conn, 400)
    end

    test "returns error when device_code param is missing", %{conn: conn} do
      conn = post(conn, "/api/device/token", %{})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end
end
