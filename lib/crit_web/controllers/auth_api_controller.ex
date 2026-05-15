defmodule CritWeb.AuthApiController do
  use CritWeb, :controller

  alias Crit.Accounts

  @doc """
  GET /api/auth/whoami — returns the authenticated user's name and email.
  """
  def whoami(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      id: user.id,
      name: user.name,
      email: user.email
    })
  end

  @doc """
  GET /api/auth/orgs — returns the authenticated user's organizations.
  """
  def orgs(conn, _params) do
    user = conn.assigns.current_user
    scope = Crit.Accounts.Scope.for_user(user)
    orgs = Crit.Organizations.list_user_organizations(scope)

    json(
      conn,
      Enum.map(orgs, fn org ->
        %{name: org.name, slug: org.slug, role: org.role}
      end)
    )
  end

  @doc """
  DELETE /api/auth/token — revokes the Bearer token used to authenticate this request.

  Idempotent: returns 204 even if the token is already gone.
  """
  def revoke(conn, _params) do
    Accounts.revoke_token_by_plaintext(conn.assigns.current_token)
    send_resp(conn, 204, "")
  end
end
