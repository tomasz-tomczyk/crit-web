defmodule CritWeb.UserLoginLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    prev_oauth = Application.get_env(:crit, :oauth_provider)
    Application.put_env(:crit, :selfhosted, true)
    Application.put_env(:crit, :local_registration_enabled, true)

    on_exit(fn ->
      Application.put_env(:crit, :selfhosted, false)
      Application.put_env(:crit, :local_registration_enabled, true)

      if prev_oauth do
        Application.put_env(:crit, :oauth_provider, prev_oauth)
      else
        Application.delete_env(:crit, :oauth_provider)
      end
    end)

    :ok
  end

  test "renders form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/log_in")
    assert html =~ "Sign in"
    assert html =~ "Email"
    assert html =~ "Password"
  end

  test "shows OAuth CTA when provider configured", %{conn: conn} do
    Application.put_env(:crit, :oauth_provider,
      strategy: Assent.Strategy.Github,
      client_id: "x",
      client_secret: "y"
    )

    {:ok, _lv, html} = live(conn, ~p"/users/log_in")
    assert html =~ "Continue with GitHub"
  end

  test "hides forgot-password when mailer unconfigured", %{conn: conn} do
    prev = Application.get_env(:crit, Crit.Mailer, [])
    Application.put_env(:crit, Crit.Mailer, Keyword.put(prev, :adapter, Swoosh.Adapters.Local))
    on_exit(fn -> Application.put_env(:crit, Crit.Mailer, prev) end)

    {:ok, _lv, html} = live(conn, ~p"/users/log_in")
    refute html =~ "Forgot your password?"
  end

  test "shows forgot-password when mailer configured", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/log_in")
    assert html =~ "Forgot your password?"
  end
end
