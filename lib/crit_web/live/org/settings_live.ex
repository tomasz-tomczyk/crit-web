defmodule CritWeb.Org.SettingsLive do
  use CritWeb, :live_view

  alias Crit.Organizations
  alias Crit.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization

    changeset = Organizations.change_organization(org)

    socket =
      socket
      |> assign(:page_title, "Organization Settings - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:org, org)
      |> assign(:is_admin, Scope.org_admin?(scope))
      |> assign(:orgs, Organizations.list_user_organizations(scope))
      |> assign(:form, to_form(changeset, as: "org"))
      |> assign(:delete_confirmation, "")

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("validate", %{"org" => params}, socket) do
    changeset =
      socket.assigns.org
      |> Organizations.change_organization(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "org"))}
  end

  @impl true
  def handle_event("save", %{"org" => params}, socket) do
    case Organizations.update_organization(
           socket.assigns.current_scope,
           socket.assigns.org,
           params
         ) do
      {:ok, updated_org} ->
        # If slug changed, redirect to the new URL
        if updated_org.slug != socket.assigns.org.slug do
          {:noreply,
           socket
           |> put_flash(:info, "Organization updated.")
           |> push_navigate(to: ~p"/orgs/#{updated_org.slug}/settings")}
        else
          scope =
            Scope.put_organization(
              socket.assigns.current_scope,
              updated_org,
              socket.assigns.current_scope.membership
            )

          {:noreply,
           socket
           |> assign(:current_scope, scope)
           |> assign(:org, updated_org)
           |> assign(
             :form,
             to_form(Organizations.change_organization(updated_org), as: "org")
           )
           |> put_flash(:info, "Organization updated.")}
        end

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "org"))}
    end
  end

  @impl true
  def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  @impl true
  def handle_event("delete_org", _params, socket) do
    if socket.assigns.delete_confirmation != socket.assigns.org.slug do
      {:noreply, put_flash(socket, :error, "Slug does not match. Deletion cancelled.")}
    else
      case Organizations.delete_organization(
             socket.assigns.current_scope,
             socket.assigns.org
           ) do
        {:ok, _org} ->
          {:noreply,
           socket
           |> put_flash(:info, "Organization deleted.")
           |> push_navigate(to: ~p"/orgs")}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, "Not authorized.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not delete organization.")}
      end
    end
  end

  @impl true
  def handle_event("leave", _params, socket) do
    case Organizations.leave_organization(
           socket.assigns.current_scope,
           socket.assigns.org
         ) do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: ~p"/orgs")}

      {:error, :last_admin} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You are the last admin. Transfer admin role before leaving."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not leave organization.")}
    end
  end
end
