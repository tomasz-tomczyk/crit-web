defmodule CritWeb.Org.SelectLive do
  use CritWeb, :live_view

  alias Crit.Organizations

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:page_title, "Organizations - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:orgs, Organizations.list_user_organizations(scope))
      |> assign(:invites, Organizations.list_pending_invites_for_email(scope))

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("dismiss_invite", %{"id" => invite_id}, socket) do
    invites = Enum.reject(socket.assigns.invites, &(&1.id == invite_id))
    {:noreply, assign(socket, :invites, invites)}
  end
end
