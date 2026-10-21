defmodule CritWeb.Plugs.FlyClientIp do
  @moduledoc """
  On Fly.io every request reaches the app through Fly's proxy, so
  `conn.remote_ip` is the proxy's address and all visitors share one
  rate-limit bucket. Fly puts the visitor's address in `Fly-Client-IP`
  (overwriting any value the client sent); copy it into `remote_ip`.

  Only trusted when `FLY_APP_NAME` is set (Fly sets it on every machine).
  Anywhere else a client could send the header to pick its own IP.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with true <- Application.get_env(:crit, :trust_fly_client_ip, false),
         [value | _] <- get_req_header(conn, "fly-client-ip"),
         {:ok, ip} <- value |> String.trim() |> String.to_charlist() |> :inet.parse_address() do
      %{conn | remote_ip: ip}
    else
      _ -> conn
    end
  end
end
