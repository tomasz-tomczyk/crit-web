defmodule CritWeb.E2E.DraftAutosaveTest do
  use CritWeb.E2ECase, async: true

  defp draft_keys(page) do
    Page.evaluate!(page, """
    () => Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
    """)
  end

  defp draft_count(page) do
    Page.evaluate!(page, """
    () =>
      Object.keys(localStorage).filter((k) => k.startsWith("crit-draft-"))
        .length
    """)
  end

  describe "Draft Autosave" do
    setup %{page: page, request: request} do
      review = create_review(request)

      # Clear any existing drafts from localStorage before each test
      Page.goto!(page, "/")

      Page.evaluate!(page, """
      () => {
        const keys = Object.keys(localStorage).filter((k) =>
          k.startsWith("crit-draft-")
        );
        keys.forEach((k) => localStorage.removeItem(k));
      }
      """)

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "typing in comment form saves draft to localStorage", %{page: page, token: token} do
      load_review(page, token)

      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, "Draft comment text")

      # Poll for debounced save to localStorage (500ms debounce + buffer)
      Expect.to_pass!(
        fn ->
          keys = draft_keys(page)
          assert length(keys) > 0
        end,
        timeout: 3_000
      )

      # Check localStorage content
      draft =
        Page.evaluate!(page, """
        () => {
          const keys = Object.keys(localStorage).filter((k) =>
            k.startsWith("crit-draft-")
          );
          if (keys.length === 0) return null;
          return JSON.parse(localStorage.getItem(keys[0]));
        }
        """)

      assert draft != :null
      assert draft["body"] == "Draft comment text"
      assert draft["savedAt"] > 0
    end

    test "draft is restored on page reload", %{page: page, token: token} do
      load_review(page, token)

      # Open comment form and type
      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, "Saved draft for reload")

      # Wait for debounced save
      Expect.to_pass!(
        fn ->
          keys = draft_keys(page)
          assert length(keys) > 0
        end,
        timeout: 3_000
      )

      # Reload the page
      load_review(page, token)

      # The comment form should be restored with the draft text
      restored_textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(restored_textarea, timeout: 5_000)
      Expect.to_have_value!(restored_textarea, "Saved draft for reload")

      # Restoring must not consume the durable copy. A second reload without an
      # input event should restore the same draft again.
      Expect.poll!(
        fn ->
          Page.evaluate!(page, """
          () => Object.keys(localStorage).filter((key) => key.startsWith("crit-draft-")).length
          """)
        end,
        &assert(&1 == 1)
      )

      load_review(page, token)

      Expect.to_have_value!(
        Page.locator(page, ".comment-form textarea"),
        "Saved draft for reload"
      )
    end

    test "submitting comment clears the draft", %{page: page, token: token} do
      load_review(page, token)

      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, "Will be submitted")

      # Wait for draft to save
      Expect.to_pass!(
        fn ->
          count = draft_count(page)
          assert count == 1
        end,
        timeout: 3_000
      )

      # Submit the comment
      Locator.click!(Page.locator(page, ~s{.comment-form button:has-text("Comment")}))
      wait_for_comment_card(page, "Will be submitted")

      # Draft should be cleared
      draft_count = draft_count(page)
      assert draft_count == 0
    end

    test "a disconnected submit keeps the draft and can be retried after reconnect", %{
      page: page,
      token: token
    } do
      test_pid = self()
      Page.on(page, :page_error, fn error -> send(test_pid, {:page_error, error}) end)

      load_review(page, token)
      Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))

      textarea = Page.locator(page, ".comment-form textarea")
      submit = Page.locator(page, ~s{.comment-form button:has-text("Comment")})
      Locator.fill!(textarea, "Keep this comment through a disconnect")

      Expect.to_pass!(
        fn ->
          count =
            Page.evaluate!(page, """
            () => Object.keys(localStorage).filter((key) => key.startsWith("crit-draft-")).length
            """)

          assert count == 1
        end,
        timeout: 3_000
      )

      Page.evaluate!(page, "() => window.liveSocket.disconnect()")

      Expect.to_have_attribute!(
        Page.locator(page, "#document-renderer"),
        "data-connection-state",
        "disconnected"
      )

      Locator.click!(submit)

      Expect.to_contain_text!(
        Locator.last(Page.locator(page, ".mini-toast")),
        "couldn't confirm whether your change was saved",
        timeout: 12_000
      )

      Expect.to_have_value!(textarea, "Keep this comment through a disconnect")
      Expect.to_be_enabled!(submit)
      refute_received {:page_error, _}

      draft_count =
        Page.evaluate!(page, """
        () => Object.keys(localStorage).filter((key) => key.startsWith("crit-draft-")).length
        """)

      assert draft_count == 1

      Page.evaluate!(page, "() => window.liveSocket.connect()")

      Expect.to_have_attribute!(
        Page.locator(page, "#document-renderer"),
        "data-connection-state",
        "connected",
        timeout: 12_000
      )

      draft_count_after_reconnect =
        Page.evaluate!(page, """
        () => Object.keys(localStorage).filter((key) => key.startsWith("crit-draft-")).length
        """)

      assert draft_count_after_reconnect == 1

      Locator.click!(submit)
      wait_for_comment_card(page, "Keep this comment through a disconnect")
      refute_received {:page_error, _}
    end

    test "cancelling comment form preserves the draft for later restoration", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)
      Locator.fill!(textarea, "Will be cancelled but saved")

      # Wait for draft to save
      Expect.to_pass!(
        fn ->
          count = draft_count(page)
          assert count == 1
        end,
        timeout: 3_000
      )

      # Cancel via Escape — non-empty draft prompts confirm; accept to discard
      Page.once(page, :dialog, fn dialog -> Dialog.accept!(dialog) end)
      Locator.press!(textarea, "Escape")
      Expect.not_to_be_visible!(Page.locator(page, ".comment-form"))

      # Draft should still exist in localStorage (cancel preserves draft for restoration)
      draft_count = draft_count(page)
      assert draft_count == 1

      # Reopen the form on the same line — draft should be restored
      Locator.click!(gutter)
      restored_textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(restored_textarea, timeout: 5_000)
      Expect.to_have_value!(restored_textarea, "Will be cancelled but saved")
    end

    test "stale drafts older than 24 hours are discarded", %{page: page, token: token} do
      # Inject a stale draft before loading the page
      Page.add_init_script!(
        page,
        """
        ((reviewToken) => {
          localStorage.setItem(
            `crit-draft-${reviewToken}-1-1`,
            JSON.stringify({
              body: "Old stale draft",
              savedAt: Date.now() - 25 * 60 * 60 * 1000, // 25 hours ago
              startLine: 1,
              endLine: 1,
              filePath: null,
            })
          );
        })(#{JSON.encode!(token)})
        """
      )

      load_review(page, token)

      # Comment form should NOT be open (stale draft discarded)
      # Give it a moment to ensure the renderer has finished restoring any drafts
      Page.wait_for_selector!(page, "#document-renderer .line-block", timeout: 15_000)

      # The stale draft should have been removed
      draft_count = draft_count(page)
      assert draft_count == 0
    end
  end
end
