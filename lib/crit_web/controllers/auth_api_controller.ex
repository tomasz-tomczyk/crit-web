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
  DELETE /api/auth/token — revokes the Bearer token used to authenticate this request.

  Idempotent: returns 204 even if the token is already gone.
  """
  def revoke(conn, _params) do
    Accounts.revoke_token_by_plaintext(conn.assigns.current_token)
    send_resp(conn, 204, "")
  end
end
