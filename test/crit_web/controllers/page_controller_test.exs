defmodule CritWeb.PageControllerTest do
  use CritWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Your feedback loop"
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

  describe "GET /integrations" do
    test "renders the index with every tool name", %{conn: conn} do
      conn = get(conn, ~p"/integrations")
      html = html_response(conn, 200)
      assert html =~ "Agent integrations for Crit"

      for tool <- Crit.Integrations.tools() do
        assert html =~ tool.name
      end
    end
  end

  describe "GET /integrations/:tool" do
    for tool <- Crit.Integrations.tools() do
      @tool tool

      test "renders the #{tool.id} page with its H1 and intro", %{conn: conn} do
        conn = get(conn, ~p"/integrations/#{@tool.id}")
        html = html_response(conn, 200)
        assert html =~ "Crit + #{@tool.name}"

        intro_escaped =
          @tool.intro |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

        assert html =~ intro_escaped
      end
    end

    test "renders the marketplace branch for claude-code", %{conn: conn} do
      conn = get(conn, ~p"/integrations/claude-code")
      html = html_response(conn, 200)
      assert html =~ "Install the plugin (recommended)"
      assert html =~ "claude plugin marketplace add tomasz-tomczyk/crit"
      assert html =~ "Per-project alternative"
    end

    test "returns 404 for an unknown tool", %{conn: conn} do
      conn = get(conn, ~p"/integrations/does-not-exist")
      assert response(conn, 404) =~ "Not Found"
    end
  end
end
