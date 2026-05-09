defmodule CritWeb.Plugs.NoTransform do
  @moduledoc """
  Endpoint `__before_compile__` hook that overrides `call/2` to register a
  `before_send` callback adding `no-transform` to every response's
  `Cache-Control` header.

  ## Why

  Transforming reverse proxies (e.g. Envoy with re-gzip) can double-encode
  responses already encoded by Bandit, producing broken bodies for the client.
  RFC 7234 instructs proxies not to transform when `no-transform` is present.

  Hooking at the endpoint level (rather than as a plug in the router pipeline)
  ensures the header is also applied to the LiveView socket transport
  endpoints (`/live/longpoll`, `/live/websocket` upgrades) which bypass the
  router pipeline.

  See https://github.com/tomasz-tomczyk/crit-web/issues/50 for context.
  """

  defmacro __before_compile__(_env) do
    quote do
      defoverridable call: 2

      def call(conn, opts) do
        conn =
          Plug.Conn.register_before_send(conn, fn conn ->
            case Plug.Conn.get_resp_header(conn, "cache-control") do
              [val] ->
                if String.contains?(val, "no-transform") do
                  conn
                else
                  Plug.Conn.put_resp_header(conn, "cache-control", val <> ", no-transform")
                end

              [] ->
                Plug.Conn.put_resp_header(conn, "cache-control", "no-transform")

              _ ->
                conn
            end
          end)

        super(conn, opts)
      end
    end
  end
end
