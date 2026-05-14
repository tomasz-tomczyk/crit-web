defmodule CritWeb.OrgOverviewLive do
  use CritWeb, :live_view

  alias Crit.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization

    socket =
      socket
      |> assign(:page_title, "#{org.name} - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:org, org)
      |> assign(:is_admin, Scope.org_admin?(scope))
      |> assign(:orgs, Crit.Organizations.list_user_organizations(scope))

    {:ok, socket, layout: false}
  end
end
