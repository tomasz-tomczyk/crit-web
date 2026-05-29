defmodule CritWeb.Plugs.SecurityHeaders do
  import Plug.Conn

  @permissions_policy [
    "camera=()",
    "microphone=()",
    "geolocation=()",
    "accelerometer=()",
    "gyroscope=()",
    "magnetometer=()",
    "payment=()",
    "usb=()",
    "browsing-topics=()"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("content-security-policy", csp())
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "SAMEORIGIN")
    |> put_resp_header("permissions-policy", Enum.join(@permissions_policy, ", "))
    |> maybe_put_hsts()
  end

  defp maybe_put_hsts(conn) do
    if Application.get_env(:crit, :hsts_enabled) do
      put_resp_header(conn, "strict-transport-security", "max-age=31536000; includeSubDomains")
    else
      conn
    end
  end

  defp csp do
    sentry_origin =
      case Application.get_env(:crit, :sentry_frontend) do
        %{ingest_origin: origin} when is_binary(origin) -> " " <> origin
        _ -> ""
      end

    "default-src 'self'; " <>
      "script-src 'self' " <>
      "'sha256-wm8xHXfA9tIFK/7McvhnPMGVuF/ErxqxEM1Clij75ec=' " <>
      "'sha256-5M5rMNBzgt7ZyJO3HUsytrd8A0xED8wq015qtyeaFrw='; " <>
      "style-src 'self' 'unsafe-inline'; " <>
      "img-src 'self' data: blob: https://i.ytimg.com https://avatars.githubusercontent.com https://assets.crit.md; " <>
      "font-src 'self'; " <>
      "media-src 'self' https://assets.crit.md; " <>
      "connect-src 'self'#{sentry_origin}; " <>
      "frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com; " <>
      "object-src 'none'"
  end
end
