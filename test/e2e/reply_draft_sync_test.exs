defmodule CritWeb.E2E.ReplyDraftSyncTest do
  use CritWeb.E2ECase, async: true

  # A reply being typed survives another reviewer's comment arriving over
  # PubSub: the draft text stays and focus and caret go back to the reply
  # textarea (crit: cli-comment.spec.ts, #1051). In a code file the new comment
  # rebuilds the file's Pierre annotations, thread cards included.

  @go Enum.join(
        [
          "package main",
          "",
          ~s(import "fmt"),
          "",
          "func main() {",
          ~s(\tfmt.Println("hello"\)),
          "}",
          ""
        ],
        "\n"
      )

  defp open_second_reviewer(browser, token) do
    context = Browser.new_context!(browser)
    page = BrowserContext.new_page!(context)
    load_review(page, token)
    %{context: context, page: page}
  end

  defp start_reply(page, comment_body) do
    card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: comment_body)
    Locator.click!(Locator.locator(card, ".reply-input"))
    reply_textarea = Locator.locator(card, ".reply-textarea")
    Expect.to_be_focused!(reply_textarea)
    Keyboard.type!(Page.keyboard(page), "draft reply")
    reply_textarea
  end

  describe "Reply drafts across comment sync" do
    test "a reply being typed in a markdown file keeps text and focus when another comment arrives",
         %{page: page, browser: browser, request: request} do
      review = create_review(request)
      delete_after(request, review)
      seed_comment(request, review.token, body: "Reviewer comment", start_line: 1)

      load_review(page, review.token)
      wait_for_comment_card(page, "Reviewer comment")
      reply_textarea = start_reply(page, "Reviewer comment")

      other = open_second_reviewer(browser, review.token)

      try do
        add_comment_via_ui(other.page, "Comment from another reviewer", line_index: 2)
      after
        BrowserContext.close!(other.context)
      end

      wait_for_comment_card(page, "Comment from another reviewer")

      Expect.to_be_focused!(reply_textarea)
      Keyboard.type!(Page.keyboard(page), " continues")
      Expect.to_have_value!(reply_textarea, "draft reply continues")
    end

    # The review conversation is rebuilt on every comment change, so this one
    # loses the draft without the fix even in a markdown review.
    test "a reply being typed on a review-level comment keeps text and focus when another comment arrives",
         %{page: page, browser: browser, request: request} do
      review = create_review(request)
      delete_after(request, review)
      seed_comment(request, review.token, body: "Review-level comment", scope: "review")

      load_review(page, review.token)

      page
      |> Page.locator("#reviewConversation .comment-card")
      |> Locator.filter(has_text: "Review-level comment")
      |> Expect.to_be_visible!(timeout: 10_000)

      reply_textarea = start_reply(page, "Review-level comment")

      other = open_second_reviewer(browser, review.token)

      try do
        add_comment_via_ui(other.page, "Comment from another reviewer", line_index: 2)
      after
        BrowserContext.close!(other.context)
      end

      wait_for_comment_card(page, "Comment from another reviewer")

      Expect.to_be_focused!(reply_textarea)
      Keyboard.type!(Page.keyboard(page), " continues")
      Expect.to_have_value!(reply_textarea, "draft reply continues")
    end

    test "a reply being typed in a code file keeps text and focus when another comment arrives",
         %{page: page, browser: browser, request: request} do
      review =
        create_review(request,
          files: [
            %{path: "main.go", content: @go},
            %{path: "notes.md", content: "# Notes\n\nSome prose.\n"}
          ]
        )

      delete_after(request, review)

      seed_comment(request, review.token,
        body: "Reviewer comment",
        file: "main.go",
        start_line: 1
      )

      load_review(page, review.token)

      thread =
        page
        |> code_file("main.go")
        |> Locator.locator(".comment-card")
        |> Locator.filter(has_text: "Reviewer comment")

      Expect.to_be_visible!(thread, timeout: 10_000)
      reply_textarea = start_reply(page, "Reviewer comment")
      # Caret mid-draft, so the restore has to keep the selection, not just focus.
      Locator.evaluate!(reply_textarea, "el => el.setSelectionRange(5, 5)")

      other = open_second_reviewer(browser, review.token)

      try do
        open_code_line_comment(other.page, "main.go", 5)
        form = Page.locator(other.page, ".comment-form textarea")
        Locator.fill!(form, "Comment from another reviewer")
        Locator.press!(form, "Control+Enter")
        wait_for_comment_card(other.page, "Comment from another reviewer")
      after
        BrowserContext.close!(other.context)
      end

      page
      |> code_file("main.go")
      |> Locator.locator(".comment-card")
      |> Locator.filter(has_text: "Comment from another reviewer")
      |> Expect.to_be_visible!(timeout: 10_000)

      Expect.to_be_focused!(reply_textarea)
      Expect.to_have_value!(reply_textarea, "draft reply")
      Keyboard.type!(Page.keyboard(page), "X")
      Expect.to_have_value!(reply_textarea, "draftX reply")
    end
  end

  # The spec's afterEach deletes the review the test created (module-level
  # `deleteToken`); here each test registers it.
  defp delete_after(request, review) do
    on_exit(fn -> delete_review(request, review.delete_token) end)
  end
end
