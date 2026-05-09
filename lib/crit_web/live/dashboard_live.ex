defmodule CritWeb.DashboardLive do
  use CritWeb, :live_view

  alias Crit.{Accounts, Reviews}

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
      |> assign(
        :marketing_opted_in,
        if(has_user?, do: Accounts.marketing_opted_in?(socket.assigns.current_scope.user), else: false)
      )
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
