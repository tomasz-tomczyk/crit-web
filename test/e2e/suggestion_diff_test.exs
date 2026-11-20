defmodule CritWeb.E2E.SuggestionDiffTest do
  use CritWeb.E2ECase, async: true

  describe "Suggestion Diff Rendering" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{
              path: "example.md",
              content:
                "# Hello World\n\nThis is the first line\nThis is the second line\nThis is the third line\n"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "renders suggestion block as inline diff", %{page: page, token: token} do
      load_review(page, token)

      # Open comment form on a line
      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)

      Locator.fill!(
        textarea,
        "Here is my suggestion:\n\n```suggestion\nreplacement line\n```\n\nPlease consider this change."
      )

      Locator.click!(Page.locator(page, ~s[.comment-form button:has-text("Comment")]))

      # Wait for comment to render
      wait_for_comment_card(page, "Here is my suggestion")

      # Verify the suggestion diff is rendered
      suggestion_diff = Page.locator(page, ".suggestion-diff")
      Expect.to_be_visible!(suggestion_diff, timeout: 5_000)

      # Should have a "Suggested change" header
      Expect.to_have_text!(
        Locator.locator(suggestion_diff, ".suggestion-header"),
        "Suggested change"
      )

      # Should have deletion line (original) and addition line (suggestion)
      Expect.to_have_count!(Locator.locator(suggestion_diff, ".suggestion-line-del"), 1)
      Expect.to_have_count!(Locator.locator(suggestion_diff, ".suggestion-line-add"), 1)

      # The addition line should contain our replacement text
      Expect.to_have_text!(
        Locator.locator(suggestion_diff, ".suggestion-line-add .suggestion-line-content"),
        "replacement line"
      )
    end

    test "regular code blocks do not render as suggestion diff", %{page: page, token: token} do
      load_review(page, token)

      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, ~s|```javascript\nconsole.log("hello")\n```|)

      Locator.click!(Page.locator(page, ~s[.comment-form button:has-text("Comment")]))

      # Wait for comment to render
      Expect.to_be_visible!(Locator.first(Page.locator(page, ".comment-card")), timeout: 5_000)

      # Should NOT render as suggestion diff
      Expect.to_have_count!(Page.locator(page, ".suggestion-diff"), 0)

      # Should render as a normal code block
      code_block = Page.locator(page, ".comment-body pre code")
      Expect.to_be_visible!(code_block)
    end

    test "empty suggestion renders as deletion-only", %{page: page, token: token} do
      load_review(page, token)

      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, "```suggestion\n```")

      Locator.click!(Page.locator(page, ~s[.comment-form button:has-text("Comment")]))

      Expect.to_be_visible!(Locator.first(Page.locator(page, ".comment-card")), timeout: 5_000)

      # Should render as suggestion diff with deletion but no addition
      suggestion_diff = Page.locator(page, ".suggestion-diff")
      Expect.to_be_visible!(suggestion_diff, timeout: 5_000)
      Expect.to_have_count!(Locator.locator(suggestion_diff, ".suggestion-line-del"), 1)
      Expect.to_have_count!(Locator.locator(suggestion_diff, ".suggestion-line-add"), 0)
    end

    test "suggest button inserts suggestion template into textarea", %{page: page, token: token} do
      load_review(page, token)

      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)

      # Click the Suggest button
      suggest_btn = Page.locator(page, ~s[.comment-form button:has-text("Suggest")])
      Expect.to_be_visible!(suggest_btn)
      Locator.click!(suggest_btn)

      # Textarea should now contain a suggestion block
      value = Locator.input_value!(textarea)
      assert value =~ "```suggestion"
      assert value =~ "```"
    end
  end
end
