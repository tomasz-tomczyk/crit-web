defmodule CritWeb.Plugs.RegistrationEnabled do
  @moduledoc """
  Halts with a 404 when local registration is disabled on this instance.

  Selfhosted operators who want to seed users via `mix crit.create_user`
  can flip `:local_registration_enabled` to false to keep the registration
  routes from existing at all.
  """

  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:crit, :local_registration_enabled, true) do
      conn
    else
      conn |> send_resp(404, "Not found") |> halt()
    end
  end
end
