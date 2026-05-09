defmodule CritWeb.DashboardLive do
  use CritWeb, :live_view

  alias Crit.Reviews

  import CritWeb.Components.ReviewSnippet
  import CritWeb.Components.ReviewListingHeader

  @impl true
  def mount(_params, _session, socket) do
    has_user? = socket.assigns.current_scope.user != nil

    reviews =
      if has_user?,
        do: Reviews.list_user_reviews_with_counts(socket.assigns.current_scope),
        else: []

    socket =
      socket
      |> assign(:page_title, "Dashboard - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:instance_url, CritWeb.Endpoint.url())
      |> assign(:auth_configured, Crit.Config.auth_configured?())
      |> stream(:reviews, reviews)
      |> assign(:review_count, length(reviews))

    {:ok, socket, layout: false}
  end
end
