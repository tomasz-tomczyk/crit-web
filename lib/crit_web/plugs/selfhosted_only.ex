defmodule CritWeb.Plugs.SelfhostedOnly do
  @moduledoc """
  Halts with a 404 when the instance is not running in selfhosted mode.

  Used to gate the `/users/*` local-auth routes — on the hosted/SaaS
  deployment those endpoints simply don't exist.
  """

  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:crit, :selfhosted) do
      conn
    else
      conn |> send_resp(404, "Not found") |> halt()
    end
  end
end
