defmodule CritWeb.SettingsLive do
  use CritWeb, :live_view

  alias Crit.Accounts
  alias Crit.Accounts.Scope
  alias Crit.Organizations

  import CritWeb.Helpers, only: [time_ago: 1]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    local_registration_enabled =
      Application.get_env(:crit, :local_registration_enabled, true) == true

    socket =
      socket
      |> assign(:page_title, "Settings - Crit")
      |> assign(:noindex, true)
      |> assign(:tokens, Accounts.list_tokens(user.id))
      |> assign(:new_token_plaintext, nil)
      |> assign(:new_token_name, "")
      |> assign(:delete_confirmation, "")
      |> assign(:keep_reviews, user.keep_reviews)
      |> assign(:marketing_opted_in, Accounts.marketing_opted_in?(user))
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:orgs, Organizations.list_user_organizations(socket.assigns.current_scope))
      |> assign(:local_registration_enabled, local_registration_enabled)
      |> assign(:has_password, is_binary(user.hashed_password))
      |> assign(:can_edit_email, is_nil(user.provider) and local_registration_enabled)
      |> assign(:profile_form, to_form(Accounts.change_user_profile(user), as: "user"))
      |> assign(:password_form, to_form(Accounts.change_user_password(user), as: "user"))
      |> assign(:orgs, Organizations.list_user_organizations(socket.assigns.current_scope))

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("validate_profile", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user
    params = filter_profile_params(params, socket.assigns.can_edit_email)

    changeset =
      user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :profile_form, to_form(changeset, as: "user"))}
  end

  @impl true
  def handle_event("update_profile", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user
    params = filter_profile_params(params, socket.assigns.can_edit_email)

    case Accounts.update_user_profile(user, params) do
      {:ok, updated} ->
        scope = Scope.put_user(socket.assigns.current_scope, updated)

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> put_flash(:info, "Profile updated.")
         |> assign(:profile_form, to_form(Accounts.change_user_profile(updated), as: "user"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, as: "user"))}
    end
  end

  @impl true
  def handle_event("validate_password", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    changeset =
      user
      |> Accounts.change_user_password(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :password_form, to_form(changeset, as: "user"))}
  end

  @impl true
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
        # Invalidate any "remember me" cookies issued to other devices so a
        # password change actually rotates persistent auth.
        Crit.Repo.delete_all(
          Crit.Accounts.UserToken.by_user_and_contexts_query(user, ["remember_me"])
        )

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

  @impl true
  def handle_event("toggle_keep_reviews", _params, socket) do
    %{current_scope: scope} = socket.assigns
    user = scope.user
    new_value = !socket.assigns.keep_reviews

    case Accounts.update_keep_reviews(user, new_value) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:keep_reviews, new_value)
         |> assign(:current_scope, Scope.put_user(scope, updated_user))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update setting.")}
    end
  end

  @impl true
  def handle_event("toggle_marketing_consent", _params, socket) do
    case Accounts.toggle_marketing_consent(socket.assigns.current_scope.user, "settings_toggle") do
      {:ok, new_value} ->
        {:noreply, assign(socket, :marketing_opted_in, new_value)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference.")}
    end
  end

  @impl true
  def handle_event("create_token", %{"name" => name}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.create_token(user, name) do
      {:ok, {plaintext, _token}} ->
        {:noreply,
         socket
         |> assign(:tokens, Accounts.list_tokens(user.id))
         |> assign(:new_token_plaintext, plaintext)
         |> assign(:new_token_name, "")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create token.")}
    end
  end

  @impl true
  def handle_event("revoke_token", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.revoke_token(id, user.id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:tokens, Accounts.list_tokens(user.id))
         |> assign(:new_token_plaintext, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke token.")}
    end
  end

  @impl true
  def handle_event("dismiss_token", _params, socket) do
    {:noreply, assign(socket, :new_token_plaintext, nil)}
  end

  @impl true
  def handle_event("validate_delete", %{"confirmation" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  @impl true
  def handle_event("delete_account", _params, socket) do
    user = socket.assigns.current_scope.user

    if socket.assigns.delete_confirmation == delete_confirmation_text(user) do
      case Accounts.delete_user(user) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Your account has been deleted.")
           |> redirect(to: ~p"/")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete account. Please try again.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Confirmation text does not match.")}
    end
  end

  defp delete_confirmation_text(user) do
    user.email || user.name || "delete my account"
  end

  # Drop the email key entirely when the user can't edit it, so a stray submitted
  # value (e.g. via devtools) cannot bypass the visibility gate.
  defp filter_profile_params(params, true), do: params
  defp filter_profile_params(params, false), do: Map.delete(params, "email")
end
