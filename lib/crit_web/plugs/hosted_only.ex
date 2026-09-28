defmodule CritWeb.Plugs.HostedOnly do
  @moduledoc """
  Halts with a 404 when the instance is running in selfhosted mode.

  Used to gate SaaS-only marketing surfaces (newsletters, etc.) that must not
  appear on self-hosted deployments.
  """

  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Crit.Config.hosted?() do
      conn
    else
      conn |> send_resp(404, "Not found") |> halt()
    end
  end
end
