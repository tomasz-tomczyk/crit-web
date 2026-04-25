defmodule CritWeb.DashboardLive do
  use CritWeb, :live_view

  alias Crit.Reviews

  import CritWeb.Helpers, only: [time_ago: 1, split_path: 1]
  import CritWeb.Components.ReviewSnippet

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    reviews = Reviews.list_user_reviews_with_counts(current_user.id)

    socket =
      socket
      |> assign(:page_title, "Dashboard - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> stream(:reviews, reviews)
      |> assign(:review_count, length(reviews))

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("delete_review", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    case Reviews.delete_review(id, owner_id: current_user.id) do
      :ok ->
        reviews = Reviews.list_user_reviews_with_counts(current_user.id)

        {:noreply,
         socket
         |> stream(:reviews, reviews, reset: true)
         |> assign(:review_count, length(reviews))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can only delete your own reviews.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete review.")}
    end
  end
end
