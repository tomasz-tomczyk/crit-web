defmodule CritWeb.E2E.ThreadingTest do
  use CritWeb.E2ECase, async: true

  describe "Comment Threading" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "reply input is visible on a comment card", %{page: page, request: request, token: token} do
      seed_comment(request, token, body: "Please fix this", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "Please fix this")

      # The reply input should be visible on the comment card
      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Please fix this")
      reply_input = Locator.locator(card, ".reply-input")
      Expect.to_be_visible!(reply_input)
    end

    test "can expand reply form and submit a reply", %{page: page, request: request, token: token} do
      seed_comment(request, token, body: "Needs work", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "Needs work")

      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Needs work")

      # Click the reply input to expand
      Locator.click!(Locator.locator(card, ".reply-input"))

      # The reply textarea should appear
      reply_textarea = Locator.locator(card, ".reply-textarea")
      Expect.to_be_visible!(reply_textarea, timeout: 5_000)

      # Type a reply
      Locator.fill!(reply_textarea, "Done, fixed it")

      # Click the submit button
      Locator.click!(Locator.locator(card, ".reply-form-buttons .btn-primary"))

      # The reply should appear
      Expect.to_be_visible!(Locator.locator(card, ".comment-reply"), timeout: 5_000)
      Expect.to_contain_text!(Locator.locator(card, ".reply-body"), "Done, fixed it")
    end

    test "reply form collapses and clears after successful submit", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Review this", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "Review this")

      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Review this")

      Locator.click!(Locator.locator(card, ".reply-input"))
      Locator.fill!(Locator.locator(card, ".reply-textarea"), "Addressed this")
      Locator.click!(Locator.locator(card, ".reply-form-buttons .btn-primary"))

      # Reply should render
      Expect.to_have_count!(Locator.locator(card, ".comment-reply"), 1)

      # Form should collapse — textarea gone, compact input visible & empty
      Expect.to_have_count!(Locator.locator(card, ".reply-textarea"), 0)
      Expect.to_have_count!(Locator.locator(card, ".reply-form.expanded"), 0)
      Expect.to_be_visible!(Locator.locator(card, ".reply-input"))
      Expect.to_have_value!(Locator.locator(card, ".reply-input"), "")
    end

    test "Ctrl+Enter submits a new reply", %{page: page, request: request, token: token} do
      seed_comment(request, token, body: "Reply shortcut target", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "Reply shortcut target")

      card =
        page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Reply shortcut target")

      Locator.click!(Locator.locator(card, ".reply-input"))
      reply_textarea = Locator.locator(card, ".reply-textarea")
      Expect.to_be_visible!(reply_textarea, timeout: 5_000)
      Locator.fill!(reply_textarea, "Submitted with Ctrl+Enter")
      Locator.press!(reply_textarea, "Control+Enter")

      card
      |> Locator.locator(".reply-body")
      |> Locator.filter(has_text: "Submitted with Ctrl+Enter")
      |> Expect.to_be_visible!(timeout: 5_000)
    end

    test "reply form Cancel collapses without submitting", %{
      page: page,
      request: request,
      token: token
    } do
      seed_comment(request, token, body: "Check this", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "Check this")

      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Check this")

      # Expand the reply input
      Locator.click!(Locator.locator(card, ".reply-input"))
      reply_textarea = Locator.locator(card, ".reply-textarea")
      Expect.to_be_visible!(reply_textarea, timeout: 5_000)
      Locator.fill!(reply_textarea, "draft text")

      # Click Cancel
      Locator.click!(Locator.locator(card, ".reply-form-buttons .btn:not(.btn-primary)"))

      # Should collapse back, no reply added
      Expect.not_to_be_visible!(Locator.locator(card, ".reply-textarea"))
      assert Locator.count!(Locator.locator(card, ".comment-reply")) == 0
    end
  end
end
