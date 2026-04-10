defmodule CritWeb.DeviceControllerTest do
  use CritWeb.ConnCase, async: true

  alias Crit.{Accounts, DeviceCodes}

  describe "GET /auth/cli?code=SESSION_CODE" do
    test "redirects to OAuth login with valid session code", %{conn: conn} do
      {:ok, %{session_code: session_code, record: record}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/cli", %{code: session_code})

      assert redirected_to(conn) == ~p"/auth/login"
      assert get_session(conn, :device_code_id) == record.id
    end

    test "returns 400 with invalid session code", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/cli", %{code: "nonexistent"})

      assert html_response(conn, 400) =~ "invalid or expired"
    end

    test "returns 400 when code param is missing", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/cli")

      assert html_response(conn, 400) =~ "invalid or expired"
    end
  end

  describe "GET /auth/cli/authorize" do
    test "renders consent page when session has device_code_id and user is logged in", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid_authorize",
          "name" => "Auth User",
          "email" => "auth@example.com",
          "picture" => "https://example.com/avatar.png"
        })

      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id, device_code_id: device_code.id})
        |> assign(:current_user, user)
        |> get(~p"/auth/cli/authorize")

      body = html_response(conn, 200)
      assert body =~ "Authorize Device"
      assert body =~ "Auth User"
      assert body =~ "Authorize this device to access your account"
    end

    test "shows avatar fallback letter when user has no avatar", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid_no_avatar",
          "name" => "No Avatar",
          "email" => "noavatar@example.com",
          "picture" => nil
        })

      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id, device_code_id: device_code.id})
        |> assign(:current_user, user)
        |> get(~p"/auth/cli/authorize")

      body = html_response(conn, 200)
      assert body =~ "Authorize Device"
      assert body =~ "No Avatar"
    end

    test "redirects to /auth/cli when device_code_id is missing from session", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid_no_code",
          "name" => "User",
          "email" => "user@example.com",
          "picture" => nil
        })

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id})
        |> assign(:current_user, user)
        |> get(~p"/auth/cli/authorize")

      assert redirected_to(conn) == ~p"/auth/cli"
    end

    test "redirects to /auth/cli when user is not logged in", %{conn: conn} do
      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{device_code_id: device_code.id})
        |> get(~p"/auth/cli/authorize")

      assert redirected_to(conn) == ~p"/auth/cli"
    end
  end

  describe "POST /auth/cli/authorize" do
    test "authorizes device code and redirects to success", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid_confirm",
          "name" => "Confirm User",
          "email" => "confirm@example.com",
          "picture" => nil
        })

      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id, device_code_id: device_code.id})
        |> assign(:current_user, user)
        |> post(~p"/auth/cli/authorize")

      assert redirected_to(conn) == ~p"/auth/cli/success"
      assert get_session(conn, :device_code_id) == nil
    end

    test "redirects to /auth/cli with error when device code is expired", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid_expired",
          "name" => "Expired User",
          "email" => "expired@example.com",
          "picture" => nil
        })

      conn =
        conn
        |> init_test_session(%{
          "user_id" => user.id,
          device_code_id: Ecto.UUID.generate()
        })
        |> assign(:current_user, user)
        |> post(~p"/auth/cli/authorize")

      assert redirected_to(conn) == ~p"/auth/cli"
      assert get_session(conn, :device_code_id) == nil
    end

    test "redirects to /auth/cli when session is missing device_code_id", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid_missing",
          "name" => "Missing User",
          "email" => "missing@example.com",
          "picture" => nil
        })

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id})
        |> assign(:current_user, user)
        |> post(~p"/auth/cli/authorize")

      assert redirected_to(conn) == ~p"/auth/cli"
    end

    test "redirects to /auth/cli when user is not logged in", %{conn: conn} do
      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{device_code_id: device_code.id})
        |> post(~p"/auth/cli/authorize")

      assert redirected_to(conn) == ~p"/auth/cli"
    end
  end

  describe "POST /auth/cli/cancel" do
    test "clears device_code_id from session and redirects to /auth/cli", %{conn: conn} do
      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{device_code_id: device_code.id})
        |> post(~p"/auth/cli/cancel")

      assert redirected_to(conn) == ~p"/auth/cli"
      assert get_session(conn, :device_code_id) == nil
    end
  end

  describe "GET /auth/cli/success" do
    test "renders the success page", %{conn: conn} do
      conn = get(conn, ~p"/auth/cli/success")
      assert html_response(conn, 200) =~ "signed in"
      assert html_response(conn, 200) =~ "close this tab"
    end
  end
end
