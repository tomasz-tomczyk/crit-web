defmodule CritWeb.Plugs.RateLimit do
  @moduledoc """
  Global per-IP rate limit. Backstop against scanners and runaway clients;
  tighter per-route limits (write API, invalid-token 404s) live alongside
  this and apply on top.

  Options:

    * `:limit`    — requests per minute per IP (default `180`).
    * `:response` — `:text` (default) or `:json`. Sets the body and content-type
      sent on a 429 response. Pass `:json` from API pipelines.
  """

  import Plug.Conn

  @default_limit 180
  @window :timer.minutes(1)

  def init(opts) do
    response = Keyword.get(opts, :response, :text)

    unless response in [:text, :json],
      do: raise(ArgumentError, ":response must be :text or :json")

    opts
  end

  def call(conn, opts) do
    if disabled?() do
      conn
    else
      limit = Keyword.get(opts, :limit, @default_limit)
      response = Keyword.get(opts, :response, :text)
      ip = conn.remote_ip |> :inet.ntoa() |> to_string()

      case Crit.RateLimit.hit("global:#{ip}", @window, limit) do
        {:allow, _} ->
          conn

        {:deny, _} ->
          {content_type, body} = body_for(response)

          conn
          |> put_resp_content_type(content_type)
          |> put_resp_header("retry-after", "60")
          |> send_resp(429, body)
          |> halt()
      end
    end
  end

  defp body_for(:json), do: {"application/json", ~s({"error":"Too many requests"})}
  defp body_for(:text), do: {"text/plain", "Too many requests"}

  defp disabled? do
    System.get_env("E2E") == "true" or
      Application.get_env(:crit, __MODULE__, [])[:disabled] == true
  end
end
