defmodule CritWeb.OAuthControllerTest do
  use CritWeb.ConnCase, async: false

  alias Crit.DeviceCodes

  describe "DELETE /auth/logout" do
    test "clears user_id from session and redirects to /" do
      conn =
        build_conn()
        |> init_test_session(%{"user_id" => 42})
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, "user_id") == nil
    end
  end

  describe "GET /auth/login" do
    test "redirects to GitHub when provider is configured" do
      # config/test.exs sets up a stub GitHub provider
      conn = get(build_conn(), ~p"/auth/login")
      assert redirected_to(conn) =~ "github.com/login/oauth/authorize"
    end
  end

  describe "GET /auth/login/callback (happy path)" do
    setup do
      original = Application.get_env(:crit, :oauth_provider)

      Application.put_env(:crit, :oauth_provider,
        strategy: CritWeb.OAuthControllerTest.StubStrategy,
        client_id: "test",
        client_secret: "test"
      )

      on_exit(fn ->
        if original,
          do: Application.put_env(:crit, :oauth_provider, original),
          else: Application.delete_env(:crit, :oauth_provider)
      end)

      :ok
    end

    test "logs in user, sets session user_id, and redirects to dashboard" do
      conn =
        build_conn()
        |> init_test_session(%{oauth_session_params: %{}})
        |> get(~p"/auth/login/callback", %{"code" => "test_code"})

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_session(conn, "user_id") != nil
    end

    test "redirects to /auth/cli/authorize when device_code_id is in session" do
      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        build_conn()
        |> init_test_session(%{
          oauth_session_params: %{},
          device_code_id: device_code.id
        })
        |> get(~p"/auth/login/callback", %{"code" => "test_code"})

      assert redirected_to(conn) == ~p"/auth/cli/authorize"
      assert get_session(conn, "user_id") != nil
      assert get_session(conn, :device_code_id) == device_code.id
    end
  end

  describe "GET /auth/login return_to open-redirect guard" do
    # Exercises OAuthController.safe_return_to/1 by hitting the public login
    # endpoint and inspecting the session it stores. Only local "/path" values
    # are accepted; external URLs, protocol-relative URLs, and anything else
    # must be dropped (stored as nil → callback falls back to /dashboard).
    setup do
      original = Application.get_env(:crit, :oauth_provider)

      Application.put_env(:crit, :oauth_provider,
        strategy: CritWeb.OAuthControllerTest.StubStrategy,
        client_id: "test",
        client_secret: "test"
      )

      on_exit(fn ->
        if original,
          do: Application.put_env(:crit, :oauth_provider, original),
          else: Application.delete_env(:crit, :oauth_provider)
      end)

      :ok
    end

    test "stores a local /path return_to in session" do
      conn = get(build_conn(), ~p"/auth/login", %{"return_to" => "/r/abc123"})
      assert get_session(conn, :oauth_return_to) == "/r/abc123"
    end

    test "drops https://evil.com (full external URL)" do
      conn = get(build_conn(), ~p"/auth/login", %{"return_to" => "https://evil.com/steal"})
      assert get_session(conn, :oauth_return_to) == nil
    end

    test "drops //evil.com (protocol-relative URL)" do
      conn = get(build_conn(), ~p"/auth/login", %{"return_to" => "//evil.com/steal"})
      assert get_session(conn, :oauth_return_to) == nil
    end

    test "drops bare hostnames and other non-local values" do
      for bad <- ["evil.com", "javascript:alert(1)", "ftp://x", ""] do
        conn = get(build_conn(), ~p"/auth/login", %{"return_to" => bad})

        assert get_session(conn, :oauth_return_to) == nil,
               "expected #{inspect(bad)} to be dropped from session"
      end
    end

    test "callback redirects to / (default) when no return_to was stored" do
      conn =
        build_conn()
        |> init_test_session(%{oauth_session_params: %{}})
        |> get(~p"/auth/login/callback", %{"code" => "test_code"})

      # No oauth_return_to in session → callback falls back to /dashboard.
      assert redirected_to(conn) == ~p"/dashboard"
    end
  end

  defmodule StubStrategy do
    @moduledoc false

    def authorize_url(config) do
      {:ok, %{url: "https://example.com/authorize", session_params: %{}}}
      |> then(fn result -> result end)
      |> tap(fn _ -> config end)
    end

    def callback(_config, _params) do
      {:ok,
       %{
         user: %{
           "sub" => "stub_uid_#{System.unique_integer([:positive])}",
           "name" => "Stub User",
           "email" => "stub@example.com",
           "picture" => nil
         }
       }}
    end
  end
end
