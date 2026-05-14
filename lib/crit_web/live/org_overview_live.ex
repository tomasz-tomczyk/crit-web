defmodule CritWeb.OrgOverviewLive do
  use CritWeb, :live_view

  alias Crit.Accounts.Scope
  alias Crit.Organizations

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    members = Organizations.list_members(scope, org)

    socket =
      socket
      |> assign(:page_title, "#{org.name} - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:org, org)
      |> assign(:is_admin, Scope.org_admin?(scope))
      |> assign(:orgs, Organizations.list_user_organizations(scope))
      |> assign(:members, members)
      |> assign(:greeting, greeting(scope))

    {:ok, socket, layout: false}
  end

  defp greeting(%Scope{user: %{name: name}}) when is_binary(name) and name != "",
    do: "Welcome back, #{name}"

  defp greeting(_scope), do: "Welcome back"
end
