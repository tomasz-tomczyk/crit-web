defmodule CritWeb.UserRegistrationLive do
  use CritWeb, :live_view

  alias Crit.Accounts
  alias Crit.User

  def mount(_params, _session, socket) do
    # Router-level plug `:registration_enabled` (Task 16) returns 404 for
    # disabled instances on the GET path before we ever reach mount/3, so by
    # the time we're here registration is enabled.
    changeset = Accounts.change_user_registration(%User{})

    {:ok,
     socket
     |> assign(:trigger_submit, false)
     |> assign(:form, to_form(changeset, as: "user"))}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.register_user(params) do
      {:ok, _user} ->
        # Hand off to the controller via phx-trigger-action — the form
        # POSTs to /users/register which calls UserAuth.log_in_user/3.
        # We re-render with the same params so the controller receives them.
        changeset = Accounts.change_user_registration(%User{}, params)

        {:noreply,
         socket
         |> assign(:trigger_submit, true)
         |> assign(:form, to_form(changeset, as: "user"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
    end
  end
end
