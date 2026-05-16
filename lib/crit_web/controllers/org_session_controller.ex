defmodule CritWeb.OrgSessionController do
  use CritWeb, :controller

  require Logger

  alias Crit.Organizations

  @doc """
  Email-link accept flow: verifies the raw token from the URL before
  creating membership. Used by `POST /invites/:token/accept`.
  """
  def accept_invite(conn, %{"token" => raw_token}) do
    scope = conn.assigns.current_scope

    result = Organizations.accept_invite(scope, raw_token)

    case result do
      {:ok, {_org, _membership}} ->
        finalize_accept(conn)

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "This invite link is invalid.")
        |> redirect(to: ~p"/orgs")

      other ->
        handle_invite_result(conn, other)
    end
  end

  @doc """
  Direct accept flow from the `/orgs` page where the user is already
  authenticated. Looks up the invite by id; email match is enforced
  inside `Organizations.accept_invite_by_id/2`.
  """
  def accept_invite_direct(conn, %{"id" => invite_id}) do
    scope = conn.assigns.current_scope

    result = Organizations.accept_invite_by_id(scope, invite_id)

    case result do
      {:ok, {_org, _membership}} ->
        finalize_accept(conn)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invite not found.")
        |> redirect(to: ~p"/orgs")

      other ->
        handle_invite_result(conn, other)
    end
  end

  defp handle_invite_result(conn, result) do
    case result do
      {:error, :email_mismatch} ->
        conn
        |> put_flash(:error, "This invite was sent to a different email address.")
        |> redirect(to: ~p"/orgs")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "This invite has expired.")
        |> redirect(to: ~p"/orgs")

      {:error, :already_member} ->
        conn
        |> put_flash(:error, "You are already a member of this organization.")
        |> redirect(to: ~p"/orgs")

      other ->
        Logger.warning("Unexpected invite result: #{inspect(other)}")

        conn
        |> put_flash(:error, "Could not accept invite.")
        |> redirect(to: ~p"/orgs")
    end
  end

  defp finalize_accept(conn) do
    conn
    |> put_flash(:info, "Welcome! You have joined the organization.")
    |> redirect(to: ~p"/orgs")
  end
end
