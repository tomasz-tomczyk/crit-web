defmodule CritWeb.ReviewsLive do
  use CritWeb, :live_view

  alias Crit.Reviews

  @per_page 15

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    {reviews, count} = Reviews.list_user_reviews_paginated(scope, page: 1, per_page: @per_page)

    socket =
      socket
      |> assign(:page_title, "My reviews - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:orgs, Crit.Organizations.list_user_organizations(scope))
      |> assign(:review_count, count)
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> stream(:reviews, reviews)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("change_page", %{"page" => page}, socket) do
    page =
      case Integer.parse(page) do
        {n, ""} -> n
        _ -> socket.assigns.page
      end

    total_pages = max(1, ceil(socket.assigns.review_count / @per_page))
    page = max(1, min(page, total_pages))

    scope = socket.assigns.current_scope
    {reviews, count} = Reviews.list_user_reviews_paginated(scope, page: page, per_page: @per_page)

    socket =
      socket
      |> assign(:page, page)
      |> assign(:review_count, count)
      |> stream(:reviews, reviews, reset: true)

    {:noreply, socket}
  end
end
