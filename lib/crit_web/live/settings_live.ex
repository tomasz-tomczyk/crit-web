defmodule CritWeb.SettingsLive do
  use CritWeb, :live_view

  alias Crit.Accounts

  import CritWeb.Helpers, only: [time_ago: 1]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "Settings - Crit")
      |> assign(:noindex, true)
      |> assign(:tokens, Accounts.list_tokens(user.id))
      |> assign(:new_token_plaintext, nil)
      |> assign(:new_token_name, "")
      |> assign(:delete_confirmation, "")
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("create_token", %{"name" => name}, socket) do
    user = socket.assigns.current_user

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
    user = socket.assigns.current_user

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
    user = socket.assigns.current_user

    if socket.assigns.delete_confirmation == delete_confirmation_text(user) do
      case Accounts.delete_account(user) do
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
end
