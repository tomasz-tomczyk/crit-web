defmodule CritWeb.TokensLive do
  use CritWeb, :live_view

  alias Crit.Accounts

  @impl true
  def mount(_params, session, socket) do
    if Application.get_env(:crit, :selfhosted) do
      password_required = Application.get_env(:crit, :admin_password) != nil
      admin_authenticated = Map.get(session, "admin_authenticated", false) == true

      current_user =
        case Map.get(session, "user_id") do
          nil ->
            nil

          user_id ->
            case Accounts.get_user(user_id) do
              {:ok, user} -> user
              {:error, :not_found} -> nil
            end
        end

      oauth_configured = Application.get_env(:crit, :oauth_provider) != nil

      authenticated =
        cond do
          oauth_configured -> current_user != nil
          password_required -> admin_authenticated
          true -> true
        end

      socket =
        socket
        |> assign(:password_required, password_required)
        |> assign(:authenticated, authenticated)
        |> assign(:current_user, current_user)
        |> assign(:page_title, "API Tokens - Crit")
        |> assign(:noindex, true)

      socket =
        if authenticated && current_user do
          socket
          |> assign(:tokens, Accounts.list_tokens(current_user.id))
          |> assign(:new_token_plaintext, nil)
          |> assign(:new_token_name, "")
        else
          {:ok, redirect(socket, to: ~p"/dashboard")}
          |> elem(1)
        end

      {:ok, socket, layout: false}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
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

  @doc false
  def session_opts(conn) do
    %{
      "admin_authenticated" => Plug.Conn.get_session(conn, :admin_authenticated),
      "user_id" => Plug.Conn.get_session(conn, :user_id)
    }
  end

  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> "#{div(diff, 604_800)}w ago"
    end
  end
end
