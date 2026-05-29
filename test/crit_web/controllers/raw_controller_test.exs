defmodule CritWeb.RawControllerTest do
  use CritWeb.ConnCase, async: true

  alias Crit.Reviews

  # 8-byte PNG magic header, base64-encoded.
  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @png_base64 Base.encode64(@png_signature)

  defp create_review(attrs) do
    {:ok, review} =
      Reviews.create_review(Map.merge(%{review_round: 1, cli_args: []}, attrs))

    review
  end

  describe "GET /r/:token/raw/*file_path (files mode)" do
    test "serves file content as text/plain", %{conn: conn} do
      review =
        create_review(%{
          files: [%{file_path: "lib/foo.ex", content: "defmodule Foo", status: "modified"}]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/lib/foo.ex")

      assert response_content_type(conn, :txt) =~ "text/plain"
      assert response(conn, 200) == "defmodule Foo"
    end

    test "returns 404 for missing file", %{conn: conn} do
      review =
        create_review(%{
          files: [%{file_path: "lib/foo.ex", content: "defmodule Foo", status: "modified"}]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/lib/missing.ex")

      assert response(conn, 404) == "not found"
    end

    test "files-mode HTML is served verbatim without agent injection or preview CSP", %{
      conn: conn
    } do
      html = "<html><body><h1>hi</h1></body></html>"

      review =
        create_review(%{
          files: [%{file_path: "index.html", content: html, status: "modified"}]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/index.html")

      body = response(conn, 200)
      assert body == html
      refute body =~ "/preview-agent/"
      # The restrictive preview CSP must not leak onto non-preview reviews.
      refute get_resp_header(conn, "content-security-policy")
             |> Enum.any?(&(&1 =~ "connect-src 'none'"))
    end
  end

  describe "GET /r/:token/raw/*file_path (preview mode)" do
    test "serves a base64 snapshot decoded with the correct MIME type", %{conn: conn} do
      review =
        create_review(%{
          review_type: :preview,
          files: [
            %{file_path: "index.html", content: "<html><body></body></html>", status: "modified"},
            %{file_path: "logo.png", content: @png_base64, status: "modified", encoding: "base64"}
          ]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/logo.png")

      assert response_content_type(conn, :png) =~ "image/png"
      assert response(conn, 200) == @png_signature
    end

    test "injects agent scripts before </body> and sets a restrictive CSP on HTML", %{conn: conn} do
      html = "<html><head></head><body><h1>Hi</h1></body></html>"

      review =
        create_review(%{
          review_type: :preview,
          files: [%{file_path: "index.html", content: html, status: "modified"}]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/index.html")

      body = response(conn, 200)
      assert response_content_type(conn, :html) =~ "text/html"

      # All 7 agent scripts injected, in crit's exact order, before </body>.
      expected_scripts = [
        "agent-protocol.js",
        "agent-anchor-utils.js",
        "agent-marker-overlay.js",
        "agent-mutation-batcher.js",
        "agent-resolution.js",
        "agent-reanchor-state.js",
        "crit-agent.js"
      ]

      for name <- expected_scripts do
        assert body =~ ~s(<script src="/preview-agent/#{name}"></script>)
      end

      # Injected before the closing body tag.
      [before_body, _after] = String.split(body, "</body>", parts: 2)
      assert before_body =~ "/preview-agent/crit-agent.js"

      # Order preserved.
      proto_idx = :binary.match(body, "/preview-agent/agent-protocol.js") |> elem(0)
      agent_idx = :binary.match(body, "/preview-agent/crit-agent.js") |> elem(0)
      assert proto_idx < agent_idx

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'self' 'unsafe-inline' 'unsafe-eval'"
      assert csp =~ "img-src 'self' data: blob:"
      assert csp =~ "font-src 'self' data:"
      assert csp =~ "connect-src 'none'"
      assert csp =~ "frame-src 'none'"
      # No external origins in the preview sandbox CSP.
      refute csp =~ "http"
    end

    test "appends agent scripts when there is no </body> tag", %{conn: conn} do
      html = "<div>fragment with no body tag</div>"

      review =
        create_review(%{
          review_type: :preview,
          files: [%{file_path: "index.html", content: html, status: "modified"}]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/index.html")

      body = response(conn, 200)
      assert body =~ "fragment with no body tag"
      assert body =~ ~s(<script src="/preview-agent/crit-agent.js"></script>)
    end

    test "serves a text asset (.css) verbatim as text/css", %{conn: conn} do
      css = "body { color: red; }"

      review =
        create_review(%{
          review_type: :preview,
          files: [
            %{file_path: "index.html", content: "<html><body></body></html>", status: "modified"},
            %{file_path: "style.css", content: css, status: "modified"}
          ]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/style.css")

      assert response_content_type(conn, :css) =~ "text/css"
      assert response(conn, 200) == css
      # CSS assets are not HTML — no restrictive preview sandbox CSP.
      refute get_resp_header(conn, "content-security-policy")
             |> Enum.any?(&(&1 =~ "connect-src 'none'"))
    end
  end
end
