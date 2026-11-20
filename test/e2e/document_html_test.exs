defmodule CritWeb.E2E.DocumentHtmlTest do
  use CritWeb.E2ECase, async: true

  alias Playwright.Route

  # Raw HTML in a shared document must not run script on the review page.
  @content Enum.join(
             [
               "# Raw HTML",
               "",
               ~s(before <img src=x onerror="window.__xss=1"> after),
               "",
               ~s(<div onclick="window.__xss=1"><script>window.__xss=1</script>block</div>),
               "",
               ~s(a <a href="javascript:window.__xss=1">bad</a> link),
               "",
               "<details><summary>More</summary>hidden</details>",
               "",
               ~s(<div class="overlay" style="position:fixed;inset:0">cover</div>),
               "",
               # A real review-page class (a fixed, full-page overlay), a page id, and a
               # fake comment card that comment links would jump to.
               ~s(<div class="crit-prompt-overlay" id="commentsPanel">overlay class</div>),
               "",
               ~s(<div class="comment-card" data-comment-id="fake-card">fake card</div>),
               "",
               # Id references: a label for a real review-page button, and every other
               # attribute that names ids.
               ~s(<label for="settingsToggle">open settings</label>),
               "",
               ~s(<span aria-labelledby="a b" aria-describedby="c" aria-controls="d" aria-owns="e">aria refs</span>),
               "",
               ~s(<input list="choices" aria-label="list ref">),
               "",
               ~s(<table><tr><td headers="h1 h2">cell ref</td></tr></table>),
               "",
               ~s(<img alt="map ref" usemap=" #shapes" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"><map name="shapes"></map>),
               ""
             ],
             "\n"
           )

  describe "Document HTML sanitizing" do
    setup %{request: request} do
      review = create_review(request, files: [%{path: "raw.md", content: @content}])
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "strips handlers, scripts, javascript: URLs and positioning styles and keeps plain HTML",
         %{page: page, token: token} do
      load_review(page, token)
      doc = Page.locator(page, "#document-renderer")

      # The broken image still renders (then becomes a placeholder) but
      # without its handler. The CSP blocks inline handlers too; these checks
      # cover the markup itself.
      Expect.to_have_text!(Locator.locator(doc, ".img-placeholder"), "[image]")
      Expect.to_have_count!(Locator.locator(doc, "[onerror], [onclick]"), 0)
      Expect.to_be_visible!(Locator.get_by_text(doc, "block", exact: true))
      Expect.to_have_count!(Locator.locator(doc, "script"), 0)
      Expect.not_to_have_attribute!(Locator.locator(doc, "a", has_text: "bad"), "href")
      Expect.to_have_text!(Locator.locator(doc, "details summary"), "More")
      Expect.not_to_have_attribute!(Locator.get_by_text(doc, "cover", exact: true), "style")
      assert Page.evaluate!(page, "() => window.__xss") == nil
    end

    test "prefixes author ids and classes and drops data attributes", %{page: page, token: token} do
      load_review(page, token)
      doc = Page.locator(page, "#document-renderer")

      # Page classes and ids from the document get a user-content- prefix, so
      # the page's fixed overlay rule does not apply.
      overlay = Locator.get_by_text(doc, "overlay class", exact: true)
      Expect.to_have_attribute!(overlay, "class", "user-content-crit-prompt-overlay")
      Expect.to_have_attribute!(overlay, "id", "user-content-commentsPanel")
      assert Locator.evaluate!(overlay, "el => getComputedStyle(el).position") == "static"

      # The fake card is neither a .comment-card nor carries data-comment-id.
      fake = Locator.get_by_text(doc, "fake card", exact: true)
      Expect.to_have_attribute!(fake, "class", "user-content-comment-card")
      Expect.not_to_have_attribute!(fake, "data-comment-id")
      Expect.to_have_count!(Page.locator(page, ~s([data-comment-id="fake-card"])), 0)
    end

    test "prefixes id references, so a label can't press a review-page button",
         %{page: page, token: token} do
      load_review(page, token)
      doc = Page.locator(page, "#document-renderer")

      label = Locator.get_by_text(doc, "open settings", exact: true)
      Expect.to_have_attribute!(label, "for", "user-content-settingsToggle")
      Locator.click!(label)
      Expect.to_have_count!(Page.locator(page, "#settingsOverlay.active"), 0)

      aria = Locator.get_by_text(doc, "aria refs", exact: true)
      Expect.to_have_attribute!(aria, "aria-labelledby", "user-content-a user-content-b")
      Expect.to_have_attribute!(aria, "aria-describedby", "user-content-c")
      Expect.to_have_attribute!(aria, "aria-controls", "user-content-d")
      Expect.to_have_attribute!(aria, "aria-owns", "user-content-e")

      Expect.to_have_attribute!(
        Locator.locator(doc, ~s(input[aria-label="list ref"])),
        "list",
        "user-content-choices"
      )

      Expect.to_have_attribute!(
        Locator.get_by_text(doc, "cell ref", exact: true),
        "headers",
        "user-content-h1 user-content-h2"
      )

      Expect.to_have_attribute!(
        Locator.locator(doc, ~s(img[alt="map ref"])),
        "usemap",
        "#user-content-shapes"
      )

      Expect.to_have_attribute!(Locator.locator(doc, "map"), "name", "user-content-shapes")
    end
  end

  # Relative image paths point at the review's raw route. The src arrives
  # HTML-escaped (and percent-encoded by markdown-it), so it must be decoded
  # once before each path segment is encoded.
  describe "Document image paths" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{
              path: "docs/plan.md",
              content:
                "# Images\n\n![amp](img/a&b.png)\n\n![space](<img/my pic.png>)\n\n<img alt=\"raw\" src=\"img/x&amp;y.png\">\n"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "encodes each path segment once", %{page: page, token: token} do
      # Serve a 1x1 PNG so the images stay on the page (a broken image is
      # swapped for a placeholder).
      png =
        Base.decode64!(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        )

      Page.route!(page, "**/raw/docs/img/**", fn route ->
        Route.fulfill!(route, content_type: "image/png", body: {:binary, png})
      end)

      load_review(page, token)
      doc = Page.locator(page, "#document-renderer")

      Expect.to_have_attribute!(
        Locator.locator(doc, ~s(img[alt="amp"])),
        "src",
        "/r/#{token}/raw/docs/img/a%26b.png"
      )

      Expect.to_have_attribute!(
        Locator.locator(doc, ~s(img[alt="space"])),
        "src",
        "/r/#{token}/raw/docs/img/my%20pic.png"
      )

      Expect.to_have_attribute!(
        Locator.locator(doc, ~s(img[alt="raw"])),
        "src",
        "/r/#{token}/raw/docs/img/x%26y.png"
      )
    end
  end

  # Crit's own markup never goes through the raw-HTML pass, so it keeps its
  # ids and classes even next to raw HTML.
  describe "Document HTML — crit's own markup" do
    setup %{request: request} do
      content =
        Enum.join(
          # Push the link target below the fold.
          [
            ~s(# Setup <kbd class="key">Ctrl</kbd>),
            "",
            "```js",
            "const a = 1",
            "```",
            ""
          ] ++
            Enum.map(1..60, &"Filler #{&1}.\n") ++
            [~s(Run <span id="cmd">this</span>:), ""],
          "\n"
        )

      review = create_review(request, files: [%{path: "own.md", content: content}])
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "headings and fences keep their ids and classes; author ids still work as link targets",
         %{page: page, token: token} do
      load_review(page, token)
      doc = Page.locator(page, "#document-renderer")

      heading = Locator.locator(doc, "h1")
      id = Locator.get_attribute!(heading, "id")
      assert id not in [nil, ""]
      refute id =~ ~r/^user-content-/
      Expect.to_have_count!(Locator.locator(doc, ~s(a.heading-anchor[href="##{id}"])), 1)
      Expect.to_have_attribute!(Locator.locator(heading, "kbd"), "class", "user-content-key")

      # The fence renders as crit's per-line code markup.
      Expect.to_have_count!(Locator.locator(doc, ".fence-marker"), 2)
      Expect.to_have_count!(Locator.locator(doc, "code.crit-code", has_text: "const a = 1"), 1)

      # #cmd finds the author's id="user-content-cmd", as on GitHub.
      target = Locator.locator(doc, "#user-content-cmd")
      Expect.to_have_text!(target, "this")
      Expect.not_to_be_in_viewport!(target)
      Page.evaluate!(page, ~s|() => { window.location.hash = "cmd"; }|)
      Expect.to_be_in_viewport!(target)
    end
  end
end
