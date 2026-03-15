defmodule CritWeb.Plugs.SecurityHeaders do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header(
      "content-security-policy",
      "default-src 'self'; script-src 'self' 'sha256-wm8xHXfA9tIFK/7McvhnPMGVuF/ErxqxEM1Clij75ec='; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://i.ytimg.com; font-src 'self'; connect-src 'self'; frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com; object-src 'none'"
    )
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
  end
end
