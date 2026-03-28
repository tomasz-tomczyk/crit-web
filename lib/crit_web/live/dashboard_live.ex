defmodule CritWeb.DashboardLive do
  use CritWeb, :live_view

  alias Crit.Reviews

  import CritWeb.Helpers, only: [time_ago: 1]

  on_mount {CritWeb.Live.Hooks, :require_authenticated_user}

  @impl true
  def mount(_params, _session, socket) do
    %{authenticated: authenticated} = socket.assigns

    stats = Reviews.dashboard_stats()
    chart_data = Reviews.activity_chart(30)
    max_count = chart_data |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end)

    socket =
      socket
      |> assign(:stats, stats)
      |> assign(:chart_data, chart_data)
      |> assign(:max_count, max_count)
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

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("delete_review", %{"id" => id}, socket) do
    %{oauth_configured: oauth_configured, current_user: current_user} = socket.assigns

    opts =
      if oauth_configured && current_user do
        [owner_id: current_user.id]
      else
        []
      end

    case Reviews.delete_review(id, opts) do
      :ok ->
        reviews = Reviews.list_reviews_with_counts()
        stats = Reviews.dashboard_stats()

        {:noreply,
         socket
         |> stream(:reviews, reviews, reset: true)
         |> assign(:review_count, length(reviews))
         |> assign(:stats, stats)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only delete your own reviews.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete review.")}
    end
  end

  @doc false
  def session_opts(conn) do
    %{
      "admin_authenticated" => Plug.Conn.get_session(conn, "admin_authenticated"),
      "user_id" => Plug.Conn.get_session(conn, "user_id")
    }
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
