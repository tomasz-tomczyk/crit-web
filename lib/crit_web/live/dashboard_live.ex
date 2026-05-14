defmodule CritWeb.DashboardLive do
  use CritWeb, :live_view

  alias Crit.{Accounts, Reviews}
  alias Crit.Organizations

  import CritWeb.Components.ReviewSnippet
  import CritWeb.Components.ReviewListingHeader

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    user = scope.user
    reviews = Reviews.list_user_reviews_with_counts(scope)
    orgs = Organizations.list_user_organizations(scope)

    socket =
      socket
      |> assign(:page_title, "My Reviews - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:instance_url, CritWeb.Endpoint.url())
      |> assign(:marketing_opted_in, Accounts.marketing_opted_in?(user))
      |> assign(:orgs, orgs)
      |> stream(:reviews, reviews)
      |> assign(:review_count, length(reviews))

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("toggle_marketing_consent", _params, socket) do
    case Accounts.toggle_marketing_consent(
           socket.assigns.current_scope.user,
           "dashboard_checkbox"
         ) do
      {:ok, new_value} ->
        {:noreply, assign(socket, :marketing_opted_in, new_value)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference.")}
    end
  end
end
