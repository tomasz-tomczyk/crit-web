defmodule CritWeb.UserSessionController do
  use CritWeb, :controller

  alias Crit.Accounts
  alias CritWeb.UserAuth

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/users/log_in")

      user ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, user_params)
        |> redirect(to: ~p"/dashboard")
    end
  end

  def register(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome to crit!")
        |> UserAuth.log_in_user(user, %{})
        |> redirect(to: ~p"/dashboard")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Registration failed. Please check the form and try again.")
        |> redirect(to: ~p"/users/register")
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case conn.assigns.current_scope.user do
      nil ->
        # Link opened in a different browser / expired session.
        # `Accounts.update_user_email/2` pattern-matches on `%User{}` and
        # would raise FunctionClauseError → 500 if we passed nil through.
        conn
        |> put_flash(:error, "Please sign in to confirm your email change.")
        |> redirect(to: ~p"/users/log_in")

      user ->
        case Accounts.update_user_email(user, token) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Email updated")
            |> redirect(to: ~p"/users/settings")

          _ ->
            conn
            |> put_flash(:error, "Email change link is invalid or expired")
            |> redirect(to: ~p"/users/settings")
        end
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out")
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/")
  end
end
