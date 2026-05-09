defmodule CritWeb.LiveViewTransportMetaTest do
  # async: false — mutates Application env on CritWeb.Endpoint key.
  use CritWeb.ConnCase, async: false

  describe "<meta name=\"liveview-transport\">" do
    test "defaults to websocket when unset", %{conn: conn} do
      original = Application.get_env(:crit, CritWeb.Endpoint, [])
      Application.put_env(:crit, CritWeb.Endpoint, Keyword.delete(original, :liveview_transport))

      on_exit(fn -> Application.put_env(:crit, CritWeb.Endpoint, original) end)

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ ~s(<meta name="liveview-transport" content="websocket")
    end

    test "renders longpoll when configured", %{conn: conn} do
      original = Application.get_env(:crit, CritWeb.Endpoint, [])

      Application.put_env(
        :crit,
        CritWeb.Endpoint,
        Keyword.put(original, :liveview_transport, "longpoll")
      )

      on_exit(fn -> Application.put_env(:crit, CritWeb.Endpoint, original) end)

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ ~s(<meta name="liveview-transport" content="longpoll")
    end
  end
end
