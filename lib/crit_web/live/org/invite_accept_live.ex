defmodule CritWeb.Org.InviteAcceptLive do
  use CritWeb, :live_view

  alias Crit.Organizations
  alias Crit.Organizations.OrganizationInvite

  @impl true
  def mount(%{"token" => raw_token}, _session, socket) do
    user = socket.assigns.current_scope.user

    {status, invite} =
      case Organizations.get_invite_by_raw_token(raw_token) do
        {:ok, invite} ->
          cond do
            OrganizationInvite.expired?(invite) ->
              {:expired, invite}

            String.downcase(invite.email) != String.downcase(user.email || "") ->
              {:email_mismatch, invite}

            true ->
              {:ok, invite}
          end

        {:error, _} ->
          {:not_found, nil}
      end

    socket =
      socket
      |> assign(:page_title, "Accept Invitation - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:status, status)
      |> assign(:invite, invite)
      |> assign(:raw_token, raw_token)

    {:ok, socket, layout: false}
  end
end
