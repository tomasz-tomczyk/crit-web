defmodule CritWeb.E2E.FileShortcutsTest do
  use CritWeb.E2ECase, async: true

  # a (toggle viewed) and o (collapse or expand) act on the file of the last
  # j/k focus, or on the file under the mouse when the mouse moved since then
  # (crit #1049).

  @first "a-first.md"
  @second "b-second.md"

  defp section(page, path),
    do: Page.locator(page, ~s(details.file-section[data-file-path="#{path}"]))

  defp press(page, key), do: Keyboard.press!(Page.keyboard(page), key)

  describe "File shortcuts — a / o" do
    setup %{page: page, request: request} do
      review =
        create_review(request,
          files: [
            %{path: @first, content: "# First\n\n- one\n- two\n"},
            %{path: @second, content: "# Second\n\n- three\n- four\n"}
          ]
        )

      # Viewed state is kept per browser; start clean.
      Page.goto!(page, "/")

      Page.evaluate!(page, """
      () => {
        for (let i = localStorage.length - 1; i >= 0; i--) {
          const key = localStorage.key(i);
          if (key && key.startsWith("crit-viewed-")) localStorage.removeItem(key);
        }
      }
      """)

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "a marks the focused file viewed, and again unmarks it", %{page: page, token: token} do
      load_review(page, token)
      press(page, "j")
      Expect.to_have_count!(Locator.locator(section(page, @first), ".line-block.focused"), 1)

      checkbox = Locator.locator(section(page, @first), ".file-header-viewed input")
      press(page, "a")
      Expect.to_be_checked!(checkbox)
      # Viewing a file collapses it, as the checkbox does.
      Expect.not_to_have_attribute!(section(page, @first), "open", "")
      Expect.to_have_text!(Page.locator(page, "#critStatus"), "Marked #{@first} viewed")

      Expect.not_to_be_checked!(
        Locator.locator(section(page, @second), ".file-header-viewed input")
      )

      press(page, "a")
      Expect.not_to_be_checked!(checkbox)
      Expect.to_have_text!(Page.locator(page, "#critStatus"), "Unmarked #{@first} viewed")
    end

    test "o collapses and expands the focused file", %{page: page, token: token} do
      load_review(page, token)
      press(page, "j")

      press(page, "o")
      Expect.not_to_have_attribute!(section(page, @first), "open", "")
      Expect.to_have_attribute!(section(page, @second), "open", "")
      Expect.to_have_text!(Page.locator(page, "#critStatus"), "Collapsed #{@first}")

      press(page, "o")
      Expect.to_have_attribute!(section(page, @first), "open", "")
      Expect.to_have_text!(Page.locator(page, "#critStatus"), "Expanded #{@first}")
      # The focus comes back with the file.
      Expect.to_have_count!(Locator.locator(section(page, @first), ".line-block.focused"), 1)
    end

    test "the file under the mouse wins once the mouse moves after j/k",
         %{page: page, token: token} do
      load_review(page, token)
      press(page, "j")

      # The second file's header is on screen; its body may not be.
      box =
        Locator.bounding_box!(Locator.locator(section(page, @second), ".file-header .filename"))

      if !box, do: raise("second file header not on screen")
      mouse = Page.mouse(page)
      Mouse.move!(mouse, box.x + 2, box.y + box.height / 2)
      Mouse.move!(mouse, box.x + 10, box.y + box.height / 2, steps: 4)

      press(page, "o")
      Expect.not_to_have_attribute!(section(page, @second), "open", "")
      Expect.to_have_attribute!(section(page, @first), "open", "")

      # j moves the keyboard focus again: it wins over the still mouse.
      press(page, "j")
      press(page, "o")
      Expect.not_to_have_attribute!(section(page, @first), "open", "")
    end

    test "o on a file above the focus keeps j moving within the focused file",
         %{page: page, token: token} do
      load_review(page, token)
      second = section(page, @second)
      # j until the focus is on the first row of the second file.
      Enum.reduce_while(1..20, nil, fn _, _ ->
        press(page, "j")

        if Locator.count!(Locator.locator(second, ".line-block.focused")) > 0,
          do: {:halt, nil},
          else: {:cont, nil}
      end)

      focused = Locator.locator(second, ".line-block.focused")
      Expect.to_have_count!(focused, 1)
      start_line = String.to_integer(Locator.get_attribute!(focused, "data-start-line"))

      # Collapse the first file with the mouse over it.
      box =
        Locator.bounding_box!(Locator.locator(section(page, @first), ".file-header .filename"))

      if !box, do: raise("first file header not on screen")
      mouse = Page.mouse(page)
      Mouse.move!(mouse, box.x + 2, box.y + box.height / 2)
      Mouse.move!(mouse, box.x + 10, box.y + box.height / 2, steps: 4)
      press(page, "o")
      Expect.not_to_have_attribute!(section(page, @first), "open", "")

      # j goes to the next row of the second file, not a row further on.
      press(page, "j")
      Expect.to_have_count!(focused, 1)
      next_start = String.to_integer(Locator.get_attribute!(focused, "data-start-line"))

      row_starts =
        Locator.evaluate_all!(
          Locator.locator(second, ".line-block"),
          "els => els.map(el => Number(el.dataset.startLine))"
        )

      assert next_start ==
               Enum.at(row_starts, Enum.find_index(row_starts, &(&1 == start_line)) + 1)
    end

    test "does nothing with no focus and no mouse over a file", %{page: page, token: token} do
      load_review(page, token)
      press(page, "o")
      press(page, "a")
      Expect.to_have_attribute!(section(page, @first), "open", "")
      Expect.to_have_attribute!(section(page, @second), "open", "")
      Expect.to_have_count!(Page.locator(page, ".file-header-viewed input:checked"), 0)
    end

    test "tooltips and the shortcuts panel name the keys", %{page: page, token: token} do
      load_review(page, token)
      header = Locator.locator(section(page, @first), ".file-header")

      Expect.to_have_attribute!(
        Locator.locator(header, ".file-header-viewed"),
        "title",
        "Viewed (a)"
      )

      Expect.to_have_attribute!(
        Locator.locator(header, ".file-header-chevron"),
        "title",
        "Collapse or expand (o)"
      )

      press(page, "?")
      pane = Page.locator(page, "#shortcutsPane")
      Expect.to_contain_text!(pane, "Toggle viewed on focused file (or file under the mouse)")
      Expect.to_contain_text!(pane, "Collapse or expand focused file (or file under the mouse)")
    end
  end
end
