defmodule CritWeb.ChangelogControllerTest do
  use CritWeb.ConnCase, async: true

  test "GET /changelog renders the page", %{conn: conn} do
    conn = get(conn, ~p"/changelog")
    assert html_response(conn, 200) =~ "Changelog"
  end

  test "GET /changelog has correct page title", %{conn: conn} do
    conn = get(conn, ~p"/changelog")
    assert html_response(conn, 200) =~ "Changelog - Crit"
  end
end
