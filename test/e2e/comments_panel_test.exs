defmodule CritWeb.E2E.CommentsPanelTest do
  use CritWeb.E2ECase, async: true

  # Comments panel — merged spec covering:
  # 1. Toggle & visibility (open/close, panel rendering, scroll-to-comment)
  # 2. Filter & grouping (segmented filter pill, count badge, file groups,
  #    expand/collapse all)
  #
  # The redundant "Show resolved filter" test from the legacy detail spec is
  # dropped — coverage lives in the segmented-filter tests below.

  defp open_panel(page) do
    Locator.click!(Page.locator(page, "#comment-count"))
    panel = Page.locator(page, ".comments-panel")
    Expect.to_have_class!(panel, ~r/comments-panel-open/, timeout: 5_000)
    panel
  end

  describe "Comments Panel — Toggle & visibility" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{
              path: "example.md",
              content:
                "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n" <>
                  "Line 11\nLine 12\nLine 13\nLine 14\nLine 15\nLine 16\nLine 17\nLine 18\nLine 19\nLine 20\n"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "panel shows all comments", %{page: page, request: request, token: token} do
      seed_comment(request, token, body: "First panel comment", start_line: 1)
      seed_comment(request, token, body: "Second panel comment", start_line: 5)

      load_review(page, token)
      wait_for_comment_card(page, "First panel comment")

      Locator.click!(Page.locator(page, "#comment-count"))
      panel = Page.locator(page, ".comments-panel")
      Expect.to_be_visible!(panel, timeout: 5_000)

      Expect.to_contain_text!(panel, "First panel comment")
      Expect.to_contain_text!(panel, "Second panel comment")
    end

    test "Shift+C toggles panel open and closed", %{page: page, request: request, token: token} do
      seed_comment(request, token, body: "Toggle test", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "Toggle test")

      panel = Page.locator(page, ".comments-panel")

      Keyboard.press!(Page.keyboard(page), "Shift+C")
      Expect.to_have_class!(panel, ~r/comments-panel-open/, timeout: 5_000)

      Keyboard.press!(Page.keyboard(page), "Shift+C")
      Expect.not_to_have_class!(panel, ~r/comments-panel-open/)
    end

    test "close button hides panel", %{page: page, request: request, token: token} do
      seed_comment(request, token, body: "Close button test", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "Close button test")

      Locator.click!(Page.locator(page, "#comment-count"))
      panel = Page.locator(page, ".comments-panel")
      Expect.to_have_class!(panel, ~r/comments-panel-open/, timeout: 5_000)

      Locator.click!(Locator.locator(panel, ".comments-panel-close"))
      Expect.not_to_have_class!(panel, ~r/comments-panel-open/)
    end

    test "clicking a comment in panel scrolls to inline comment", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Bottom comment to scroll to", start_line: 18)

      load_review(page, token)
      wait_for_comment_card(page, "Bottom comment to scroll to")

      Locator.click!(Page.locator(page, "#comment-count"))
      panel = Page.locator(page, ".comments-panel")
      Expect.to_have_class!(panel, ~r/comments-panel-open/, timeout: 5_000)

      panel_comment = Locator.first(Locator.locator(panel, ".panel-comment-block"))
      Locator.click!(panel_comment)

      inline_card =
        Locator.filter(Page.locator(page, "#document-renderer .comment-card"),
          has_text: "Bottom comment to scroll to"
        )

      Expect.to_be_visible!(inline_card, timeout: 5_000)
    end
  end

  describe "Comments Panel — Filter & grouping" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{
              path: "main.ts",
              content:
                "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "panel header shows correct count badge", %{page: page, request: request, token: token} do
      seed_comment(request, token, body: "Comment A", start_line: 1)
      seed_comment(request, token, body: "Comment B", start_line: 3)
      seed_comment(request, token, body: "Comment C", start_line: 5)

      load_review(page, token)
      wait_for_comment_card(page, "Comment A")

      panel = open_panel(page)

      badge = Locator.locator(panel, "#commentsPanelCountBadge")
      Expect.to_have_text!(badge, "3")
    end

    test "segmented filter defaults to All with all comments shown", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Open comment", start_line: 1)
      seed_comment(request, token, body: "Another open", start_line: 3)

      load_review(page, token)
      wait_for_comment_card(page, "Open comment")

      panel = open_panel(page)

      all_btn = Locator.locator(panel, ~s(.crit-toggle-btn[data-filter="all"]))
      Expect.to_have_class!(all_btn, ~r/crit-toggle-btn--active/)

      Expect.to_contain_text!(panel, "Open comment")
      Expect.to_contain_text!(panel, "Another open")
    end

    test "segmented filter Open shows only unresolved comments", %{page: page, token: token} do
      load_review(page, token)

      add_comment_via_ui(page, "Will stay open", line_index: 0)
      add_comment_via_ui(page, "Will be resolved", line_index: 4)

      resolved_card =
        Locator.filter(Page.locator(page, ".comment-card"), has_text: "Will be resolved")

      Locator.click!(Locator.locator(resolved_card, ".resolve-btn"))
      Expect.to_have_class!(resolved_card, ~r/resolved-card/, timeout: 5_000)

      panel = open_panel(page)

      open_btn = Locator.locator(panel, ~s(.crit-toggle-btn[data-filter="open"]))
      Locator.click!(open_btn)
      Expect.to_have_class!(open_btn, ~r/crit-toggle-btn--active/)

      Expect.to_contain_text!(panel, "Will stay open")

      Expect.not_to_be_visible!(
        Locator.filter(Locator.locator(panel, ".panel-comment-block"),
          has_text: "Will be resolved"
        )
      )
    end

    test "segmented filter Resolved shows only resolved comments", %{page: page, token: token} do
      load_review(page, token)

      add_comment_via_ui(page, "Stays open", line_index: 0)
      add_comment_via_ui(page, "Gets resolved", line_index: 4)

      card = Locator.filter(Page.locator(page, ".comment-card"), has_text: "Gets resolved")
      Locator.click!(Locator.locator(card, ".resolve-btn"))
      Expect.to_have_class!(card, ~r/resolved-card/, timeout: 5_000)

      panel = open_panel(page)

      resolved_btn = Locator.locator(panel, ~s(.crit-toggle-btn[data-filter="resolved"]))
      Locator.click!(resolved_btn)
      Expect.to_have_class!(resolved_btn, ~r/crit-toggle-btn--active/)

      Expect.to_contain_text!(panel, "Gets resolved")

      Expect.not_to_be_visible!(
        Locator.filter(Locator.locator(panel, ".panel-comment-block"), has_text: "Stays open")
      )
    end

    test "filter pill counts match actual comment counts", %{page: page, token: token} do
      load_review(page, token)

      add_comment_via_ui(page, "Open one", line_index: 0)
      add_comment_via_ui(page, "Open two", line_index: 2)
      add_comment_via_ui(page, "To resolve", line_index: 4)

      card = Locator.filter(Page.locator(page, ".comment-card"), has_text: "To resolve")
      Locator.click!(Locator.locator(card, ".resolve-btn"))
      Expect.to_have_class!(card, ~r/resolved-card/, timeout: 5_000)

      panel = open_panel(page)

      all_count = Locator.locator(panel, ~s(.crit-toggle-btn[data-filter="all"] .filter-count))
      open_count = Locator.locator(panel, ~s(.crit-toggle-btn[data-filter="open"] .filter-count))

      resolved_count =
        Locator.locator(panel, ~s(.crit-toggle-btn[data-filter="resolved"] .filter-count))

      Expect.to_have_text!(all_count, "3")
      Expect.to_have_text!(open_count, "2")
      Expect.to_have_text!(resolved_count, "1")
    end

    test "collapsible file groups toggle on click", %{page: page, request: request} do
      multi_file_review =
        create_review(request,
          files: [
            %{path: "alpha.ts", content: "Line 1\nLine 2\nLine 3\n"},
            %{path: "beta.ts", content: "Line 1\nLine 2\nLine 3\n"}
          ]
        )

      mf_token = multi_file_review.token

      seed_comment(request, mf_token, body: "File comment", start_line: 1, file: "alpha.ts")

      load_review(page, mf_token)
      wait_for_comment_card(page, "File comment")

      panel = open_panel(page)

      file_group = Locator.first(Locator.locator(panel, ".comments-panel-file-group"))
      file_cards = Locator.locator(file_group, ".comments-panel-file-cards")

      Expect.to_be_visible!(file_cards)

      file_header = Locator.locator(file_group, ".comments-panel-file-name")
      Locator.click!(file_header)
      Expect.to_have_class!(file_group, ~r/collapsed/)

      Locator.click!(file_header)
      Expect.not_to_have_class!(file_group, ~r/collapsed/)

      delete_review(request, multi_file_review.delete_token)
    end

    test "Expand all / Collapse all toggles all comment cards", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Card one", start_line: 1)
      seed_comment(request, token, body: "Card two", start_line: 3)

      load_review(page, token)
      wait_for_comment_card(page, "Card one")

      panel = open_panel(page)

      expand_all_btn = Locator.locator(panel, "#commentsPanelExpandAll")

      Expect.to_have_text!(expand_all_btn, "Collapse all")

      Locator.click!(expand_all_btn)

      panel_cards = Locator.locator(panel, ".comment-card")
      count = Locator.count!(panel_cards)
      assert count >= 2

      for i <- 0..(count - 1)//1 do
        Expect.to_have_class!(Locator.nth(panel_cards, i), ~r/collapsed/)
      end

      Expect.to_have_text!(expand_all_btn, "Expand all")

      Locator.click!(expand_all_btn)

      for i <- 0..(count - 1)//1 do
        Expect.not_to_have_class!(Locator.nth(panel_cards, i), ~r/collapsed/)
      end

      Expect.to_have_text!(expand_all_btn, "Collapse all")
    end

    test "Collapse all also collapses inline comments in the document body", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Inline collapse test", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "Inline collapse test")

      panel = open_panel(page)

      inline_card =
        Locator.filter(Page.locator(page, "#document-renderer .comment-card"),
          has_text: "Inline collapse test"
        )

      Expect.to_be_visible!(inline_card)
      Expect.not_to_have_class!(inline_card, ~r/collapsed/)

      expand_all_btn = Locator.locator(panel, "#commentsPanelExpandAll")
      Locator.click!(expand_all_btn)

      Expect.to_have_class!(inline_card, ~r/collapsed/)

      Locator.click!(expand_all_btn)
      Expect.not_to_have_class!(inline_card, ~r/collapsed/)
    end
  end
end
