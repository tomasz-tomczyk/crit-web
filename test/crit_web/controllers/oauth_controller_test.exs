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

    test "redirects to /device/authorize when device_code_id is in session" do
      {:ok, %{record: device_code}} = DeviceCodes.create_device_code()

      conn =
        build_conn()
        |> init_test_session(%{
          oauth_session_params: %{},
          device_code_id: device_code.id
        })
        |> get(~p"/auth/login/callback", %{"code" => "test_code"})

      assert redirected_to(conn) == ~p"/device/authorize"
      assert get_session(conn, "user_id") != nil
      assert get_session(conn, :device_code_id) == device_code.id
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
