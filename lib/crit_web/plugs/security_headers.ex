defmodule CritWeb.Plugs.SecurityHeaders do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("content-security-policy", csp())
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
  end

  defp csp do
    sentry_origin =
      case Application.get_env(:crit, :sentry_frontend) do
        %{ingest_origin: origin} when is_binary(origin) -> " " <> origin
        _ -> ""
      end

    "default-src 'self'; " <>
      "script-src 'self' 'sha256-wm8xHXfA9tIFK/7McvhnPMGVuF/ErxqxEM1Clij75ec='; " <>
      "style-src 'self' 'unsafe-inline'; " <>
      "img-src 'self' data: blob: https://i.ytimg.com https://avatars.githubusercontent.com; " <>
      "font-src 'self'; " <>
      "connect-src 'self'#{sentry_origin}; " <>
      "frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com; " <>
      "object-src 'none'"
  end
end
