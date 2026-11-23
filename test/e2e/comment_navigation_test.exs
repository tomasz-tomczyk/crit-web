defmodule CritWeb.E2E.CommentNavigationTest do
  use CritWeb.E2ECase, async: true

  # Navigation jumps add a transient `.comment-nav-highlight` class to the
  # target card (removed again after ~1s), so assertions are fully
  # condition-based — no sleeps needed.
  defp highlighted_card(page), do: Page.locator(page, ".comment-card.comment-nav-highlight")

  defp seed_two_comments(request, token) do
    seed_comment(request, token, body: "First comment at top", start_line: 1)
    seed_comment(request, token, body: "Second comment lower", start_line: 10)
  end

  describe "Comment Navigation" do
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

    test "prev/next buttons navigate between comments", %{
      page: page,
      request: request,
      token: token
    } do
      seed_two_comments(request, token)

      load_review(page, token)

      first =
        Locator.filter(Page.locator(page, ".comment-card"), has_text: "First comment at top")

      second =
        Locator.filter(Page.locator(page, ".comment-card"), has_text: "Second comment lower")

      wait_for_comment_card(page, "First comment at top")
      wait_for_comment_card(page, "Second comment lower")

      # Next → highlights the first comment
      Locator.click!(Page.locator(page, "#comment-nav-next"))
      Expect.to_have_class!(first, ~r/comment-nav-highlight/)

      # Wait for the transient highlight to clear before the next jump
      Expect.not_to_have_class!(first, ~r/comment-nav-highlight/)

      # Next again → highlights the second comment
      Locator.click!(Page.locator(page, "#comment-nav-next"))
      Expect.to_have_class!(second, ~r/comment-nav-highlight/)
      Expect.not_to_have_class!(second, ~r/comment-nav-highlight/)

      # Previous → back to the first comment
      Locator.click!(Page.locator(page, "#comment-nav-prev"))
      Expect.to_have_class!(first, ~r/comment-nav-highlight/)
    end

    test "keyboard shortcuts [ and ] navigate comments", %{
      page: page,
      request: request,
      token: token
    } do
      seed_two_comments(request, token)

      load_review(page, token)

      first =
        Locator.filter(Page.locator(page, ".comment-card"), has_text: "First comment at top")

      second =
        Locator.filter(Page.locator(page, ".comment-card"), has_text: "Second comment lower")

      wait_for_comment_card(page, "First comment at top")
      wait_for_comment_card(page, "Second comment lower")

      # ] → next comment gets highlighted
      Keyboard.press!(Page.keyboard(page), "]")
      Expect.to_have_count!(highlighted_card(page), 1)
      Expect.to_have_class!(first, ~r/comment-nav-highlight/)
      Expect.not_to_have_class!(first, ~r/comment-nav-highlight/)

      # ] again → the second comment
      Keyboard.press!(Page.keyboard(page), "]")
      Expect.to_have_class!(second, ~r/comment-nav-highlight/)
      Expect.not_to_have_class!(second, ~r/comment-nav-highlight/)

      # [ → back to the first comment
      Keyboard.press!(Page.keyboard(page), "[")
      Expect.to_have_class!(first, ~r/comment-nav-highlight/)
    end

    test "review-scope comments come before inline cards", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Review scope note", scope: "review")
      seed_comment(request, token, body: "Inline note", start_line: 8)

      load_review(page, token)

      review_card =
        Locator.filter(Page.locator(page, "#reviewConversation .comment-card"),
          has_text: "Review scope note"
        )

      inline =
        Locator.filter(Page.locator(page, "#document-renderer .comment-card"),
          has_text: "Inline note"
        )

      Expect.to_be_visible!(review_card)
      wait_for_comment_card(page, "Inline note")

      Keyboard.press!(Page.keyboard(page), "]")
      Expect.to_have_class!(review_card, ~r/comment-nav-highlight/)
      Expect.not_to_have_class!(review_card, ~r/comment-nav-highlight/)

      Keyboard.press!(Page.keyboard(page), "]")
      Expect.to_have_class!(inline, ~r/comment-nav-highlight/)
      Expect.not_to_have_class!(review_card, ~r/comment-nav-highlight/)
    end

    test "] opens a collapsed review conversation to reach its comment", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Review scope note", scope: "review")
      seed_comment(request, token, body: "Inline note", start_line: 8)

      Page.add_init_script!(page, """
      localStorage.setItem("crit-review-conversation-collapsed", "1");
      """)

      load_review(page, token)

      section = Page.locator(page, "#reviewConversation")

      review_card =
        Locator.filter(Locator.locator(section, ".comment-card"), has_text: "Review scope note")

      inline =
        Locator.filter(Page.locator(page, "#document-renderer .comment-card"),
          has_text: "Inline note"
        )

      Expect.to_be_visible!(section)
      Expect.to_have_class!(section, ~r/collapsed/)
      Expect.to_have_count!(review_card, 0)
      wait_for_comment_card(page, "Inline note")

      # First ] prefers the mounted inline card and leaves the section closed.
      Locator.click!(Page.locator(page, "#comment-nav-next"))
      Expect.to_have_class!(inline, ~r/comment-nav-highlight/)
      Expect.to_have_class!(section, ~r/collapsed/)
      Expect.not_to_have_class!(inline, ~r/comment-nav-highlight/)

      # The next stop wraps to the review thread, which is not in the DOM
      # until the section expands.
      Keyboard.press!(Page.keyboard(page), "]")
      Expect.not_to_have_class!(section, ~r/collapsed/)
      Expect.to_have_class!(review_card, ~r/comment-nav-highlight/)

      Keyboard.press!(Page.keyboard(page), "[")
      Expect.to_have_class!(inline, ~r/comment-nav-highlight/)
    end
  end
end
