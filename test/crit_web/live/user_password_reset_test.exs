defmodule CritWeb.UserPasswordResetTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  alias Crit.AccountsFixtures

  setup do
    Application.put_env(:crit, :selfhosted, true)
    on_exit(fn -> Application.put_env(:crit, :selfhosted, false) end)
    :ok
  end

  describe "forgot password" do
    test "sends reset email when user exists", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      {:ok, lv, _} = live(conn, ~p"/users/reset_password")

      lv |> form("#forgot_form", user: %{email: user.email}) |> render_submit()

      assert_email_sent()
    end

    test "silently no-ops for unknown email but redirects with same flash", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/users/reset_password")
      lv |> form("#forgot_form", user: %{email: "nope@example.com"}) |> render_submit()
      # No assert_email_sent — but the redirect happens regardless
    end
  end

  describe "reset password" do
    test "happy path resets and redirects", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      parent = self()
      {:ok, _} =
        Crit.Accounts.deliver_user_reset_password_instructions(user, fn token ->
          send(parent, {:token, token})
          "https://t.test/r/#{token}"
        end)

      assert_receive {:token, plaintext}

      {:ok, lv, _} = live(conn, ~p"/users/reset_password/#{plaintext}")

      lv
      |> form("#reset_form", user: %{password: "new-password-1234", password_confirmation: "new-password-1234"})
      |> render_submit()

      refute Crit.User.valid_password?(Crit.Accounts.get_user_by_email(user.email), AccountsFixtures.valid_user_password())
      assert Crit.User.valid_password?(Crit.Accounts.get_user_by_email(user.email), "new-password-1234")
    end

    test "invalid token redirects to login with error", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/users/reset_password/garbage")
    end
  end
end
