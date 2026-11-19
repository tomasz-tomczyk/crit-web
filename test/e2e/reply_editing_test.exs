defmodule CritWeb.E2E.ReplyEditingTest do
  use CritWeb.E2ECase, async: true

  # Add a reply to the first comment card via the UI.
  defp add_reply_via_ui(page, comment_body, reply_body) do
    card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: comment_body)
    Locator.click!(Locator.locator(card, ".reply-input"))

    reply_textarea = Locator.locator(card, ".reply-textarea")
    Expect.to_be_visible!(reply_textarea, timeout: 5_000)
    Locator.fill!(reply_textarea, reply_body)

    Locator.click!(Locator.locator(card, ".reply-form-buttons .btn-primary"))

    # Wait for the reply to appear
    card
    |> Locator.locator(".reply-body")
    |> Locator.filter(has_text: reply_body)
    |> Expect.to_be_visible!(timeout: 5_000)
  end

  defp card(page, text),
    do: page |> Page.locator(".comment-card") |> Locator.filter(has_text: text)

  describe "Reply Editing" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "edit button on reply opens editor with existing text", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Parent comment")
      add_reply_via_ui(page, "Parent comment", "Reply to edit")

      card = card(page, "Parent comment")
      reply = Locator.locator(card, ".comment-reply")

      # Click Edit button on the reply
      Locator.click!(Locator.locator(reply, ~s(button[title="Edit"])))

      # The editReply function replaces .reply-body with a textarea inside .comment-reply
      textarea = Locator.locator(reply, "textarea.comment-textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Expect.to_have_value!(textarea, "Reply to edit")
    end

    test "editing a reply saves updated text", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Parent for edit test")
      add_reply_via_ui(page, "Parent for edit test", "Original reply")

      card = card(page, "Parent for edit test")
      reply = Locator.locator(card, ".comment-reply")

      # Click Edit
      Locator.click!(Locator.locator(reply, ~s(button[title="Edit"])))

      textarea = Locator.locator(reply, "textarea.comment-textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.clear!(textarea)
      Locator.fill!(textarea, "Updated reply text")

      # Click Save
      Locator.click!(Locator.locator(reply, ".reply-edit-actions .btn-primary"))

      # Reload the page to confirm persistence (the reply_updated event saves to DB)
      load_review(page, token)
      wait_for_comment_card(page, "Parent for edit test")

      # The reply should show updated text after reload
      reloaded_card = card(page, "Parent for edit test")

      reloaded_card
      |> Locator.locator(".reply-body")
      |> Locator.filter(has_text: "Updated reply text")
      |> Expect.to_be_visible!(timeout: 5_000)
    end

    test "cancelling reply edit preserves original text", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Parent for cancel test")
      add_reply_via_ui(page, "Parent for cancel test", "Keep this reply")

      card = card(page, "Parent for cancel test")
      reply = Locator.locator(card, ".comment-reply")

      # Click Edit
      Locator.click!(Locator.locator(reply, ~s(button[title="Edit"])))

      textarea = Locator.locator(reply, "textarea.comment-textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.clear!(textarea)
      Locator.fill!(textarea, "This should be discarded")

      # Click Cancel (the non-primary button in reply-edit-actions)
      Locator.click!(Locator.locator(reply, ".reply-edit-actions .btn:not(.btn-primary)"))

      # Original text should still be visible after re-render
      card
      |> Locator.locator(".reply-body")
      |> Locator.filter(has_text: "Keep this reply")
      |> Expect.to_be_visible!(timeout: 5_000)
    end

    test "Ctrl+Enter submits reply edit", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Parent for Ctrl+Enter")
      add_reply_via_ui(page, "Parent for Ctrl+Enter", "Edit me with shortcut")

      card = card(page, "Parent for Ctrl+Enter")
      reply = Locator.locator(card, ".comment-reply")

      Locator.click!(Locator.locator(reply, ~s(button[title="Edit"])))

      textarea = Locator.locator(reply, "textarea.comment-textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.clear!(textarea)
      Locator.fill!(textarea, "Shortcut edited reply")
      Locator.press!(textarea, "Control+Enter")

      # Reload to confirm persistence
      load_review(page, token)
      wait_for_comment_card(page, "Parent for Ctrl+Enter")

      reloaded_card = card(page, "Parent for Ctrl+Enter")

      reloaded_card
      |> Locator.locator(".reply-body")
      |> Locator.filter(has_text: "Shortcut edited reply")
      |> Expect.to_be_visible!(timeout: 5_000)
    end
  end

  describe "Reply Deletion" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "delete button removes a reply", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Parent with reply to delete")
      add_reply_via_ui(page, "Parent with reply to delete", "Delete this reply")

      card = card(page, "Parent with reply to delete")

      reply =
        card |> Locator.locator(".comment-reply") |> Locator.filter(has_text: "Delete this reply")

      # Click the delete button on the reply
      Locator.click!(Locator.locator(reply, ".delete-btn"))

      # The reply should disappear
      card
      |> Locator.locator(".comment-reply")
      |> Locator.filter(has_text: "Delete this reply")
      |> Expect.not_to_be_visible!(timeout: 5_000)

      # Parent comment should still be visible
      wait_for_comment_card(page, "Parent with reply to delete")
    end

    test "deleting one reply preserves other replies", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Multi reply parent")
      add_reply_via_ui(page, "Multi reply parent", "Reply one")
      add_reply_via_ui(page, "Multi reply parent", "Reply two")

      card = card(page, "Multi reply parent")

      # Verify both replies exist
      Expect.to_have_count!(Locator.locator(card, ".comment-reply"), 2)

      # Delete the first reply
      first_reply =
        card |> Locator.locator(".comment-reply") |> Locator.filter(has_text: "Reply one")

      Locator.click!(Locator.locator(first_reply, ".delete-btn"))

      # Only second reply should remain
      card
      |> Locator.locator(".comment-reply")
      |> Locator.filter(has_text: "Reply one")
      |> Expect.not_to_be_visible!(timeout: 5_000)

      card
      |> Locator.locator(".reply-body")
      |> Locator.filter(has_text: "Reply two")
      |> Expect.to_be_visible!()
    end
  end
end
