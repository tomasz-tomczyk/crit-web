defmodule CritWeb.RawControllerTest do
  # async: false — the auth-gate describes mutate global Application env
  # (:selfhosted / :oauth_provider), which would race other async tests.
  use CritWeb.ConnCase, async: false

  import Crit.ReviewsFixtures

  defp file(path, content, extra \\ %{}) do
    Map.merge(%{"path" => path, "content" => content}, extra)
  end

  describe "GET /r/:token/raw/*file_path" do
    test "returns the file content as text/plain with utf-8", %{conn: conn} do
      review = review_fixture(%{files: [file("lib/foo.ex", "defmodule Foo, do: :ok\n")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/lib/foo.ex")

      assert response(conn, 200) == "defmodule Foo, do: :ok\n"
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "sets inline content-disposition with the basename", %{conn: conn} do
      review = review_fixture(%{files: [file("deep/nested/dir/file.txt", "hi")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/deep/nested/dir/file.txt")

      assert get_resp_header(conn, "content-disposition") ==
               [~s(inline; filename="file.txt")]
    end

    test "sets x-robots-tag noindex", %{conn: conn} do
      review = review_fixture(%{files: [file("a.md", "# hi")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/a.md")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
    end

    test "supports file paths with multiple slashes (glob)", %{conn: conn} do
      review =
        review_fixture(%{
          files: [file("src/app/components/Button.tsx", "export const x = 1")]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/src/app/components/Button.tsx")

      assert response(conn, 200) == "export const x = 1"
    end

    test "404s when the review token is unknown", %{conn: conn} do
      conn = get(conn, ~p"/r/does-not-exist/raw/foo.txt")

      assert response(conn, 404)
    end

    test "404s when the file_path is not in the review", %{conn: conn} do
      review = review_fixture(%{files: [file("real.txt", "x")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/missing.txt")

      assert response(conn, 404)
    end

    test "serves removed/orphaned file content (still part of the review)", %{conn: conn} do
      review =
        review_fixture(%{
          files: [file("removed.ex", "old", %{"status" => "removed"})]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/removed.ex")

      assert response(conn, 200) == "old"
    end

    test "404s when filename contains non-ASCII characters", %{conn: conn} do
      review = review_fixture(%{files: [file("héllo.txt", "x")]})

      conn = get(conn, "/r/" <> review.token <> "/raw/" <> "héllo.txt")

      assert response(conn, 404)
    end
  end

  describe "preview reviews" do
    # 8-byte PNG magic header, base64-encoded.
    @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
    @png_base64 Base.encode64(@png_signature)

    test "serves a base64 snapshot decoded with the correct MIME type", %{conn: conn} do
      review =
        review_fixture(%{
          review_type: :preview,
          files: [
            file("index.html", "<html><body></body></html>"),
            file("logo.png", @png_base64, %{"encoding" => "base64"})
          ]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/logo.png")

      assert response_content_type(conn, :png) =~ "image/png"
      assert response(conn, 200) == @png_signature
    end

    test "injects agent scripts before </body> and sets a restrictive CSP on HTML", %{conn: conn} do
      html = "<html><head></head><body><h1>Hi</h1></body></html>"
      review = review_fixture(%{review_type: :preview, files: [file("index.html", html)]})

      conn = get(conn, ~p"/r/#{review.token}/raw/index.html")

      body = response(conn, 200)
      assert response_content_type(conn, :html) =~ "text/html"

      # All 7 agent scripts injected, in crit's exact order.
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
      # connect-src 'self' (not 'none') so the injected agent can fetch its
      # same-origin marker CSS without a CSP violation; external egress stays
      # blocked.
      assert csp =~ "connect-src 'self'"
      assert csp =~ "frame-src 'none'"
      # No external origins in the preview sandbox CSP.
      refute csp =~ "http"
    end

    test "appends agent scripts when there is no </body> tag", %{conn: conn} do
      review =
        review_fixture(%{
          review_type: :preview,
          files: [file("index.html", "<div>fragment with no body tag</div>")]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/index.html")

      body = response(conn, 200)
      assert body =~ "fragment with no body tag"
      assert body =~ ~s(<script src="/preview-agent/crit-agent.js"></script>)
    end

    test "serves a text asset (.css) verbatim as text/css without injection or preview CSP", %{
      conn: conn
    } do
      css = "body { color: red; }"

      review =
        review_fixture(%{
          review_type: :preview,
          files: [file("index.html", "<html><body></body></html>"), file("style.css", css)]
        })

      conn = get(conn, ~p"/r/#{review.token}/raw/style.css")

      assert response_content_type(conn, :css) =~ "text/css"
      assert response(conn, 200) == css
      refute response(conn, 200) =~ "/preview-agent/"
      # CSS assets are not HTML — no restrictive preview sandbox CSP.
      refute get_resp_header(conn, "content-security-policy")
             |> Enum.any?(&(&1 =~ "connect-src 'none'"))
    end

    test "files-mode HTML is served verbatim — no agent injection, no preview CSP", %{conn: conn} do
      html = "<html><body><h1>hi</h1></body></html>"
      review = review_fixture(%{files: [file("index.html", html)]})

      conn = get(conn, ~p"/r/#{review.token}/raw/index.html")

      body = response(conn, 200)
      assert body == html
      refute body =~ "/preview-agent/"

      refute get_resp_header(conn, "content-security-policy")
             |> Enum.any?(&(&1 =~ "connect-src 'none'"))
    end
  end

  describe "auth gate for selfhosted with OAuth" do
    setup do
      original_selfhosted = Application.get_env(:crit, :selfhosted)
      original_oauth = Application.get_env(:crit, :oauth_provider)

      Application.put_env(:crit, :selfhosted, true)
      Application.put_env(:crit, :oauth_provider, :github)

      on_exit(fn ->
        if is_nil(original_selfhosted),
          do: Application.delete_env(:crit, :selfhosted),
          else: Application.put_env(:crit, :selfhosted, original_selfhosted)

        if is_nil(original_oauth),
          do: Application.delete_env(:crit, :oauth_provider),
          else: Application.put_env(:crit, :oauth_provider, original_oauth)
      end)

      :ok
    end

    test "redirects unauthenticated visitor to /auth/login with return_to", %{conn: conn} do
      review = review_fixture(%{files: [file("lib/foo.ex", "secret")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/lib/foo.ex")

      assert redirected_to(conn) =~ "/auth/login"
      assert redirected_to(conn) =~ "return_to="
      assert redirected_to(conn) =~ URI.encode_www_form("/r/#{review.token}/raw/lib/foo.ex")
      # Body must not include the file content.
      refute response(conn, 302) =~ "secret"
    end

    test "serves file content when an authenticated user is in the session", %{conn: conn} do
      review = review_fixture(%{files: [file("lib/foo.ex", "defmodule Foo, do: :ok\n")]})

      {:ok, user} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "raw_uid_#{System.unique_integer()}",
          "email" => "raw@example.com",
          "name" => "Raw User"
        })

      conn =
        conn
        |> Plug.Test.init_test_session(%{user_id: user.id})
        |> get(~p"/r/#{review.token}/raw/lib/foo.ex")

      assert response(conn, 200) == "defmodule Foo, do: :ok\n"
    end
  end

  describe "without selfhosted+OAuth (public/hosted mode)" do
    setup do
      original_selfhosted = Application.get_env(:crit, :selfhosted)
      original_oauth = Application.get_env(:crit, :oauth_provider)

      Application.put_env(:crit, :selfhosted, false)
      Application.delete_env(:crit, :oauth_provider)

      on_exit(fn ->
        if is_nil(original_selfhosted),
          do: Application.delete_env(:crit, :selfhosted),
          else: Application.put_env(:crit, :selfhosted, original_selfhosted)

        if is_nil(original_oauth),
          do: Application.delete_env(:crit, :oauth_provider),
          else: Application.put_env(:crit, :oauth_provider, original_oauth)
      end)

      :ok
    end

    test "raw URL is reachable without auth", %{conn: conn} do
      review = review_fixture(%{files: [file("lib/foo.ex", "defmodule Foo, do: :ok\n")]})

      conn = get(conn, ~p"/r/#{review.token}/raw/lib/foo.ex")

      assert response(conn, 200) == "defmodule Foo, do: :ok\n"
    end
  end
end
