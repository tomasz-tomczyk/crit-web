defmodule CritWeb.E2E.EditingTest do
  use CritWeb.E2ECase, async: true

  describe "Comment Editing" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "edit button opens editor with existing text", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Original comment text")

      # Click Edit button on the comment card
      card =
        page
        |> Page.locator(".comment-card")
        |> Locator.filter(has_text: "Original comment text")

      edit_btn = Locator.locator(card, ~s(button[title="Edit"]))
      Locator.click!(edit_btn)

      # Editor should open with existing text
      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Expect.to_have_value!(textarea, "Original comment text")
    end

    test "editing a comment saves updated text", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Before edit")

      # Click Edit
      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Before edit")
      Locator.click!(Locator.locator(card, ~s(button[title="Edit"])))

      # Clear and type new text
      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.clear!(textarea)
      Locator.fill!(textarea, "After edit")

      # Click Update button
      Locator.click!(Page.locator(page, ".comment-form .btn-primary"))

      # The comment should show updated text
      wait_for_comment_card(page, "After edit")

      # Original text should be gone
      Expect.not_to_be_visible!(
        Locator.filter(Page.locator(page, ".comment-card"), has_text: "Before edit")
      )
    end

    test "edited comment persists after page reload", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Will be edited")

      # Edit the comment
      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Will be edited")
      Locator.click!(Locator.locator(card, ~s(button[title="Edit"])))

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.clear!(textarea)
      Locator.fill!(textarea, "Persisted edit")
      Locator.click!(Page.locator(page, ".comment-form .btn-primary"))

      wait_for_comment_card(page, "Persisted edit")

      # Reload and verify persistence
      load_review(page, token)
      wait_for_comment_card(page, "Persisted edit")
    end

    test "cancelling edit preserves original text", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Do not change me")

      # Click Edit
      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Do not change me")
      Locator.click!(Locator.locator(card, ~s(button[title="Edit"])))

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.clear!(textarea)
      Locator.fill!(textarea, "This should be discarded")

      # Click Cancel
      page
      |> Page.locator(".comment-form .btn-sm:not(.btn-primary)")
      |> Locator.filter(has_text: "Cancel")
      |> Locator.click!()

      # Original text should still be visible
      wait_for_comment_card(page, "Do not change me")
    end

    test "Ctrl+Enter submits edit", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Edit with shortcut")

      card =
        page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Edit with shortcut")

      Locator.click!(Locator.locator(card, ~s(button[title="Edit"])))

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.clear!(textarea)
      Locator.fill!(textarea, "Updated via Ctrl+Enter")
      Locator.press!(textarea, "Control+Enter")

      wait_for_comment_card(page, "Updated via Ctrl+Enter")
    end

    test "edit form header shows 'Editing comment' text", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Check header")

      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Check header")
      Locator.click!(Locator.locator(card, ~s(button[title="Edit"])))

      header = Page.locator(page, ".comment-form-header")
      Expect.to_be_visible!(header, timeout: 5_000)
      Expect.to_contain_text!(header, "Editing comment")
    end
  end
end
