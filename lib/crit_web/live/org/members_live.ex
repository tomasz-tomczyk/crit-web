defmodule CritWeb.Org.MembersLive do
  use CritWeb, :live_view

  alias Crit.Accounts
  alias Crit.Organizations
  alias Crit.Organizations.OrgNotifier
  alias Crit.Accounts.Scope

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    is_admin = Scope.org_admin?(scope)

    socket =
      socket
      |> assign(:page_title, "Members - Crit")
      |> assign(:noindex, true)
      |> assign(:selfhosted, Application.get_env(:crit, :selfhosted) == true)
      |> assign(:org, org)
      |> assign(:is_admin, is_admin)
      |> assign(:current_user_id, scope.user.id)
      |> assign(:tab, "active")
      |> assign(:orgs, Organizations.list_user_organizations(scope))
      |> load_members()

    socket =
      if is_admin do
        socket
        |> assign(:invite_form, build_invite_form())
        |> load_invites()
      else
        socket
        |> assign(:invite_form, nil)
        |> assign(:invites, [])
      end

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["active", "pending"] do
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def handle_event("remove_member", %{"user_id" => user_id}, socket) do
    with {:ok, user} <- Accounts.get_user(user_id),
         {:ok, _} <-
           Organizations.remove_member(socket.assigns.current_scope, socket.assigns.org, user) do
      {:noreply, load_members(socket)}
    else
      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "Cannot remove the last admin.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not remove member.")}
    end
  end

  @impl true
  def handle_event("change_role", %{"user_id" => user_id, "role" => role}, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns.org

    with {:ok, user} <- Accounts.get_user(user_id),
         {:ok, membership} <- Organizations.get_membership_for_user(org.id, user.id),
         {:ok, _} <- Organizations.update_membership_role(scope, membership, role) do
      {:noreply, load_members(socket)}
    else
      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "Cannot demote the last admin.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update role.")}
    end
  end

  @impl true
  def handle_event("validate_invite", %{"invite" => params}, socket) do
    {:noreply, assign(socket, :invite_form, to_form(params, as: "invite"))}
  end

  @impl true
  def handle_event("send_invite", %{"invite" => params}, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns.org
    role = Map.get(params, "role", "member")

    emails =
      (Map.get(params, "email") || "")
      |> String.split(~r/[\s,]+/, trim: true)
      |> Enum.uniq()

    case emails do
      [] ->
        case Organizations.create_invite(scope, org, %{"email" => "", "role" => role}) do
          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :invite_form, to_form(changeset, as: "invite"))}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {sent, errors} =
          Enum.reduce(emails, {[], []}, fn email, {sent_acc, err_acc} ->
            case Organizations.create_invite(scope, org, %{"email" => email, "role" => role}) do
              {:ok, {raw_token, invite}} ->
                url = CritWeb.Endpoint.url() <> ~p"/invites/#{raw_token}"
                OrgNotifier.deliver_invitation(invite, org, scope.user, url)
                {[invite.email | sent_acc], err_acc}

              {:error, :already_member} ->
                {sent_acc, ["#{email} is already a member" | err_acc]}

              {:error, :invite_exists} ->
                {sent_acc, ["#{email} already has a pending invite" | err_acc]}

              {:error, %Ecto.Changeset{} = cs} ->
                msg = Ecto.Changeset.traverse_errors(cs, fn {m, _} -> m end) |> inspect()
                {sent_acc, ["#{email}: #{msg}" | err_acc]}

              _ ->
                {sent_acc, ["#{email}: could not send" | err_acc]}
            end
          end)

        socket = load_invites(socket)

        socket =
          case sent do
            [] ->
              socket

            _ ->
              socket
              |> assign(:invite_form, build_invite_form())
              |> put_flash(:info, "Invited #{Enum.join(Enum.reverse(sent), ", ")}.")
          end

        socket =
          case errors do
            [] -> socket
            _ -> put_flash(socket, :error, Enum.join(Enum.reverse(errors), ". ") <> ".")
          end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("revoke_invite", %{"id" => invite_id}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, invite} <- Organizations.get_invite(scope, invite_id),
         {:ok, _} <- Organizations.revoke_invite(scope, invite) do
      {:noreply, load_invites(socket)}
    else
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Invite not found.")}
      {:error, :unauthorized} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
      _ -> {:noreply, put_flash(socket, :error, "Could not revoke invite.")}
    end
  end

  @impl true
  def handle_event("resend_invite", %{"id" => invite_id}, socket) do
    scope = socket.assigns.current_scope
    org = socket.assigns.org

    with {:ok, invite} <- Organizations.get_invite(scope, invite_id),
         {:ok, {raw_token, new_invite}} <- Organizations.resend_invite(scope, invite) do
      url = CritWeb.Endpoint.url() <> ~p"/invites/#{raw_token}"
      new_invite_with_org = Map.put(new_invite, :organization, org)
      OrgNotifier.deliver_invitation(new_invite_with_org, org, scope.user, url)

      {:noreply,
       socket
       |> load_invites()
       |> put_flash(:info, "Invite resent.")}
    else
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Invite not found.")}
      {:error, :unauthorized} -> {:noreply, put_flash(socket, :error, "Not authorized.")}
      _ -> {:noreply, put_flash(socket, :error, "Could not resend invite.")}
    end
  end

  @doc false
  def expires_label(invite) do
    ttl_days = Crit.Organizations.OrganizationInvite.ttl_days()
    expiry = DateTime.add(invite.inserted_at, ttl_days * 24 * 3600, :second)
    days = DateTime.diff(expiry, DateTime.utc_now(), :day)

    cond do
      days < 0 -> "Expired"
      days == 0 -> "Today"
      days == 1 -> "Tomorrow"
      true -> "#{days}d"
    end
  end

  defp build_invite_form do
    to_form(%{"email" => "", "role" => "member"}, as: "invite")
  end

  defp load_members(socket) do
    members =
      Organizations.list_members(socket.assigns.current_scope, socket.assigns.org)

    assign(socket, :members, members)
  end

  defp load_invites(socket) do
    invites =
      Organizations.list_pending_invites(socket.assigns.current_scope, socket.assigns.org)

    assign(socket, :invites, invites)
  end
end
