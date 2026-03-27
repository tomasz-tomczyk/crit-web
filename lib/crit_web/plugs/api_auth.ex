defmodule CritWeb.Plugs.ApiAuth do
  import Plug.Conn
  alias Crit.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if enforced?(conn) do
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] ->
          case Accounts.verify_token(token) do
            {:ok, user} -> assign(conn, :current_user, user)
            {:error, :invalid} -> conn |> send_resp(401, ~s({"error":"invalid token"})) |> halt()
          end

        _ ->
          conn |> send_resp(401, ~s({"error":"authentication required"})) |> halt()
      end
    else
      conn
    end
  end

  defp enforced?(_conn) do
    Application.get_env(:crit, :selfhosted) == true &&
      Application.get_env(:crit, :oauth_provider) != nil
  end
end
