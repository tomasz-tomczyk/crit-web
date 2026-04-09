defmodule CritWeb.Plugs.RequireBearerAuth do
  @moduledoc """
  Plug that always enforces Bearer token authentication.

  Unlike `ApiAuth` which is conditional on self-hosted mode, this plug
  unconditionally requires a valid Bearer token. Used for endpoints like
  `/api/auth/whoami` and `/api/auth/token` where authentication is always required.
  """

  import Plug.Conn

  alias Crit.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case Accounts.verify_token(token) do
          {:ok, user} ->
            conn
            |> assign(:current_user, user)
            |> assign(:current_token, token)

          {:error, :invalid} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, ~s({"error":"invalid token"}))
            |> halt()
        end

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, ~s({"error":"authentication required"}))
        |> halt()
    end
  end
end
