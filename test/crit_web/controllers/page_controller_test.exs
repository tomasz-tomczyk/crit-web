defmodule CritWeb.PageControllerTest do
  use CritWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Point at the line."
  end

  test "GET /integrations/build-your-own", %{conn: conn} do
    conn = get(conn, ~p"/integrations/build-your-own")
    assert html_response(conn, 200) =~ "Build Your Own"
  end

  test "GET /terms", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms of Service"
  end

  test "GET /privacy", %{conn: conn} do
    conn = get(conn, ~p"/privacy")
    assert html_response(conn, 200) =~ "Privacy Policy"
    assert html_response(conn, 200) =~ "Website analytics"
    assert html_response(conn, 200) =~ "Umami"
  end

  test "GET /self-hosting", %{conn: conn} do
    conn = get(conn, ~p"/self-hosting")
    assert html_response(conn, 200) =~ "Self-Hosting"
  end

  test "GET / shows homepage sections", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Point at the line."
    assert html =~ "Every agent reads files"
    assert html =~ "Guides & articles"
    assert html =~ "Frequently asked questions"
  end

  describe "GET /articles" do
    test "renders the articles landing page", %{conn: conn} do
      conn = get(conn, ~p"/articles")
      html = html_response(conn, 200)
      assert html =~ "Articles"
      assert html =~ "How to Plan, Document and Review Code with Open Source Tools"
    end
  end

  describe "GET /articles/:slug" do
    test "renders an article", %{conn: conn} do
      conn = get(conn, ~p"/articles/how-to-plan-document-and-review")
      html = html_response(conn, 200)
      assert html =~ "How to Plan, Document and Review Code with Open Source Tools"
      assert html =~ "All articles"
    end

    test "returns 404 for unknown slug", %{conn: conn} do
      conn = get(conn, ~p"/articles/does-not-exist")
      body = response(conn, 404)
      assert body =~ "not found"
    end
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

    test "renders the marketplace branch for codex", %{conn: conn} do
      conn = get(conn, ~p"/integrations/codex")
      html = html_response(conn, 200)
      assert html =~ "Install the plugin (recommended)"
      assert html =~ "crit install codex-plugin"
      assert html =~ "Proposed-plan review hook"
      assert html =~ "Per-project alternative"
      assert html =~ "crit install codex"
    end

    test "returns 404 for an unknown tool", %{conn: conn} do
      conn = get(conn, ~p"/integrations/does-not-exist")
      body = response(conn, 404)
      assert body =~ "This page was"
      assert body =~ "not found"
    end
  end

  describe "GET /modes/:mode" do
    for slug <- ~w(plans-docs code story live preview) do
      @slug slug

      test "renders the #{slug} mode page", %{conn: conn} do
        conn = get(conn, "/modes/#{@slug}")
        html = html_response(conn, 200)
        assert html =~ "How it works."
        assert html =~ "What you get."
      end
    end

    test "story mode page includes token cost indication", %{conn: conn} do
      conn = get(conn, "/modes/story")
      html = html_response(conn, 200)
      assert html =~ "Token cost."
      assert html =~ "Rough extra LLM spend"
      assert html =~ "does not scale linearly"
    end

    test "returns 404 for an unknown mode", %{conn: conn} do
      conn = get(conn, "/modes/does-not-exist")
      assert response(conn, 404) =~ "not found"
    end
  end
end
