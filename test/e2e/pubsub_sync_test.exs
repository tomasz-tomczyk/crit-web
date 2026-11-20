defmodule CritWeb.E2E.PubsubSyncTest do
  use CritWeb.E2ECase, async: true

  describe "Multi-User PubSub Sync" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "comment added on page 1 appears on page 2 via PubSub",
         %{browser: browser, token: token} do
      # Open two separate browser contexts (simulates two users)
      context1 = Browser.new_context!(browser)
      context2 = Browser.new_context!(browser)

      page1 = BrowserContext.new_page!(context1)
      page2 = BrowserContext.new_page!(context2)

      try do
        # Load the same review on both pages
        load_review(page1, token)
        load_review(page2, token)

        # Add a comment on page 1
        add_comment_via_ui(page1, "Synced from page 1")

        # Page 2 should receive the comment via PubSub
        wait_for_comment_card(page2, "Synced from page 1")

        # Both pages should show count of 1
        Expect.to_have_text!(Page.locator(page1, "#commentCountNumber"), "1")
        Expect.to_have_text!(Page.locator(page2, "#commentCountNumber"), "1")
      after
        BrowserContext.close!(context1)
        BrowserContext.close!(context2)
      end
    end

    test "reply added on page 1 appears on page 2 via PubSub",
         %{browser: browser, token: token} do
      context1 = Browser.new_context!(browser)
      context2 = Browser.new_context!(browser)

      page1 = BrowserContext.new_page!(context1)
      page2 = BrowserContext.new_page!(context2)

      try do
        load_review(page1, token)
        load_review(page2, token)

        # Add a comment on page 1
        add_comment_via_ui(page1, "Comment for reply sync")

        # Wait for it to appear on page 2
        wait_for_comment_card(page2, "Comment for reply sync")

        # Add a reply on page 1
        card1 =
          page1
          |> Page.locator(".comment-card")
          |> Locator.filter(has_text: "Comment for reply sync")

        Locator.click!(Locator.locator(card1, ".reply-input"))
        reply_textarea = Locator.locator(card1, ".reply-textarea")
        Expect.to_be_visible!(reply_textarea, timeout: 5_000)
        Locator.fill!(reply_textarea, "Reply synced via PubSub")
        Locator.click!(Locator.locator(card1, ".reply-form-buttons .btn-primary"))

        # Wait for reply to appear on page 1
        card1
        |> Locator.locator(".reply-body")
        |> Locator.filter(has_text: "Reply synced via PubSub")
        |> Expect.to_be_visible!(timeout: 5_000)

        # Reply should also appear on page 2
        card2 =
          page2
          |> Page.locator(".comment-card")
          |> Locator.filter(has_text: "Comment for reply sync")

        card2
        |> Locator.locator(".reply-body")
        |> Locator.filter(has_text: "Reply synced via PubSub")
        |> Expect.to_be_visible!(timeout: 10_000)
      after
        BrowserContext.close!(context1)
        BrowserContext.close!(context2)
      end
    end

    test "resolve on page 1 syncs to page 2 via PubSub", %{browser: browser, token: token} do
      context1 = Browser.new_context!(browser)
      context2 = Browser.new_context!(browser)

      page1 = BrowserContext.new_page!(context1)
      page2 = BrowserContext.new_page!(context2)

      try do
        load_review(page1, token)
        load_review(page2, token)

        # Add a comment on page 1
        add_comment_via_ui(page1, "Resolve sync test")

        # Wait for it on page 2
        wait_for_comment_card(page2, "Resolve sync test")

        # Resolve on page 1
        card1 =
          page1 |> Page.locator(".comment-card") |> Locator.filter(has_text: "Resolve sync test")

        Locator.click!(Locator.locator(card1, ".resolve-btn"))

        # Should show resolved state on page 1
        Expect.to_be_visible!(Page.locator(page1, ".comment-card.resolved-card"), timeout: 5_000)

        # Should also show resolved state on page 2
        Expect.to_be_visible!(Page.locator(page2, ".comment-card.resolved-card"), timeout: 10_000)
      after
        BrowserContext.close!(context1)
        BrowserContext.close!(context2)
      end
    end
  end
end
