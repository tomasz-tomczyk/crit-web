defmodule CritWeb.UserSessionController do
  use CritWeb, :controller

  alias Crit.Accounts
  alias CritWeb.UserAuth

  # NOTE: plain string redirect targets used here pending Task 16, which wires
  # /users/log_in, /users/log_out, and /dashboard into the router and switches
  # these to ~p sigils.
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: "/users/log_in")

      user ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, user_params)
        |> redirect(to: "/dashboard")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out")
    |> UserAuth.log_out_user()
    |> redirect(to: "/")
  end
end
