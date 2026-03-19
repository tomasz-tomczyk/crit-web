defmodule CritWeb.Plugs.CanonicalHost do
  @moduledoc """
  Redirects non-canonical hosts (www, fly.dev) to the canonical host.
  """
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    canonical_host = Application.get_env(:crit, :canonical_host)

    if canonical_host && should_redirect?(conn.host, canonical_host) do
      redirect_to_canonical(conn, canonical_host)
    else
      conn
    end
  end

  defp should_redirect?(host, canonical_host) do
    host != canonical_host &&
      (String.starts_with?(host, "www.") || String.ends_with?(host, ".fly.dev") ||
         host == "crit.live" || host == "www.crit.live")
  end

  defp redirect_to_canonical(conn, canonical_host) do
    scheme = redirect_scheme(conn)
    path = conn.request_path
    query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""

    url = "#{scheme}://#{canonical_host}#{path}#{query}"

    conn
    |> put_resp_header("location", url)
    |> send_resp(308, "")
    |> halt()
  end

  defp redirect_scheme(conn) do
    case get_req_header(conn, "x-forwarded-proto") do
      [forwarded_proto | _rest] ->
        forwarded_proto
        |> String.split(",", parts: 2)
        |> hd()
        |> String.trim()
        |> String.downcase()

      [] ->
        if conn.scheme == :https, do: "https", else: "http"
    end
  end
end
