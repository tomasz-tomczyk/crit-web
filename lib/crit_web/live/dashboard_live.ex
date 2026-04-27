defmodule CritWeb.DashboardLive do
  use CritWeb, :live_view

  alias Crit.Reviews

  import CritWeb.Components.ReviewSnippet
  import CritWeb.Components.ReviewListingHeader

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    reviews = Reviews.list_user_reviews_with_counts(current_user.id)

    socket =
      socket
      |> assign(:page_title, "Dashboard - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:instance_url, CritWeb.Endpoint.url())
      |> stream(:reviews, reviews)
      |> assign(:review_count, length(reviews))

    {:ok, socket, layout: false}
  end
end
