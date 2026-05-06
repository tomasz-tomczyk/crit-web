defmodule CritWeb.UserSessionControllerTest do
  use CritWeb.ConnCase, async: false

  alias Crit.AccountsFixtures

  setup do
    Application.put_env(:crit, :selfhosted, true)
    on_exit(fn -> Application.put_env(:crit, :selfhosted, false) end)
    :ok
  end

  test "POST /users/log_in with valid creds redirects to dashboard", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => AccountsFixtures.valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/dashboard"
    assert get_session(conn, "user_id") == user.id
  end

  test "POST /users/log_in with invalid creds re-renders with error", %{conn: conn} do
    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => "no@one.com", "password" => "nope-nope-nope"}
      })

    assert redirected_to(conn) == ~p"/users/log_in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
  end

  test "DELETE /users/log_out clears session", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")

    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, "user_id")
  end
end
