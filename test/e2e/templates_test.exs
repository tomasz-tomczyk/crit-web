defmodule CritWeb.E2E.TemplatesTest do
  use CritWeb.E2ECase, async: true

  # Open a comment form on the first line gutter.
  defp open_comment_form(page) do
    Locator.click!(Locator.first(Page.locator(page, ".line-gutter")))
    Expect.to_be_visible!(Page.locator(page, ".comment-form"), timeout: 5_000)
  end

  # Fill the open comment form with `text` and save it as a template via the
  # "+ Template" dialog.
  defp save_template(page, text) do
    textarea = Page.locator(page, ".comment-form textarea")
    Locator.fill!(textarea, text)

    Locator.click!(Page.locator(page, ".comment-form-actions button", has_text: "+ Template"))

    overlay = Page.locator(page, ".save-template-overlay")
    Expect.to_be_visible!(overlay)
    Locator.click!(Locator.locator(overlay, "button", has_text: "Save"))
    Expect.to_be_hidden!(overlay)
  end

  describe "Comment Templates" do
    setup %{page: page, request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)

      # Clear localStorage templates before each test
      Page.goto!(page, "/")

      Page.evaluate!(page, """
      () => {
        localStorage.removeItem("crit-templates");
      }
      """)

      %{token: review.token, delete_token: review.delete_token}
    end

    test "no template bar visible on fresh start", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)

      bar = Page.locator(page, ".comment-template-bar")
      Expect.to_be_hidden!(bar)
    end

    test "+ Template button visible in actions row", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)

      save_btn = Page.locator(page, ".comment-form-actions button", has_text: "+ Template")
      Expect.to_be_visible!(save_btn)
    end

    test "+ Template opens dialog with textarea content", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)

      textarea = Page.locator(page, ".comment-form textarea")
      Locator.fill!(textarea, "Consider using X instead")

      Locator.click!(Page.locator(page, ".comment-form-actions button", has_text: "+ Template"))

      overlay = Page.locator(page, ".save-template-overlay")
      Expect.to_be_visible!(overlay)
      input = Locator.locator(overlay, ".save-template-input")
      Expect.to_have_value!(input, "Consider using X instead")
    end

    test "saving template makes chip appear in template bar", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)
      save_template(page, "Needs a test for this")

      bar = Page.locator(page, ".comment-template-bar")
      Expect.to_be_visible!(bar)
      chip = Locator.locator(bar, ".template-chip")
      Expect.to_have_count!(chip, 1)
      Expect.to_have_text!(Locator.locator(chip, ".template-chip-label"), "Needs a test for this")
    end

    test "clicking chip inserts text into textarea", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)
      save_template(page, "My template text")

      # Clear textarea
      textarea = Page.locator(page, ".comment-form textarea")
      Locator.fill!(textarea, "")

      # Click the chip
      chip = Locator.first(Page.locator(page, ".template-chip"))
      Locator.click!(chip)

      Expect.to_have_value!(textarea, "My template text")
    end

    test "deleting chip via x removes it and hides bar when empty", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)
      save_template(page, "Temp template")

      bar = Page.locator(page, ".comment-template-bar")
      Expect.to_be_visible!(bar)

      # Click x to delete chip
      chip = Locator.first(Locator.locator(bar, ".template-chip"))
      del = Locator.locator(chip, ".template-chip-delete")
      Expect.to_be_visible!(del)
      Locator.click!(del)

      Expect.to_be_hidden!(bar)
    end

    test "templates persist across form close and reopen", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)
      save_template(page, "Persistent template")

      # Cancel form
      Locator.click!(Page.locator(page, ".comment-form-actions button", has_text: "Cancel"))
      Expect.not_to_be_visible!(Page.locator(page, ".comment-form"))

      # Reopen form
      open_comment_form(page)

      # Template bar should still have the chip
      bar = Page.locator(page, ".comment-template-bar")
      Expect.to_be_visible!(bar)
      Expect.to_have_count!(Locator.locator(bar, ".template-chip"), 1)

      Expect.to_have_text!(
        Locator.first(Locator.locator(bar, ".template-chip-label")),
        "Persistent template"
      )
    end

    test "save dialog does nothing when textarea is empty", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)

      # Textarea is empty by default
      Locator.click!(Page.locator(page, ".comment-form-actions button", has_text: "+ Template"))

      # Dialog should not appear
      overlay = Page.locator(page, ".save-template-overlay")
      Expect.to_be_hidden!(overlay)
    end

    test "save dialog can be cancelled", %{page: page, token: token} do
      load_review(page, token)
      open_comment_form(page)

      textarea = Page.locator(page, ".comment-form textarea")
      Locator.fill!(textarea, "Cancel me")

      Locator.click!(Page.locator(page, ".comment-form-actions button", has_text: "+ Template"))

      overlay = Page.locator(page, ".save-template-overlay")
      Expect.to_be_visible!(overlay)

      Locator.click!(Locator.locator(overlay, "button", has_text: "Cancel"))
      Expect.to_be_hidden!(overlay)

      # No template bar should appear
      bar = Page.locator(page, ".comment-template-bar")
      Expect.to_be_hidden!(bar)
    end
  end
end
