defmodule CritWeb.E2E.KeyboardTest do
  use CritWeb.E2ECase, async: true

  defp press(page, key), do: Keyboard.press!(Page.keyboard(page), key)

  describe "Keyboard Shortcuts" do
    setup %{request: request} do
      # Use a list so each item is a separate line-block for keyboard navigation
      review =
        create_review(request,
          files: [
            %{
              path: "example.md",
              content:
                "# Heading\n\n- Item one\n- Item two\n- Item three\n- Item four\n- Item five\n"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "j focuses the first line block", %{page: page, token: token} do
      load_review(page, token)

      # No element should be focused initially
      Expect.to_have_count!(Page.locator(page, ".line-block.focused"), 0)

      press(page, "j")

      focused = Page.locator(page, ".line-block.focused")
      Expect.to_have_count!(focused, 1)
    end

    test "j/k navigates between blocks", %{page: page, token: token} do
      load_review(page, token)

      # Press j twice to focus the second block
      press(page, "j")
      press(page, "j")

      all_blocks = Page.locator(page, ".line-block")
      second_block = Locator.nth(all_blocks, 1)
      Expect.to_have_class!(second_block, ~r/focused/)

      # Press k to go back to first block
      press(page, "k")
      first_block = Locator.nth(all_blocks, 0)
      Expect.to_have_class!(first_block, ~r/focused/)
    end

    test "Escape clears focus from a focused block", %{page: page, token: token} do
      load_review(page, token)

      # Focus a block
      press(page, "j")
      Expect.to_have_count!(Page.locator(page, ".line-block.focused"), 1, timeout: 3_000)

      # Press Escape to clear focus
      press(page, "Escape")
      Expect.to_have_count!(Page.locator(page, ".line-block.focused"), 0)
    end

    test "? opens settings panel with shortcuts tab", %{page: page, token: token} do
      load_review(page, token)

      press(page, "?")

      overlay = Page.locator(page, "#settingsOverlay.active")
      Expect.to_be_visible!(overlay, timeout: 5_000)

      # Should show shortcuts content
      shortcuts_pane = Page.locator(page, "#shortcutsPane")
      Expect.to_be_visible!(shortcuts_pane)
    end

    test "? toggles settings panel", %{page: page, token: token} do
      load_review(page, token)

      # Open
      press(page, "?")
      overlay = Page.locator(page, "#settingsOverlay.active")
      Expect.to_be_visible!(overlay, timeout: 5_000)

      # Close
      press(page, "?")
      Expect.not_to_be_visible!(overlay)
    end

    test "custom shortcut applies immediately, persists, and resets", %{page: page, token: token} do
      load_review(page, token)
      press(page, "?")
      Locator.click!(Page.locator(page, ~s([data-shortcut-id="next_block"])))
      press(page, "ArrowDown")

      Expect.to_contain_text!(
        Page.locator(page, ~s([data-shortcut-id="next_block"])),
        "ArrowDown"
      )

      Locator.click!(Page.locator(page, "#settingsOverlay"), position: %{x: 10, y: 10})
      press(page, "j")
      Expect.to_have_count!(Page.locator(page, ".line-block.focused"), 0)
      press(page, "ArrowDown")
      Expect.to_have_count!(Page.locator(page, ".line-block.focused"), 1)

      load_review(page, token)
      Locator.click!(Page.locator(page, "#settingsToggle"))
      Locator.click!(Page.locator(page, ~s([data-tab="shortcuts"])))

      Expect.to_contain_text!(
        Page.locator(page, ~s([data-shortcut-id="next_block"])),
        "ArrowDown"
      )

      Locator.click!(Page.locator(page, ".shortcut-reset-all"))
      Locator.click!(Page.locator(page, "#settingsOverlay"), position: %{x: 10, y: 10})
      press(page, "j")
      Expect.to_have_count!(Page.locator(page, ".line-block.focused"), 1)
    end

    test "shortcut conflicts use a toast without changing row height", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      press(page, "?")

      Expect.poll!(
        fn ->
          page
          |> Page.locator(".settings-dialog")
          |> Locator.evaluate!("element => getComputedStyle(element).transform")
        end,
        &assert(&1 == "none")
      )

      previous = Page.locator(page, ~s([data-shortcut-id="previous_block"]))
      row = Locator.locator(previous, "xpath=ancestor::tr")
      before = Locator.evaluate!(row, "element => element.getBoundingClientRect().height")
      Locator.click!(previous)
      editing = Locator.evaluate!(row, "element => element.getBoundingClientRect().height")
      assert editing == before
      press(page, "j")

      Expect.to_contain_text!(
        Page.locator(page, ".mini-toast--error"),
        "already assigned to “Next block”"
      )
    end

    test "capture can move to another shortcut or Reset all on the first click", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      press(page, "?")
      next = Page.locator(page, ~s([data-shortcut-id="next_block"]))
      previous = Page.locator(page, ~s([data-shortcut-id="previous_block"]))

      Locator.click!(next)
      Locator.click!(previous)
      Expect.to_contain_text!(next, "j")
      Expect.to_contain_text!(previous, "Press keys…")

      Locator.click!(Page.locator(page, ".shortcut-reset-all"))
      Expect.to_contain_text!(previous, "k")
      Expect.to_have_count!(Page.locator(page, ".shortcut-binding.is-capturing"), 0)
    end

    test "modified question-mark chords are reserved", %{page: page, token: token} do
      load_review(page, token)
      press(page, "?")
      next = Page.locator(page, ~s([data-shortcut-id="next_block"]))
      Locator.click!(next)
      press(page, "Control+Shift+/")

      Expect.to_contain_text!(Page.locator(page, ".mini-toast--error"), "is reserved by Crit Web")
      Expect.to_contain_text!(next, "j")
    end

    test "custom Space shortcut does not hijack a focused button", %{page: page, token: token} do
      load_review(page, token)
      press(page, "?")
      Locator.click!(Page.locator(page, ~s([data-shortcut-id="next_block"])))
      press(page, "Space")
      Locator.click!(Page.locator(page, "#settingsOverlay"), position: %{x: 10, y: 10})

      Locator.focus!(Page.locator(page, "#settingsToggle"))
      press(page, "Space")
      Expect.to_be_visible!(Page.locator(page, "#settingsOverlay.active"))
      Expect.to_have_count!(Page.locator(page, ".line-block.focused"), 0)
    end

    test "fixed settings shortcuts work while a settings control is focused", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      press(page, "?")
      Locator.focus!(Page.locator(page, ".shortcut-reset-all"))
      press(page, "Escape")
      Expect.to_have_count!(Page.locator(page, "#settingsOverlay.active"), 0)

      Locator.click!(Page.locator(page, "#settingsToggle"))
      Locator.focus!(Page.locator(page, ~s(.settings-tab[data-tab="shortcuts"])))
      press(page, "?")
      Expect.to_have_count!(Page.locator(page, "#settingsOverlay.active"), 0)
    end

    test "malformed persisted shortcut values fall back without breaking settings", %{
      page: page,
      token: token
    } do
      owner = self()
      Page.on(page, :page_error, fn error -> send(owner, {:page_error, error}) end)

      # A string without an argument is the script's source, not a function to
      # call (an arrow function here would only be defined): the statement form.
      Page.add_init_script!(
        page,
        ~s[localStorage.setItem("crit-shortcuts", JSON.stringify({ next_block: 7 }))]
      )

      load_review(page, token)
      press(page, "?")

      Expect.to_contain_text!(Page.locator(page, ~s([data-shortcut-id="next_block"])), "j")
      refute_received {:page_error, _}
    end

    # [ / ] comment navigation is covered (with highlight assertions) in
    # comment-navigation.spec.ts; Shift+C panel toggle in comments-panel.spec.ts.

    test "keyboard shortcuts do not fire when typing in textarea", %{page: page, token: token} do
      load_review(page, token)

      # Open a comment form
      gutter = Locator.first(Page.locator(page, ".line-gutter"))
      Locator.click!(gutter)

      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_visible!(textarea, timeout: 5_000)

      # Type navigation shortcuts in the textarea — they must not leave the editor.
      Locator.type!(textarea, "jn")
      Expect.to_have_value!(textarea, "jn")

      # No block should get focused from the shortcut.
      Expect.to_have_count!(Page.locator(page, ".line-block.focused"), 0)
    end
  end
end
