defmodule CritWeb.TokensLive do
  use CritWeb, :live_view

  alias Crit.Accounts

  import CritWeb.Helpers, only: [time_ago: 1]

  on_mount {CritWeb.Live.Hooks, :require_authenticated_user}

  @impl true
  def mount(_params, _session, socket) do
    %{authenticated: authenticated, current_user: current_user} = socket.assigns

    socket =
      socket
      |> assign(:page_title, "API Tokens - Crit")
      |> assign(:noindex, true)

    socket =
      if authenticated && current_user do
        socket
        |> assign(:tokens, Accounts.list_tokens(current_user.id))
        |> assign(:new_token_plaintext, nil)
        |> assign(:new_token_name, "")
      else
        redirect(socket, to: ~p"/dashboard")
      end

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("create_token", %{"name" => name}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "Not authenticated.")}

      user ->
        case Accounts.create_token(user, name) do
          {:ok, {plaintext, _token}} ->
            tokens = Accounts.list_tokens(user.id)

            {:noreply,
             socket
             |> assign(:tokens, tokens)
             |> assign(:new_token_plaintext, plaintext)
             |> assign(:new_token_name, "")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to create token.")}
        end
    end
  end

  @impl true
  def handle_event("revoke_token", %{"id" => id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "Not authenticated.")}

      user ->
        case Accounts.revoke_token(id, user.id) do
          :ok ->
            tokens = Accounts.list_tokens(user.id)

            {:noreply,
             socket
             |> assign(:tokens, tokens)
             |> assign(:new_token_plaintext, nil)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to revoke token.")}
        end
    end
  end

  @impl true
  def handle_event("dismiss_token", _params, socket) do
    {:noreply, assign(socket, :new_token_plaintext, nil)}
  end
end
