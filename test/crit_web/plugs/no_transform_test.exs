defmodule CritWeb.Plugs.NoTransformTest do
  use CritWeb.ConnCase, async: true

  describe "Cache-Control: no-transform" do
    test "is added on a normal page response", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert response(conn, 200)

      cache_control =
        conn
        |> get_resp_header("cache-control")
        |> List.first() || ""

      assert cache_control =~ "no-transform"
    end

    test "is merged into an existing Cache-Control on a static asset", %{conn: conn} do
      # Plug.Static sets its own Cache-Control on static files; the endpoint's
      # before_send must merge no-transform without clobbering it.
      conn = get(conn, "/favicon.svg")

      assert conn.status == 200

      [cache_control] = get_resp_header(conn, "cache-control")

      assert cache_control =~ "no-transform"
      # Plug.Static emits "public, max-age=..." — make sure that survives.
      assert cache_control =~ "public" or cache_control =~ "max-age"
    end
  end
end
