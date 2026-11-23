defmodule CritWeb.E2E.CommentsTest do
  use CritWeb.E2ECase, async: true

  setup %{request: request} do
    review = create_review(request)
    on_exit(fn -> delete_review(request, review.delete_token) end)
    %{token: review.token, delete_token: review.delete_token}
  end

  describe "Comments — Seed & Display" do
    test "displays a seeded comment on load", %{page: page, request: request, token: token} do
      # Seed a comment via the API before loading the page
      seed_comment(request, token, body: "This needs revision", start_line: 1)

      load_review(page, token)
      wait_for_comment_card(page, "This needs revision")

      # The comment count should show 1
      Expect.to_have_text!(Page.locator(page, "#commentCountNumber"), "1")
    end

    test "displays multiple comments", %{page: page, request: request, token: token} do
      seed_comment(request, token, body: "First comment", start_line: 1)
      seed_comment(request, token, body: "Second comment", start_line: 3)

      load_review(page, token)
      wait_for_comment_card(page, "First comment")
      wait_for_comment_card(page, "Second comment")

      Expect.to_have_text!(Page.locator(page, "#commentCountNumber"), "2")
    end
  end

  describe "Comments — Add via UI" do
    test "adds a comment by clicking the gutter and submitting", %{page: page, token: token} do
      load_review(page, token)

      # Click on the comment gutter of the first line to start selection,
      # then mouseup triggers comment form
      first_gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(first_gutter)

      # The comment form should appear
      comment_form = Page.locator(page, ".comment-form")
      Expect.to_be_visible!(comment_form, timeout: 5_000)

      # Type into the textarea
      textarea = Locator.locator(comment_form, "textarea")
      Locator.fill!(textarea, "New comment from E2E test")

      # Click Comment
      Locator.click!(Locator.locator(comment_form, ~s[button:has-text("Comment")]))

      # The comment card should appear
      wait_for_comment_card(page, "New comment from E2E test")

      # Comment count should be 1
      Expect.to_have_text!(Page.locator(page, "#commentCountNumber"), "1")
    end

    test "adds a comment with Ctrl+Enter", %{page: page, token: token} do
      load_review(page, token)

      first_gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(first_gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, "Ctrl+Enter comment")

      # Submit with Ctrl+Enter
      Locator.press!(textarea, "Control+Enter")

      wait_for_comment_card(page, "Ctrl+Enter comment")
    end

    test "a newly opened comment form gets the soft form flash, not the ref-jump flash", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      # Record every flash class put on a comment form; the class is removed
      # on animationend, so a MutationObserver catches it whatever the timing.
      Page.evaluate!(page, """
      () => {
        const seen = [];
        window.__formFlashes = seen;
        new MutationObserver(records => {
          for (const r of records) {
            const el = r.target;
            if (!el.classList || !el.classList.contains("comment-form")) continue;
            for (const cls of ["comment-form-flash", "comment-ref-flash"]) {
              if (el.classList.contains(cls) && !seen.includes(cls)) seen.push(cls);
            }
          }
        }).observe(document.body, { subtree: true, attributes: true, attributeFilter: ["class"] });
      }
      """)

      Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))
      Expect.to_be_visible!(Page.locator(page, ".comment-form"), timeout: 5_000)

      flashes = fn -> Page.evaluate!(page, "() => window.__formFlashes") end
      Expect.poll!(flashes, &assert("comment-form-flash" in &1))
      refute "comment-ref-flash" in flashes.()
    end

    test "opening a new comment form closes existing empty form", %{page: page, token: token} do
      load_review(page, token)

      # Open form on first line (leave empty)
      Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))
      Expect.to_be_visible!(Page.locator(page, ".comment-form"), timeout: 5_000)

      # Open form on a different line without filling first
      Locator.click!(Locator.nth(Page.locator(page, ".line-gutter"), 2))

      # Only one form should remain (the new one); the empty first form was closed
      Expect.to_have_count!(Page.locator(page, ".comment-form"), 1)
    end

    test "opening a new comment form keeps existing form with text", %{page: page, token: token} do
      load_review(page, token)

      Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))
      first_textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(first_textarea, timeout: 5_000)
      Locator.fill!(first_textarea, "draft text")

      # Open form on a different line
      Locator.click!(Locator.nth(Page.locator(page, ".line-gutter"), 2))

      # Both forms should remain; first retains text
      Expect.to_have_count!(Page.locator(page, ".comment-form"), 2)

      Expect.to_have_value!(
        Locator.first(Page.locator(page, ".comment-form textarea")),
        "draft text"
      )
    end

    test "Escape on empty comment form closes silently", %{page: page, token: token} do
      load_review(page, token)

      Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))
      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)

      # No content -> no confirm dialog, form just closes
      Locator.press!(textarea, "Escape")

      Expect.not_to_be_visible!(Page.locator(page, ".comment-form"))
      assert Locator.count!(Page.locator(page, ".comment-card")) == 0
    end

    test "Escape on non-empty comment form prompts confirm; OK discards", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))
      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, "Detailed draft we don't want to lose by accident")

      # Accept the confirm dialog -> discard
      Page.once(page, :dialog, fn dialog ->
        assert Dialog.type(dialog) == "confirm"
        assert Dialog.message(dialog) =~ ~r/discard/i
        Dialog.accept!(dialog)
      end)

      Locator.press!(textarea, "Escape")

      Expect.not_to_be_visible!(Page.locator(page, ".comment-form"))
      assert Locator.count!(Page.locator(page, ".comment-card")) == 0
    end

    test "Escape on non-empty comment form prompts confirm; Cancel keeps draft", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))
      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      draft = "Detailed draft we don't want to lose by accident"
      Locator.fill!(textarea, draft)

      # Dismiss the confirm dialog -> keep the form with content
      Page.once(page, :dialog, fn dialog ->
        assert Dialog.type(dialog) == "confirm"
        Dialog.dismiss!(dialog)
      end)

      Locator.press!(textarea, "Escape")

      Expect.to_be_visible!(Page.locator(page, ".comment-form textarea"))
      Expect.to_have_value!(Page.locator(page, ".comment-form textarea"), draft)
    end

    test "Cancel button on non-empty comment form discards immediately (no confirm)", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))
      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, "Important draft")

      # Cancel is an explicit, labeled discard — no confirm should appear.
      test_pid = self()

      Page.on(page, :dialog, fn dialog ->
        send(test_pid, :dialog_shown)
        Dialog.dismiss!(dialog)
      end)

      page
      |> Page.locator(".comment-form")
      |> Locator.get_by_role(:button, name: "Cancel")
      |> Locator.click!()

      Expect.not_to_be_visible!(Page.locator(page, ".comment-form"))
      refute_received :dialog_shown
    end
  end

  describe "Comments — Resolve" do
    test "can resolve a comment", %{page: page, token: token} do
      load_review(page, token)

      # Add a comment via the UI so it is owned by this session
      add_comment_via_ui(page, "Resolve me")

      # Find the resolve button on the comment card
      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Resolve me")
      resolve_btn = Locator.locator(card, ".resolve-btn")
      Locator.click!(resolve_btn)

      # After resolving, the comment card should have the resolved-card class
      Expect.to_be_visible!(Page.locator(page, ".comment-card.resolved-card"), timeout: 5_000)

      # The Unresolve button should be visible on the resolved card
      Expect.to_be_visible!(Page.locator(page, ".resolve-btn--active"))
    end

    test "can unresolve a resolved comment", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Round trip me")

      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Round trip me")
      Locator.click!(Locator.locator(card, ".resolve-btn"))
      Expect.to_have_class!(card, ~r/resolved-card/, timeout: 5_000)

      # Unresolve — the card returns to its open state
      Locator.click!(Locator.locator(card, ".resolve-btn--active"))
      Expect.not_to_have_class!(card, ~r/resolved-card/, timeout: 5_000)
      Expect.to_have_count!(Page.locator(page, ".comment-card.resolved-card"), 0)
    end
  end

  describe "Comments — Delete" do
    test "can delete a comment", %{page: page, token: token} do
      load_review(page, token)

      # Add a comment via the UI so it is owned by this session
      add_comment_via_ui(page, "Delete me")

      # Click the delete button on the comment card
      card = page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Delete me")
      delete_btn = Locator.locator(card, ".delete-btn")
      Locator.click!(delete_btn)

      # The comment should disappear and the count badge clear (empty at 0)
      page
      |> Page.locator(".comment-card")
      |> Locator.filter(has_text: "Delete me")
      |> Expect.not_to_be_visible!(timeout: 5_000)

      Expect.to_have_text!(Page.locator(page, "#commentCountNumber"), "")
    end
  end
end
