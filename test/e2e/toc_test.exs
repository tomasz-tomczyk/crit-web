defmodule CritWeb.E2E.TocTest do
  use CritWeb.E2ECase, async: true

  describe "Table of Contents" do
    # Module-level `let deleteToken` set by each test: the test sends it here,
    # and the afterEach deletes the review when one was created.
    setup %{request: request} do
      {:ok, holder} = Agent.start(fn -> nil end)

      on_exit(fn ->
        delete_token = Agent.get(holder, & &1)
        Agent.stop(holder)
        if delete_token, do: delete_review(request, delete_token)
      end)

      %{holder: holder}
    end

    defp track(holder, review), do: Agent.update(holder, fn _ -> review.delete_token end)

    test "toggle button is visible and panel opens when document has headings",
         %{page: page, request: request, holder: holder} do
      review =
        create_review(request,
          files: [
            %{
              path: "with-headings.md",
              content: "# Top Heading\n\nSome content.\n\n## Subsection\n\nMore content.\n"
            }
          ]
        )

      track(holder, review)

      Page.set_viewport_size!(page, %{width: 1400, height: 900})
      load_review(page, review.token)

      toggle = Page.locator(page, "#crit-toc-toggle")
      panel = Page.locator(page, "#crit-toc")

      Expect.to_be_visible!(toggle)
      Expect.to_have_count!(Locator.locator(panel, ".crit-toc-list a"), 2)
      # On a wide viewport with no saved preference, the panel auto-opens.
      Expect.not_to_have_class!(panel, ~r/crit-toc-hidden/)
    end

    test "scroll spy highlights active heading after content arrives",
         %{page: page, request: request, holder: holder} do
      # Long doc so that scrolling moves a later heading above the threshold.
      blocks =
        Enum.map_join(1..6, "\n\n", fn i ->
          filler = Enum.map_join(1..40, "\n", fn _ -> "filler line" end)
          "## Heading #{i}\n\n#{filler}"
        end)

      review =
        create_review(request, files: [%{path: "long.md", content: "# Top\n\n#{blocks}\n"}])

      track(holder, review)

      Page.set_viewport_size!(page, %{width: 1400, height: 900})
      load_review(page, review.token)

      panel = Page.locator(page, "#crit-toc")
      # Wait until headings are populated (init handler ran).
      Expect.to_have_count!(Locator.locator(panel, ".crit-toc-list a"), 7)

      # Scroll well past the first heading.
      Page.evaluate!(page, "() => window.scrollBy(0, 2000)")
      Expect.to_have_count!(Locator.locator(panel, ".crit-toc-list a.crit-toc-active"), 1)
    end

    test "toggle button is hidden when document has only one heading",
         %{page: page, request: request, holder: holder} do
      review =
        create_review(request,
          files: [
            %{
              path: "one-heading.md",
              content: "# Only heading\n\nSome body text, no other headings.\n"
            }
          ]
        )

      track(holder, review)

      Page.set_viewport_size!(page, %{width: 1400, height: 900})
      load_review(page, review.token)

      Expect.to_be_hidden!(Page.locator(page, "#crit-toc-toggle"))
      Expect.to_have_class!(Page.locator(page, "#crit-toc"), ~r/crit-toc-hidden/)
    end

    test "toggle button and panel are hidden when document has no headings",
         %{page: page, request: request, holder: holder} do
      review =
        create_review(request,
          files: [
            %{
              path: "no-headings.md",
              content: "Just a paragraph of text.\n\nAnother paragraph, no headings here.\n"
            }
          ]
        )

      track(holder, review)

      # Wide viewport — default behavior would open TOC if not guarded
      Page.set_viewport_size!(page, %{width: 1400, height: 900})
      load_review(page, review.token)

      toggle = Page.locator(page, "#crit-toc-toggle")
      panel = Page.locator(page, "#crit-toc")

      Expect.to_be_hidden!(toggle)
      Expect.to_have_class!(panel, ~r/crit-toc-hidden/)
    end

    test "panel stays hidden for empty TOC even when localStorage says open",
         %{page: page, request: request, holder: holder} do
      review =
        create_review(request,
          files: [
            %{path: "no-headings.md", content: "Just text. No headings at all in this file.\n"}
          ]
        )

      track(holder, review)

      # Pre-seed localStorage with a previous "open" state
      Page.goto!(page, "/")
      Page.evaluate!(page, ~s|() => localStorage.setItem("crit-toc", "open")|)

      Page.set_viewport_size!(page, %{width: 1400, height: 900})
      load_review(page, review.token)

      toggle = Page.locator(page, "#crit-toc-toggle")
      panel = Page.locator(page, "#crit-toc")

      Expect.to_be_hidden!(toggle)
      Expect.to_have_class!(panel, ~r/crit-toc-hidden/)
    end
  end
end
