defmodule CritWeb.E2E.HideResolvedTest do
  use CritWeb.E2ECase, async: true

  # Helper: add a comment via UI and resolve it, returning a resolved comment
  # block in the document body.
  defp add_and_resolve_comment(page, body, opts \\ []) do
    add_comment_via_ui(page, body, line_index: opts[:line_index] || 0)

    card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: body)
    Locator.click!(Locator.locator(card, ".resolve-btn"))

    # Wait for the resolved-card class to appear (card DOM is replaced on resolve)
    Expect.to_have_class!(card, ~r/resolved-card/, timeout: 5_000)
  end

  defp resolved_block(page) do
    page
    |> Page.locator(".comment-block:not(.panel-comment-block)")
    |> Locator.filter(has: Page.locator(page, ".resolved-card"))
  end

  describe "Hide Resolved" do
    setup %{page: page, request: request} do
      review =
        create_review(request,
          files: [
            %{
              path: "example.md",
              content: "# Hello\n\nLine one\nLine two\nLine three\nLine four\n"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)

      # Clear hide-resolved preference before each test
      Page.goto!(page, "/")
      Page.evaluate!(page, ~s|() => { localStorage.removeItem("crit-hide-resolved"); }|)

      %{token: review.token, delete_token: review.delete_token}
    end

    test "settings panel has Hide resolved toggle in Display section", %{page: page, token: token} do
      load_review(page, token)
      open_settings_pane(page)

      toggle = Page.locator(page, "#hideResolvedToggle")
      Expect.to_be_attached!(toggle)

      # Should be unchecked by default
      Expect.not_to_be_checked!(toggle)

      # Verify the label is visible
      Expect.to_be_visible!(
        Page.locator(page, ".settings-display-label", has_text: "Hide resolved")
      )
    end

    test "settings checkbox hides resolved inline comments", %{page: page, token: token} do
      load_review(page, token)

      # Add a comment and resolve it
      add_and_resolve_comment(page, "This is resolved")

      # The resolved comment block should be visible by default
      resolved_block = resolved_block(page)
      Expect.to_be_visible!(resolved_block)

      # Enable "Hide resolved" via the settings checkbox
      open_settings_pane(page)
      toggle = Page.locator(page, "#hideResolvedToggle")
      Locator.click!(toggle)
      Expect.to_be_checked!(toggle)

      # The resolved comment block should now be hidden
      Expect.not_to_be_visible!(resolved_block)

      # Uncheck to verify it toggles back
      Locator.click!(toggle)
      Expect.not_to_be_checked!(toggle)
      Expect.to_be_visible!(resolved_block)
    end

    test "keyboard shortcut h toggles hide resolved", %{page: page, token: token} do
      load_review(page, token)

      # Add a comment and resolve it
      add_and_resolve_comment(page, "Shortcut test comment")

      resolved_block = resolved_block(page)

      # Verify visible before toggle
      Expect.to_be_visible!(resolved_block)

      # Press h to hide
      Keyboard.press!(Page.keyboard(page), "h")
      Expect.not_to_be_visible!(resolved_block)

      # Press h again to show
      Keyboard.press!(Page.keyboard(page), "h")
      Expect.to_be_visible!(resolved_block)
    end

    test "a comment ref skips a hidden resolved card and uses the open panel's copy", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      add_and_resolve_comment(page, "Ref target")

      id =
        page
        |> Page.locator(".comment-block:not(.panel-comment-block) .comment-card")
        |> Locator.filter(has_text: "Ref target")
        |> Locator.get_attribute!("data-comment-id")

      assert id

      Keyboard.press!(Page.keyboard(page), "h")

      Expect.to_be_hidden!(
        Page.locator(page, ".comment-block:not(.panel-comment-block) .resolved-card")
      )

      # Click a ref chip for the card and report which copies flashed. Refs
      # hold crit's c_... ids, which never equal a crit-web card id, so the
      # chip is added here with the card's id. The click handler runs
      # synchronously, so the flash class is read before its animation ends.
      click_ref = fn ->
        Page.evaluate!(
          page,
          """
          refId => {
            const chip = document.createElement("span");
            chip.className = "comment-ref";
            chip.dataset.refId = refId;
            document.body.appendChild(chip);
            chip.click();
            chip.remove();
            return Array.from(document.querySelectorAll(".comment-ref-flash"))
              .map(card => (card.closest("#commentsPanel") ? "panel" : "inline"));
          }
          """,
          id
        )
      end

      # Panel closed, inline card hidden: nothing to scroll to.
      assert click_ref.() == []

      # Panel open: its copy flashes.
      Keyboard.press!(Page.keyboard(page), "Shift+C")

      Expect.to_be_visible!(
        Page.locator(page, ~s(#commentsPanel .comment-card[data-comment-id="#{id}"]))
      )

      assert click_ref.() == ["panel"]
    end

    test "comment arrows skip hidden resolved comments in both directions", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Open A", start_line: 1)
      seed_comment(request, token, body: "Open C", start_line: 6)
      load_review(page, token)
      add_and_resolve_comment(page, "Resolved B", line_index: 1)

      open_a =
        page
        |> Page.locator(".comment-card:not(.resolved-card)")
        |> Locator.filter(has_text: "Open A")

      resolved_card =
        page
        |> Page.locator(".comment-card.resolved-card")
        |> Locator.filter(has_text: "Resolved B")

      open_c =
        page
        |> Page.locator(".comment-card:not(.resolved-card)")
        |> Locator.filter(has_text: "Open C")

      Locator.click!(Page.locator(page, "#comment-nav-next"))
      Expect.to_have_class!(open_a, ~r/comment-nav-highlight/)
      Locator.click!(Page.locator(page, "#comment-nav-next"))
      Expect.to_have_class!(resolved_card, ~r/comment-nav-highlight/)

      Keyboard.press!(Page.keyboard(page), "h")
      Expect.not_to_be_visible!(resolved_card)
      Locator.click!(Page.locator(page, "#comment-nav-prev"))
      Expect.to_have_class!(open_a, ~r/comment-nav-highlight/)
      Expect.not_to_have_class!(open_c, ~r/comment-nav-highlight/)
      Expect.not_to_have_class!(resolved_card, ~r/comment-nav-highlight/)

      Keyboard.press!(Page.keyboard(page), "h")
      Locator.click!(Page.locator(page, "#comment-nav-next"))
      Expect.to_have_class!(resolved_card, ~r/comment-nav-highlight/)

      Keyboard.press!(Page.keyboard(page), "h")
      Locator.click!(Page.locator(page, "#comment-nav-next"))
      Expect.to_have_class!(open_c, ~r/comment-nav-highlight/)
      Expect.not_to_have_class!(resolved_card, ~r/comment-nav-highlight/)
    end

    test "resolving a comment while hide resolved is enabled hides it", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      add_comment_via_ui(page, "Resolve while hidden")
      Keyboard.press!(Page.keyboard(page), "h")

      card =
        page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Resolve while hidden")

      Locator.click!(Locator.locator(card, ".resolve-btn"))

      Expect.not_to_be_visible!(resolved_block(page))
    end

    test "persists via localStorage across reload", %{page: page, token: token} do
      load_review(page, token)

      # Add a comment and resolve it
      add_and_resolve_comment(page, "Persist test comment")

      # Enable hide resolved
      Keyboard.press!(Page.keyboard(page), "h")

      resolved_block = resolved_block(page)
      Expect.not_to_be_visible!(resolved_block)

      # Verify localStorage was set
      stored = Page.evaluate!(page, ~s|() => localStorage.getItem("crit-hide-resolved")|)
      assert stored == "true"

      # Reload the page
      load_review(page, token)

      # The resolved comment should still be hidden after reload
      # Wait for the comment to be rendered first
      page
      |> Page.locator(".comment-card")
      |> Locator.filter(has_text: "Persist test comment")
      |> Expect.to_be_attached!(timeout: 10_000)

      # The block containing the resolved card should be hidden (display: none)
      reloaded_block = resolved_block(page)
      Expect.not_to_be_visible!(reloaded_block)
    end
  end
end
