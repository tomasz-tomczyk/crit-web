defmodule CritWeb.UserRegistrationLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Crit.AccountsFixtures

  setup do
    Application.put_env(:crit, :selfhosted, true)
    Application.put_env(:crit, :local_registration_enabled, true)

    on_exit(fn ->
      Application.put_env(:crit, :selfhosted, false)
      Application.put_env(:crit, :local_registration_enabled, true)
    end)

    :ok
  end

  test "renders registration page", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/register")
    assert html =~ "Create your account"
  end

  test "rejects invalid email", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/users/register")

    result =
      lv
      |> form("#registration_form", user: %{email: "x", password: "supersecret-1234"})
      |> render_change()

    assert result =~ "must have the @ sign"
  end

  test "happy path creates user and redirects", %{conn: conn} do
    email = AccountsFixtures.unique_user_email()
    pw = AccountsFixtures.valid_user_password()

    conn = post(conn, ~p"/users/register", %{"user" => %{"email" => email, "password" => pw}})
    assert redirected_to(conn) == ~p"/dashboard"
    assert Crit.Accounts.get_user_by_email(email)
  end

  test "happy path: registration creates user and authenticates session", %{conn: conn} do
    email = AccountsFixtures.unique_user_email()
    pw = AccountsFixtures.valid_user_password()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post(~p"/users/register", %{"user" => %{"email" => email, "password" => pw}})

    assert redirected_to(conn) == ~p"/dashboard"
    assert get_session(conn, "user_id")
    assert Crit.Accounts.get_user_by_email(email)
  end

  test "404 when registration disabled", %{conn: conn} do
    Application.put_env(:crit, :local_registration_enabled, false)
    on_exit(fn -> Application.put_env(:crit, :local_registration_enabled, true) end)

    # The RegistrationEnabled plug calls send_resp(404, ...) + halt,
    # which is a normal response (not an exception). Don't use
    # assert_error_sent — that's for raised exceptions.
    conn = get(conn, ~p"/users/register")
    assert conn.status == 404
  end
end
