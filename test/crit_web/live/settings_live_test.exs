defmodule CritWeb.SettingsLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    # Ensure OAuth is configured so the hook can redirect to login
    Application.put_env(:crit, :oauth_provider, [
      strategy: Assent.Strategy.Github,
      client_id: "test",
      client_secret: "test"
    ])

    on_exit(fn ->
      Application.delete_env(:crit, :oauth_provider)
    end)
  end

  defp login_user(conn) do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "settings_uid_#{System.unique_integer()}",
        "email" => "settings@example.com",
        "name" => "Settings User"
      })

    {init_test_session(conn, %{user_id: user.id}), user}
  end

  describe "mount requires user" do
    test "redirects to /auth/login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/auth/login?return_to=/settings"}}} =
               live(conn, ~p"/settings")
    end

    test "renders settings page when authenticated", %{conn: conn} do
      {conn, _user} = login_user(conn)

      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "Settings"
    end
  end
end
