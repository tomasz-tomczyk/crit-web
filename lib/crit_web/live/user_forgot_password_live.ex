defmodule CritWeb.UserForgotPasswordLive do
  use CritWeb, :live_view

  alias Crit.Accounts

  def mount(_params, _session, socket) do
    if Crit.Mailer.configured?() do
      {:ok, assign(socket, form: to_form(%{}, as: "user"))}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  def handle_event("send", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(user, fn token ->
        unverified_url(socket, "/users/reset_password/#{token}")
      end)
    end

    {:noreply,
     socket
     |> put_flash(:info, "If that email is registered, we've sent a reset link.")
     |> redirect(to: "/users/log_in")}
  end
end
