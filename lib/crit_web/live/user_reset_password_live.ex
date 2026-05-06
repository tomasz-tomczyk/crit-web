defmodule CritWeb.UserResetPasswordLive do
  use CritWeb, :live_view

  alias Crit.Accounts

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Reset link is invalid or has expired.")
         |> redirect(to: "/users/log_in")}

      user ->
        changeset = Accounts.change_user_password(user)
        {:ok, assign(socket, user: user, token: token, form: to_form(changeset, as: "user"))}
    end
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset. Sign in with your new password.")
         |> redirect(to: "/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end
end
