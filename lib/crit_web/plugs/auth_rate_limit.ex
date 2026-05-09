defmodule CritWeb.Plugs.AuthRateLimit do
  @moduledoc """
  Per-IP rate limit for authentication POST endpoints (login, register).
  Tighter than the global browser limit so password-grinding doesn't hide
  in the noise. Only enforced on POST — GETs serving the form are exempt.
  """

  import Plug.Conn

  @limit 20
  @window :timer.minutes(1)

  def init(opts), do: opts

  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    if disabled?() do
      conn
    else
      ip = conn.remote_ip |> :inet.ntoa() |> to_string()

      case Crit.RateLimit.hit("auth:#{ip}", @window, @limit) do
        {:allow, _} ->
          conn

        {:deny, retry_after} ->
          conn
          |> put_resp_content_type("text/plain")
          |> put_resp_header("retry-after", Integer.to_string(div(retry_after, 1000)))
          |> send_resp(429, "Too many requests")
          |> halt()
      end
    end
  end

  def call(conn, _opts), do: conn

  defp disabled? do
    System.get_env("E2E") == "true" or
      Application.get_env(:crit, CritWeb.Plugs.RateLimit, [])[:disabled] == true
  end
end
