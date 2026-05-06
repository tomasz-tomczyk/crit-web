defmodule CritWeb.UserSettingsLive do
  use CritWeb, :live_view

  alias Crit.Accounts

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:has_password, is_binary(user.hashed_password))
     |> assign(:email_form, to_form(Accounts.change_user_email(user), as: "user"))
     |> assign(:password_form, to_form(Accounts.change_user_password(user), as: "user"))}
  end

  def handle_event("validate_email", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    changeset =
      user
      |> Accounts.change_user_email(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :email_form, to_form(changeset, as: "user"))}
  end

  def handle_event("update_email", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user
    changeset = Accounts.change_user_email(user, params)

    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, applied_user} ->
        Accounts.deliver_update_email_instructions(
          user,
          applied_user.email,
          fn token ->
            url(~p"/users/settings/confirm_email/#{token}")
          end
        )

        {:noreply,
         socket
         |> put_flash(:info, "A confirmation link has been sent to the new address.")
         |> assign(:email_form, to_form(Accounts.change_user_email(user), as: "user"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(changeset, as: "user"))}
    end
  end

  def handle_event("validate_password", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    changeset =
      user
      |> Accounts.change_user_password(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :password_form, to_form(changeset, as: "user"))}
  end

  def handle_event("update_password", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    result =
      if socket.assigns.has_password do
        Accounts.update_user_password(user, params["current_password"] || "", params)
      else
        # First-time set: skip current_password check, hash via password_changeset.
        user
        |> Crit.User.password_changeset(params)
        |> Crit.Repo.update()
      end

    case result do
      {:ok, _updated} ->
        msg = if socket.assigns.has_password, do: "Password updated.", else: "Password set."

        {:noreply,
         socket
         |> put_flash(:info, msg)
         |> assign(:has_password, true)
         |> assign(:password_form, to_form(Accounts.change_user_password(user), as: "user"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: "user"))}
    end
  end
end
