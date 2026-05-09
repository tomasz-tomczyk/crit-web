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
     |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
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
    # Validate only here — the controller's `register/2` owns the single
    # insert. If we also call `register_user/1` in the LiveView, the
    # subsequent form POST hits the unique-email constraint and the user
    # is never logged in.
    changeset =
      %User{}
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      {:noreply,
       socket
       |> assign(:trigger_submit, true)
       |> assign(:form, to_form(changeset, as: "user"))}
    else
      {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
    end
  end
end
