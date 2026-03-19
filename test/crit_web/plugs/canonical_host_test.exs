defmodule CritWeb.Plugs.CanonicalHostTest do
  use CritWeb.ConnCase

  alias CritWeb.Plugs.CanonicalHost

  setup do
    Application.put_env(:crit, :canonical_host, "crit.md")
    on_exit(fn -> Application.delete_env(:crit, :canonical_host) end)
  end

  defp call_plug(conn) do
    CanonicalHost.call(conn, CanonicalHost.init([]))
  end

  test "redirects crit.live to canonical host with 308", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "crit.live")
      |> call_plug()

    assert conn.status == 308
    assert get_resp_header(conn, "location") == ["http://crit.md/"]
  end

  test "redirects www subdomain to canonical host with 308", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "www.crit.md")
      |> call_plug()

    assert conn.status == 308
    assert get_resp_header(conn, "location") == ["http://crit.md/"]
  end

  test "preserves path and query on redirect", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "crit.live")
      |> Map.put(:request_path, "/r/abc123")
      |> Map.put(:query_string, "foo=bar")
      |> call_plug()

    assert conn.status == 308
    assert get_resp_header(conn, "location") == ["http://crit.md/r/abc123?foo=bar"]
  end

  test "uses forwarded https scheme on redirect", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "crit.live")
      |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
      |> call_plug()

    assert conn.status == 308
    assert get_resp_header(conn, "location") == ["https://crit.md/"]
  end

  test "does not redirect canonical host", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "crit.md")
      |> call_plug()

    refute conn.halted
  end

  test "does not redirect when no canonical host configured", %{conn: conn} do
    Application.delete_env(:crit, :canonical_host)

    conn =
      conn
      |> Map.put(:host, "crit.live")
      |> call_plug()

    refute conn.halted
  end
end
