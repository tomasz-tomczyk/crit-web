defmodule CritWeb.UserSettingsLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Crit.Accounts
  alias Crit.AccountsFixtures

  setup %{conn: conn} do
    Application.put_env(:crit, :selfhosted, true)
    on_exit(fn -> Application.put_env(:crit, :selfhosted, false) end)

    user = AccountsFixtures.user_fixture()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  describe "change email" do
    test "sends confirmation email and does not change email immediately", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _} = live(conn, ~p"/users/settings")

      lv
      |> form("#email_form", user: %{email: "newaddr@example.com"})
      |> render_submit()

      assert_email_sent()

      reloaded = Accounts.get_user_by_email(user.email)
      assert reloaded.id == user.id
      assert is_nil(Accounts.get_user_by_email("newaddr@example.com"))
    end
  end

  describe "change password" do
    test "rejects invalid current password", %{conn: conn, user: user} do
      {:ok, lv, _} = live(conn, ~p"/users/settings")

      html =
        lv
        |> form("#password_form",
          user: %{
            current_password: "wrong-password",
            password: "new-secret-1234",
            password_confirmation: "new-secret-1234"
          }
        )
        |> render_submit()

      assert html =~ "is not valid"
      refute Crit.User.valid_password?(Accounts.get_user_by_email(user.email), "new-secret-1234")
    end

    test "happy path with valid current password", %{conn: conn, user: user} do
      {:ok, lv, _} = live(conn, ~p"/users/settings")

      lv
      |> form("#password_form",
        user: %{
          current_password: AccountsFixtures.valid_user_password(),
          password: "brand-new-pwd-1234",
          password_confirmation: "brand-new-pwd-1234"
        }
      )
      |> render_submit()

      assert Crit.User.valid_password?(
               Accounts.get_user_by_email(user.email),
               "brand-new-pwd-1234"
             )
    end
  end

  describe "OAuth-only user (no hashed_password)" do
    test "sets password without current-password field; UI shows 'Set a password'", %{conn: _conn} do
      oauth_user = AccountsFixtures.oauth_user_fixture()
      conn = log_in_user(Phoenix.ConnTest.build_conn(), oauth_user)

      {:ok, lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Set a password"
      refute html =~ "Current password"

      lv
      |> form("#password_form",
        user: %{password: "first-time-pwd-1234", password_confirmation: "first-time-pwd-1234"}
      )
      |> render_submit()

      assert Crit.User.valid_password?(
               Accounts.get_user_by_email(oauth_user.email),
               "first-time-pwd-1234"
             )
    end
  end

  describe "confirm_email action" do
    test "invalid token redirects to settings with error flash", %{conn: conn} do
      conn = get(conn, ~p"/users/settings/confirm_email/garbage-token")
      assert redirected_to(conn) == "/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or expired"
    end

    test "redirects unauthenticated visitors to login (no 500)" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> get(~p"/users/settings/confirm_email/anything")

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Please sign in"
    end
  end
end
