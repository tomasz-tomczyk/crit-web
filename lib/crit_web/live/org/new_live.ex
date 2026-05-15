defmodule CritWeb.Org.NewLive do
  use CritWeb, :live_view

  alias Crit.Organizations
  alias Crit.Organizations.Organization

  @impl true
  def mount(_params, _session, socket) do
    changeset = Organization.create_changeset(%Organization{}, %{})

    socket =
      socket
      |> assign(:page_title, "New Organization - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:orgs, Organizations.list_user_organizations(socket.assigns.current_scope))
      |> assign(:form, to_form(changeset, as: "org"))
      |> assign(:slug_manually_edited, false)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("validate", %{"org" => params}, socket) do
    params =
      if socket.assigns.slug_manually_edited do
        params
      else
        Map.put(params, "slug", Organization.generate_slug(params["name"] || ""))
      end

    changeset =
      %Organization{}
      |> Organization.create_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "org"))}
  end

  @impl true
  def handle_event("slug_edited", _params, socket) do
    {:noreply, assign(socket, :slug_manually_edited, true)}
  end

  @impl true
  def handle_event("save", %{"org" => params}, socket) do
    case Organizations.create_organization(socket.assigns.current_scope, params) do
      {:ok, %Organization{} = org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization created.")
         |> push_navigate(to: ~p"/orgs/#{org.slug}/settings")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "org"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create organization.")}
    end
  end
end
