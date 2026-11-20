defmodule CritWeb.E2E.DisplayNameBroadcastTest do
  use CritWeb.E2ECase, async: true

  # Set a display name on the given page via the name pill.
  defp set_display_name(page, name) do
    name_btn = Page.locator(page, "#name-pill-btn")
    Expect.to_be_visible!(name_btn)
    Locator.click!(name_btn)

    name_input = Page.locator(page, "#name-input")
    Expect.to_be_visible!(name_input)
    Locator.fill!(name_input, name)

    Locator.click!(Page.locator(page, ".crit-name-save"))

    # Wait for the name to appear in the button
    Expect.to_contain_text!(name_btn, name)
  end

  describe "Display Name Broadcast" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "setting display name updates comment author badge on other tab", %{
      browser: browser,
      token: token
    } do
      # Use two separate browser contexts to simulate two users
      context1 = Browser.new_context!(browser)
      context2 = Browser.new_context!(browser)

      page1 = BrowserContext.new_page!(context1)
      page2 = BrowserContext.new_page!(context2)

      try do
        load_review(page1, token)
        load_review(page2, token)

        # Page 1 sets a display name
        set_display_name(page1, "Alice")

        # Page 1 adds a comment (should have author badge "Alice")
        gutter = Locator.first(Page.locator(page1, ".line-gutter"))
        Locator.click!(gutter)
        textarea = Page.locator(page1, ".comment-form textarea")
        Expect.to_be_visible!(textarea, timeout: 5_000)
        Locator.fill!(textarea, "Comment from Alice")
        Locator.press!(textarea, "Control+Enter")
        wait_for_comment_card(page1, "Comment from Alice")

        # Page 2 should see the comment with author badge
        wait_for_comment_card(page2, "Comment from Alice")

        # The comment on page 2 should show the author name
        card2 =
          page2 |> Page.locator(".comment-card") |> Locator.filter(has_text: "Comment from Alice")

        Expect.to_contain_text!(Locator.locator(card2, ".comment-author-badge"), "Alice",
          timeout: 5_000
        )
      after
        BrowserContext.close!(context1)
        BrowserContext.close!(context2)
      end
    end

    test "display name set on page persists in the pill button", %{page: page, token: token} do
      load_review(page, token)

      set_display_name(page, "TestReviewer")

      # Verify it shows in the button
      Expect.to_contain_text!(Page.locator(page, "#name-pill-btn"), "TestReviewer")
    end
  end
end
