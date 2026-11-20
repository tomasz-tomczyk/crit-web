defmodule CritWeb.RemoteImageControllerTest do
  use CritWeb.ConnCase, async: true

  alias CritWeb.RemoteImageController

  defp csp(conn), do: conn |> get_resp_header("content-security-policy") |> List.first()

  describe "GET /remote-image" do
    test "renders a frame with the image and its reporting script", %{conn: conn} do
      conn = get(conn, ~p"/remote-image?src=https://example.com/a.png&alt=Diagram")
      html = html_response(conn, 200)

      assert html =~ ~s(<img id="img" src="https://example.com/a.png" alt="Diagram">)
      assert html =~ "<script>" <> RemoteImageController.frame_script() <> "</script>"
      refute html =~ "/assets/js/app.js"
    end

    test "sends its own sandboxed policy instead of the site-wide one", %{conn: conn} do
      conn = get(conn, ~p"/remote-image?src=https://example.com/a.png")
      [policy] = get_resp_header(conn, "content-security-policy")

      script_hash =
        "'sha256-" <>
          Base.encode64(:crypto.hash(:sha256, RemoteImageController.frame_script())) <> "'"

      assert policy ==
               "sandbox allow-scripts; default-src 'none'; img-src http: https:; " <>
                 "style-src 'unsafe-inline'; script-src #{script_hash}; base-uri 'none'; " <>
                 "form-action 'none'; frame-ancestors 'self'"

      assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
      assert [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control =~ ~r/^no-store\b/
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "uses the same script hash as crit" do
      # crit's internal/server/csp.go remoteImageFrameScript, hashed. If this
      # changes, crit changed the script: copy it again.
      assert RemoteImageController.frame_csp() =~
               "script-src 'sha256-9ITVau927hxTtuBP2nBUZkBLsEbzZNcBzoSiTV9ipOk='"
    end

    test "escapes src and alt into the HTML", %{conn: conn} do
      src = "https://example.com/a.png?x=1&y=2"
      alt = ~s|"><img src=x onerror=alert(1)>|

      html =
        conn
        |> get(~p"/remote-image?#{[src: src, alt: alt]}")
        |> html_response(200)

      assert html =~ ~s|src="https://example.com/a.png?x=1&amp;y=2"|
      refute html =~ "onerror=alert(1)>"
      assert html =~ ~s|alt="&quot;&gt;&lt;img src=x onerror=alert(1)&gt;"|
    end

    test "rejects a src that would break out of the attribute", %{conn: conn} do
      src = ~s|https://example.com/a.png?x="><script>alert(1)</script>|
      conn = get(conn, ~p"/remote-image?#{[src: src]}")

      assert response(conn, 400) =~ "src must be an http(s) URL"
      refute conn.resp_body =~ "<script>"
    end

    test "accepts http URLs", %{conn: conn} do
      conn = get(conn, ~p"/remote-image?src=http://example.com/a.png")
      assert html_response(conn, 200) =~ ~s(src="http://example.com/a.png")
    end

    for bad <- [
          "javascript:alert(1)",
          "data:image/png;base64,AAAA",
          "file:///etc/passwd",
          "/relative.png",
          "//example.com/a.png",
          "https://",
          "not a url"
        ] do
      test "rejects #{inspect(bad)}", %{conn: conn} do
        conn = get(conn, ~p"/remote-image?#{[src: unquote(bad)]}")
        assert response(conn, 400) =~ "src must be an http(s) URL"
        # The error page keeps the locked-down policy too.
        assert csp(conn) =~ "default-src 'none'"
      end
    end

    test "rejects a missing src", %{conn: conn} do
      conn = get(conn, ~p"/remote-image")
      assert response(conn, 400) =~ "src must be an http(s) URL"
    end

    test "rejects an over-long src", %{conn: conn} do
      src = "https://example.com/" <> String.duplicate("a", 8 * 1024)
      conn = get(conn, ~p"/remote-image?#{[src: src]}")
      assert response(conn, 400) =~ "src too long"
    end

    test "cuts a long alt on a character boundary", %{conn: conn} do
      alt = String.duplicate("a", 1023) <> "é" <> "tail"

      html =
        conn
        |> get(~p"/remote-image?#{[src: "https://example.com/a.png", alt: alt]}")
        |> html_response(200)

      assert html =~ ~s(alt="#{String.duplicate("a", 1023)}")
      refute html =~ "tail"
    end
  end
end
