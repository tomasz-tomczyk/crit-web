defmodule CritWeb.DashboardLive do
  use CritWeb, :live_view

  alias Crit.{Accounts, Reviews}

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

      stats = Reviews.dashboard_stats()
      chart_data = Reviews.activity_chart(30)
      max_count = chart_data |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end)

      socket =
        socket
        |> assign(:stats, stats)
        |> assign(:chart_data, chart_data)
        |> assign(:max_count, max_count)
        |> assign(:password_required, password_required)
        |> assign(:authenticated, authenticated)
        |> assign(:current_user, current_user)
        |> assign(:oauth_configured, oauth_configured)
        |> assign(:page_title, "Dashboard - Crit")
        |> assign(:noindex, true)

      socket =
        if authenticated do
          reviews = Reviews.list_reviews_with_counts()

          socket
          |> stream(:reviews, reviews)
          |> assign(:review_count, length(reviews))
        else
          socket
          |> assign(:review_count, 0)
        end

      socket =
        if authenticated && current_user do
          socket
          |> assign(:tokens, Accounts.list_tokens(current_user.id))
          |> assign(:new_token_plaintext, nil)
          |> assign(:new_token_name, "")
        else
          socket
          |> assign(:tokens, [])
          |> assign(:new_token_plaintext, nil)
          |> assign(:new_token_name, "")
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

  @impl true
  def handle_event("delete_review", %{"id" => id} = params, socket) do
    %{oauth_configured: oauth_configured, current_user: current_user} = socket.assigns
    owner_id = Map.get(params, "owner-id")

    authorized =
      if oauth_configured do
        current_user != nil && current_user.id == owner_id
      else
        true
      end

    if authorized do
      case Reviews.delete_review(id) do
        :ok ->
          reviews = Reviews.list_reviews_with_counts()
          stats = Reviews.dashboard_stats()

          {:noreply,
           socket
           |> stream(:reviews, reviews, reset: true)
           |> assign(:review_count, length(reviews))
           |> assign(:stats, stats)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete review.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You can only delete your own reviews.")}
    end
  end

  @doc false
  def session_opts(conn) do
    %{
      "admin_authenticated" => Plug.Conn.get_session(conn, :admin_authenticated),
      "user_id" => Plug.Conn.get_session(conn, :user_id)
    }
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

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
