defmodule CritWeb.Plugs.LocalhostCors do
  @moduledoc """
  Reflects CORS headers for requests originating from localhost or 127.0.0.1
  (any port). Used on the /api/reviews routes so the local Crit binary can
  upload, re-share (PUT), and pull comments from its embedded browser / from the
  user's browser on localhost. Handles OPTIONS preflight inline — note the
  router must also declare an `options` route for each path the browser sends a
  preflight to (e.g. PUT /reviews/:token), otherwise the preflight 404s before
  this plug runs.
  """
  import Plug.Conn

  @localhost ~r/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = conn |> get_req_header("origin") |> List.first()

    conn =
      if origin && Regex.match?(@localhost, origin) do
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "content-type")
        |> put_resp_header("access-control-max-age", "86400")
        |> put_resp_header("vary", "Origin")
      else
        conn
      end

    if conn.method == "OPTIONS" do
      conn |> send_resp(204, "") |> halt()
    else
      conn
    end
  end
end
