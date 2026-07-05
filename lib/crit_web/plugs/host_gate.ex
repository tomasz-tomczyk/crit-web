defmodule CritWeb.Plugs.HostGate do
  @moduledoc """
  Restricts the route surface by host when PREVIEW_HOST is configured.
  """
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    preview_host = CritWeb.Hosts.preview_host()

    canonical_host = CritWeb.Hosts.canonical_host()

    cond do
      not is_binary(preview_host) ->
        conn

      not is_binary(canonical_host) ->
        conn

      conn.host == preview_host ->
        if preview_path_allowed?(conn) do
          conn
        else
          conn |> send_resp(404, "not found") |> halt()
        end

      conn.host == canonical_host ->
        conn

      local_host?(conn.host) ->
        conn

      true ->
        conn |> send_resp(404, "not found") |> halt()
    end
  end

  defp preview_path_allowed?(%Plug.Conn{method: method, request_path: path}) do
    method in ["GET", "HEAD"] and
      (preview_raw_path?(path) or
         String.starts_with?(path, "/preview-agent/") or
         path == "/agent-marker.css" or
         path == "/health" or
         path == "/share-receiver")
  end

  # Only sandboxed raw HTML belongs on the preview host — not the interactive
  # ReviewLive at /r/:token (frameable there with no x-frame-options).
  defp preview_raw_path?(path), do: String.match?(path, ~r{^/r/[^/]+/raw/})

  defp local_host?(host), do: host in ["localhost", "127.0.0.1", "[::1]"]
end
