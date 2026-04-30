defmodule CritWeb.Plugs.ApiAuth do
  import Plug.Conn
  alias Crit.Accounts
  alias Crit.Config

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case Accounts.verify_token(token) do
          {:ok, user} ->
            assign(conn, :current_user, user)

          {:error, :invalid} ->
            if Config.selfhosted_oauth?() do
              conn |> send_resp(401, ~s({"error":"invalid token"})) |> halt()
            else
              conn
            end
        end

      _ ->
        if Config.selfhosted_oauth?() do
          conn |> send_resp(401, ~s({"error":"authentication required"})) |> halt()
        else
          conn
        end
    end
  end
end
