defmodule CritWeb.Plugs.ApiAuth do
  import Plug.Conn
  alias Crit.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case Accounts.verify_token(token) do
          {:ok, user} ->
            assign(conn, :current_user, user)

          {:error, :invalid} ->
            if enforced?(conn) do
              conn |> send_resp(401, ~s({"error":"invalid token"})) |> halt()
            else
              conn
            end
        end

      _ ->
        if enforced?(conn) do
          conn |> send_resp(401, ~s({"error":"authentication required"})) |> halt()
        else
          conn
        end
    end
  end

  defp enforced?(_conn) do
    Application.get_env(:crit, :selfhosted) == true &&
      Application.get_env(:crit, :oauth_provider) != nil
  end
end
