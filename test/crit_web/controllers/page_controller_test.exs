defmodule CritWeb.PageControllerTest do
  use CritWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Don't let your agent"
  end

  test "GET /terms", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms of Service"
  end

  test "GET /privacy", %{conn: conn} do
    conn = get(conn, ~p"/privacy")
    assert html_response(conn, 200) =~ "Privacy Policy"
  end

  test "GET /self-hosting", %{conn: conn} do
    conn = get(conn, ~p"/self-hosting")
    assert html_response(conn, 200) =~ "Self-Hosting"
  end

  test "GET / shows platform stats", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Shared to"
    assert html =~ "reviews"
    assert html =~ "comments"
    assert html =~ "lines"
  end
end
