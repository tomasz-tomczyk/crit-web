defmodule CritWeb.UserSessionController do
  use CritWeb, :controller

  require Logger

  alias Crit.Accounts
  alias CritWeb.UserAuth

  def create(conn, %{"user" => user_params} = params) do
    %{"email" => email, "password" => password} = user_params
    return_to = sanitize_return_to(params["return_to"])

    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: login_path(return_to))

      user ->
        # Re-assert role from ADMIN_EMAILS on every login. If the operator
        # added/removed this email from ADMIN_EMAILS since their last login,
        # the role is updated here without waiting for the next app boot.
        {:ok, user} = Accounts.apply_role_for_email(user)

        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, user_params)
        |> redirect(to: return_to || ~p"/dashboard")
    end
  end

  def register(conn, %{"user" => user_params} = params) do
    return_to = sanitize_return_to(params["return_to"])

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        if user_params["marketing_opt_in"] == "true" do
          case Accounts.toggle_marketing_consent(user, "registration_checkbox") do
            {:ok, _} ->
              :ok

            {:error, changeset} ->
              Logger.error("Failed to record marketing consent: #{inspect(changeset.errors)}")
          end
        end

        conn
        |> put_flash(:info, "Welcome to crit!")
        |> UserAuth.log_in_user(user, %{})
        |> redirect(to: return_to || ~p"/dashboard")

      {:error, changeset} ->
        conn
        |> put_flash(:error, registration_error_message(changeset))
        |> redirect(to: ~p"/users/register")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out")
    |> UserAuth.log_out_user()
    |> redirect(to: ~p"/")
  end

  # Only allow same-origin path redirects to prevent open-redirect via return_to.
  defp sanitize_return_to(nil), do: nil
  defp sanitize_return_to("/" <> _ = path), do: path
  defp sanitize_return_to(_), do: nil

  defp login_path(nil), do: ~p"/users/log_in"
  defp login_path(return_to), do: "/users/log_in?return_to=#{URI.encode_www_form(return_to)}"

  defp registration_error_message(changeset) do
    cond do
      email_taken?(changeset) ->
        "An account with that email already exists. Try signing in instead."

      true ->
        "Registration failed. Please check the form and try again."
    end
  end

  defp email_taken?(changeset) do
    case Keyword.get(changeset.errors, :email) do
      {msg, _} when is_binary(msg) -> msg =~ "taken" or msg =~ "already"
      _ -> false
    end
  end
end
