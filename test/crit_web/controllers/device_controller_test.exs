defmodule CritWeb.DeviceControllerTest do
  use CritWeb.ConnCase, async: true

  alias Crit.{Accounts, DeviceCodes}

  describe "GET /device" do
    test "renders the code entry page", %{conn: conn} do
      conn = get(conn, ~p"/device")
      assert html_response(conn, 200) =~ "Sign in to Crit"
    end

    test "does not show user identity card", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid_index",
          "name" => "Test User",
          "email" => "test@example.com",
          "picture" => nil
        })

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id})
        |> get(~p"/device")

      body = html_response(conn, 200)
      refute body =~ "Test User"
      refute body =~ "test@example.com"
    end
  end

  describe "POST /device" do
    test "redirects to OAuth login with valid user code", %{conn: conn} do
      {:ok, %{user_code: user_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{})
        |> post(~p"/device", %{user_code: user_code})

      assert redirected_to(conn) == ~p"/auth/login"
      assert get_session(conn, :device_code_id) != nil
    end

    test "shows error with invalid user code", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> post(~p"/device", %{user_code: "ZZZZ-ZZZZ"})

      assert html_response(conn, 200) =~ "Invalid or expired code"
    end

    test "shows error when user_code is missing", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> post(~p"/device", %{})

      assert html_response(conn, 200) =~ "Please enter a code"
    end
  end

  describe "GET /device/authorize" do
    test "renders consent page when session has device_code_id and user is logged in", %{
      conn: conn
    } do
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
        |> get(~p"/device/authorize")

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
        |> get(~p"/device/authorize")

      body = html_response(conn, 200)
      assert body =~ "Authorize Device"
      assert body =~ "No Avatar"
    end

    test "redirects to /device when device_code_id is missing from session", %{conn: conn} do
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
        |> get(~p"/device/authorize")

      assert redirected_to(conn) == ~p"/device"
    end

    test "redirects to /device when user is not logged in", %{conn: conn} do
      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{device_code_id: device_code.id})
        |> get(~p"/device/authorize")

      assert redirected_to(conn) == ~p"/device"
    end
  end

  describe "POST /device/authorize" do
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
        |> post(~p"/device/authorize")

      assert redirected_to(conn) == ~p"/device/success"
      assert get_session(conn, :device_code_id) == nil
    end

    test "redirects to /device with error when device code is expired", %{conn: conn} do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid_expired",
          "name" => "Expired User",
          "email" => "expired@example.com",
          "picture" => nil
        })

      # Use a non-existent device_code_id to trigger a :not_found error
      conn =
        conn
        |> init_test_session(%{
          "user_id" => user.id,
          device_code_id: Ecto.UUID.generate()
        })
        |> assign(:current_user, user)
        |> post(~p"/device/authorize")

      assert redirected_to(conn) == ~p"/device"
      assert get_session(conn, :device_code_id) == nil
    end

    test "redirects to /device when session is missing device_code_id", %{conn: conn} do
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
        |> post(~p"/device/authorize")

      assert redirected_to(conn) == ~p"/device"
    end

    test "redirects to /device when user is not logged in", %{conn: conn} do
      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{device_code_id: device_code.id})
        |> post(~p"/device/authorize")

      assert redirected_to(conn) == ~p"/device"
    end
  end

  describe "POST /device/cancel" do
    test "clears device_code_id from session and redirects to /device", %{conn: conn} do
      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        conn
        |> init_test_session(%{device_code_id: device_code.id})
        |> post(~p"/device/cancel")

      assert redirected_to(conn) == ~p"/device"
      assert get_session(conn, :device_code_id) == nil
    end
  end

  describe "GET /device/success" do
    test "renders the success page", %{conn: conn} do
      conn = get(conn, ~p"/device/success")
      assert html_response(conn, 200) =~ "signed in"
      assert html_response(conn, 200) =~ "close this tab"
    end
  end
end
