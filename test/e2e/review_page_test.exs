defmodule CritWeb.E2E.ReviewPageTest do
  use CritWeb.E2ECase, async: true

  alias Playwright.Promise

  @table_markdown "| Link | Status |\n" <>
                    "| --- | --- |\n" <>
                    "| [x](https://example.com/a/very/very/very/long/hidden/path) | available |\n" <>
                    "| beta | waiting for review |\n" <>
                    "| gamma | ready |\n" <>
                    "| delta | review then review |\n"

  defp api_origin, do: base_url()

  describe "Review Page — Loading" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "renders the review page with document content", %{page: page, token: token} do
      load_review(page, token)

      # The meta bar should show the filename
      Expect.to_contain_text!(Page.locator(page, ".crit-review-meta"), "example.md")

      # The document should have rendered line blocks
      line_blocks = Page.locator(page, ".line-block")
      Expect.to_be_visible!(Locator.first(line_blocks))
      assert Locator.count!(line_blocks) > 0
    end

    test "renders markdown heading as rendered content", %{page: page, token: token} do
      load_review(page, token)

      # The heading "Hello World" should be rendered
      Expect.to_contain_text!(Page.locator(page, "#document-renderer h1"), "Hello World")
    end

    test "renders YAML frontmatter as highlighted YAML", %{page: page, request: request} do
      review =
        create_review(request,
          files: [%{path: "frontmatter.md", content: "---\ntitle: Hello\n---\n\n# Document\n"}]
        )

      frontmatter_token = review.token

      try do
        load_review(page, frontmatter_token)

        code =
          page
          |> Page.locator("#document-renderer code.crit-code")
          |> Locator.filter(has_text: "title: Hello")

        Expect.to_contain_text!(code, "title: Hello")
        # Shiki's YAML grammar colours the key as its own token.
        code
        |> Locator.locator(~s(span[style*="--diffs-token"]))
        |> Locator.filter(has_text: "title")
        |> Locator.first()
        |> Expect.to_be_visible!()
      after
        delete_review(request, review.delete_token)
      end
    end

    test "shows comment navigation group", %{page: page, token: token} do
      load_review(page, token)

      # The comment navigation buttons should exist in the header
      comment_count_btn = Page.locator(page, "#comment-count")
      Expect.to_be_visible!(comment_count_btn)
    end

    test "opens both prompt modes", %{page: page, token: token} do
      load_review(page, token)

      prompt_panel = Page.locator(page, "#crit-prompt-panel")
      Locator.click!(Page.get_by_role(page, :button, name: "Get prompt"))
      Expect.to_be_visible!(prompt_panel)
      Expect.to_have_text!(Locator.get_by_role(prompt_panel, :heading), "Act on comments")
      Expect.to_contain_text!(Locator.locator(prompt_panel, ".crit-prompt-text"), "crit fetch")
      Locator.click!(Locator.get_by_role(prompt_panel, :button, name: "Dismiss"))

      Locator.click!(Page.locator(page, ".crit-split-btn-caret"))
      Locator.click!(Page.get_by_role(page, :button, name: ~r/Full plan \+ comments/))
      Expect.to_be_visible!(prompt_panel)
      Expect.to_have_text!(Locator.get_by_role(prompt_panel, :heading), "Full plan + comments")

      Expect.to_contain_text!(
        Locator.locator(prompt_panel, ".crit-prompt-text"),
        "/api/export/#{token}/review"
      )
    end

    test "renders 404 page for invalid token", %{page: page} do
      response = Page.goto!(page, "/r/nonexistent-token-12345")
      assert response && Playwright.Response.status(response) == 404
      Expect.to_contain_text!(Page.get_by_role(page, :heading, level: 1), "not found")
    end
  end

  describe "Review Page — Display Name" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "can set display name", %{page: page, token: token} do
      load_review(page, token)

      # Click the name pill button to show the form
      name_btn = Page.locator(page, "#name-pill-btn")
      Expect.to_be_visible!(name_btn)
      Locator.click!(name_btn)

      # Fill in the name
      name_input = Page.locator(page, "#name-input")
      Expect.to_be_visible!(name_input)
      Locator.fill!(name_input, "Test Reviewer")

      # Submit
      Locator.click!(Page.locator(page, ".crit-name-save"))

      # Button should now show the name
      Expect.to_contain_text!(name_btn, "Test Reviewer")
    end
  end

  describe "Review Page — Rendered Tables" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{path: "table.md", content: @table_markdown},
            %{
              path: "notes.md",
              content: "# Notes\n\nA second file exercises the multi-file renderer.\n"
            }
          ],
          review_round: 1
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "uses one native auto-layout table without generated widths", %{page: page, token: token} do
      load_review(page, token)

      table = Page.locator(page, "table.native-table")
      Expect.to_have_count!(table, 1)
      Expect.to_have_count!(Locator.locator(table, "thead tr.table-row"), 1)
      Expect.to_have_count!(Locator.locator(table, "tbody tr.table-row"), 4)
      Expect.to_have_count!(Locator.locator(table, "colgroup"), 0)

      assert Locator.evaluate!(table, "element => getComputedStyle(element).tableLayout") ==
               "auto"

      assert table
             |> Locator.locator("thead th.line-content")
             |> Locator.first()
             |> Locator.evaluate!("element => getComputedStyle(element).overflowWrap") ==
               "break-word"

      # Cells carry the row's `table-row` class; Tailwind's display utility must not win (#457).
      cell_displays =
        table
        |> Locator.locator(".line-content")
        |> Locator.evaluate_all!("cells => cells.map(cell => getComputedStyle(cell).display)")

      assert length(cell_displays) == 10
      assert MapSet.new(cell_displays) == MapSet.new(["table-cell"])

      assert table
             |> Locator.locator("..")
             |> Locator.evaluate!("element => getComputedStyle(element).borderTopWidth") == "0px"
    end

    test "table-row forms cancel with both the button and Escape", %{page: page, token: token} do
      load_review(page, token)

      row = page |> Page.get_by_role(:cell, name: "beta", exact: true) |> Locator.locator("..")
      Locator.click!(Locator.locator(row, ".line-gutter"))
      Expect.to_be_visible!(Page.locator(page, ".comment-form"))
      Locator.click!(Page.get_by_role(page, :button, name: "Cancel", exact: true))
      Expect.to_have_count!(Page.locator(page, ".comment-form"), 0)

      row = page |> Page.get_by_role(:cell, name: "beta", exact: true) |> Locator.locator("..")
      Locator.click!(Locator.locator(row, ".line-gutter"))
      textarea = Page.locator(page, ".comment-form textarea")
      Expect.to_be_focused!(textarea)
      Locator.press!(textarea, "Escape")
      Expect.to_have_count!(Page.locator(page, ".comment-form"), 0)
    end

    test "selected text in a table cell is highlighted when commenting", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      cell = Page.get_by_role(page, :cell, name: "waiting for review", exact: true)
      select_phrase(cell, "review")
      Keyboard.press!(Page.keyboard(page), "c")

      Expect.to_be_focused!(Page.locator(page, ".comment-form textarea"))
      Expect.to_have_text!(Page.locator(page, "mark.quote-highlight"), "review")
      Locator.click!(Page.get_by_role(page, :button, name: "Cancel", exact: true))

      row = page |> Page.get_by_role(:cell, name: "beta", exact: true) |> Locator.locator("..")

      Locator.evaluate!(row, """
      element => {
        const cells = element.querySelectorAll(".line-content");
        const first = cells[0].firstChild;
        const second = cells[1].firstChild;
        if (!first || !second) throw new Error("Expected text in adjacent table cells");
        const range = document.createRange();
        range.setStart(first, 0);
        range.setEnd(second, 7);
        const selection = window.getSelection();
        selection?.removeAllRanges();
        selection?.addRange(range);
      }
      """)

      Keyboard.press!(Page.keyboard(page), "c")
      Expect.to_have_count!(Page.locator(page, "mark.quote-highlight"), 2)
      Expect.to_have_text!(Locator.nth(Page.locator(page, "mark.quote-highlight"), 0), "beta")
      Expect.to_have_text!(Locator.nth(Page.locator(page, "mark.quote-highlight"), 1), "waiting")
    end

    test "keeps the selected occurrence of a duplicate phrase after submission", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      cell = Page.get_by_role(page, :cell, name: "review then review", exact: true)
      select_phrase(cell, "review", 1)
      Keyboard.press!(Page.keyboard(page), "c")

      textarea = Page.locator(page, ".comment-form textarea")
      Locator.fill!(textarea, "Second occurrence")
      Locator.press!(textarea, "Control+Enter")
      Expect.to_be_visible!(Page.locator(page, ".comment-card", has_text: "Second occurrence"))
      Expect.to_have_count!(Locator.locator(cell, "mark.quote-highlight"), 1)

      assert Locator.evaluate!(cell, "element => element.innerHTML") =~
               ~r/review then\s*<mark[^>]*>review<\/mark>/
    end

    test "keeps fallback table columns aligned in rendered round diffs", %{
      page: page,
      request: request,
      token: token,
      delete_token: delete_token
    } do
      updated_table =
        String.replace(
          @table_markdown,
          "| beta | waiting for review |",
          "| beta | waiting for a substantially longer second review |",
          global: false
        )

      update = fn content ->
        response =
          APIRequestContext.put!(request, "#{api_origin()}/api/reviews/#{token}",
            data: %{
              delete_token: delete_token,
              files: [
                %{path: "table.md", content: content},
                %{
                  path: "notes.md",
                  content: "# Notes\n\nA second file exercises the multi-file renderer.\n"
                }
              ],
              comments: []
            }
          )

        assert APIResponse.ok(response)
      end

      update.(updated_table)

      update.(
        String.replace(updated_table, "| gamma | ready |", "| gamma | ready now |", global: false)
      )

      load_review(page, token)
      section = page |> Page.locator(".file-section") |> Locator.filter(has_text: "table.md")
      Locator.click!(Page.locator(page, "button.crit-round-diff-btn"))
      diff = Locator.locator(section, ".diff-view")
      Expect.to_be_visible!(diff)
      tables = Locator.locator(diff, "table.split-table")
      Expect.to_be_visible!(Locator.first(tables))
      Expect.to_be_attached!(Locator.first(Locator.locator(tables, "colgroup")))

      side_width_sets =
        Locator.evaluate!(diff, """
        element => {
          const cells = Array.from(element.querySelectorAll(":scope > .diff-view-cell"));
          return [0, 1].map(side => Array.from(new Set(cells
            .filter((_, index) => index % 2 === side)
            .map(cell => Array.from(cell.querySelectorAll("table.split-table col"))
              .map(col => col.style.width).join(","))
            .filter(Boolean))));
        }
        """)

      assert length(Enum.at(side_width_sets, 0)) == 1
      assert length(Enum.at(side_width_sets, 1)) == 1

      assert tables
             |> Locator.first()
             |> Locator.evaluate!("table => getComputedStyle(table).marginTop") == "0px"
    end

    test "n and Shift+N navigate and flash rendered table diff changes", %{
      page: page,
      request: request,
      token: token,
      delete_token: delete_token
    } do
      update = fn content ->
        response =
          APIRequestContext.put!(request, "#{api_origin()}/api/reviews/#{token}",
            data: %{
              delete_token: delete_token,
              files: [
                %{path: "table.md", content: content},
                %{
                  path: "notes.md",
                  content: "# Notes\n\nA second file exercises the multi-file renderer.\n"
                }
              ],
              comments: []
            }
          )

        assert APIResponse.ok(response)
      end

      update.(
        String.replace(
          @table_markdown,
          "| beta | waiting for review |",
          "| beta | changed once |",
          global: false
        )
      )

      update.(
        @table_markdown
        |> String.replace("| beta | waiting for review |", "| beta | changed twice |",
          global: false
        )
        |> String.replace("| gamma | ready |", "| gamma | changed separately |", global: false)
      )

      load_review(page, token)

      table_section =
        page |> Page.locator(".file-section") |> Locator.filter(has_text: "table.md")

      Locator.click!(Page.locator(page, "button.crit-round-diff-btn"))
      Expect.to_be_visible!(Locator.locator(table_section, ".diff-view"))

      Keyboard.press!(Page.keyboard(page), "n")
      first_target = Page.locator(page, ".change-flash")
      Expect.to_have_count!(first_target, 1)
      first_text = Locator.text_content!(first_target)

      Keyboard.press!(Page.keyboard(page), "Shift+N")
      previous_target = Page.locator(page, ".change-flash")
      Expect.to_have_count!(previous_target, 1)
      refute Locator.text_content!(previous_target) == first_text
    end

    test "drag highlights every selected table row with one endpoint utility and no bracket", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      first_row = page |> Page.get_by_role(:cell, name: "x", exact: true) |> Locator.locator("..")

      last_row =
        page |> Page.get_by_role(:cell, name: "gamma", exact: true) |> Locator.locator("..")

      first = Locator.locator(first_row, ".line-gutter")
      last = Locator.locator(last_row, ".line-gutter")
      # Boxes must be read atomically after both gutters are visible + stable:
      # separate reads across a layout shift flake with null boxes.
      Expect.to_be_visible!(first, timeout: 10_000)
      Expect.to_be_visible!(last, timeout: 10_000)
      Locator.scroll_into_view_if_needed!(first)
      Locator.scroll_into_view_if_needed!(last)
      # JS reassigns `let` boxes inside the toPass callback; return them instead.
      {first_box, last_box} =
        Expect.to_pass!(
          fn ->
            first_box = Locator.bounding_box!(first)
            last_box = Locator.bounding_box!(last)
            refute is_nil(first_box)
            refute is_nil(last_box)
            {first_box, last_box}
          end,
          timeout: 15_000
        )

      refute is_nil(first_box)
      refute is_nil(last_box)

      mouse = Page.mouse(page)
      Mouse.move!(mouse, first_box.x + first_box.width / 2, first_box.y + 10)
      Mouse.down!(mouse)
      Mouse.move!(mouse, last_box.x + last_box.width / 2, last_box.y + 10, steps: 5)

      selected = Page.locator(page, ".native-table .line-block.selected")
      Expect.to_have_count!(selected, 3)
      Expect.to_have_count!(Page.locator(page, ".native-table .line-block.drag-endpoint"), 1)
      Expect.to_have_class!(last_row, ~r/drag-endpoint/)
      Expect.to_be_visible!(Locator.first(Locator.locator(last_row, ".line-add")))
      Expect.to_be_hidden!(Locator.first(Locator.locator(first_row, ".line-add")))
      last_gutter = Locator.locator(last_row, ".line-comment-gutter")

      assert Locator.evaluate!(last_gutter, ~s|el => getComputedStyle(el, "::after").content|) ==
               "none"

      Mouse.up!(mouse)
      Expect.to_be_visible!(Page.locator(page, ".comment-form"))
    end

    test "row stripes stay stable when an annotation is inserted", %{page: page, token: token} do
      load_review(page, token)

      even_row =
        page |> Page.get_by_role(:cell, name: "beta", exact: true) |> Locator.locator("..")

      odd_row =
        page |> Page.get_by_role(:cell, name: "gamma", exact: true) |> Locator.locator("..")

      Expect.to_have_class!(even_row, ~r/table-even/)
      odd_row |> Expect.not_() |> Expect.to_have_class!(~r/table-even/)

      background = "cell => getComputedStyle(cell).backgroundColor"

      before =
        Promise.await!(
          Promise.all([
            Promise.async(fn ->
              even_row
              |> Locator.locator("td.line-content")
              |> Locator.first()
              |> Locator.evaluate!(background)
            end),
            Promise.async(fn ->
              odd_row
              |> Locator.locator("td.line-content")
              |> Locator.first()
              |> Locator.evaluate!(background)
            end)
          ])
        )

      refute Enum.at(before, 0) == Enum.at(before, 1)

      page
      |> Page.get_by_role(:cell, name: "x", exact: true)
      |> Locator.locator("..")
      |> Locator.locator(".line-gutter")
      |> Locator.click!()

      after_ =
        Promise.await!(
          Promise.all([
            Promise.async(fn ->
              page
              |> Page.get_by_role(:cell, name: "beta", exact: true)
              |> Locator.evaluate!(background)
            end),
            Promise.async(fn ->
              page
              |> Page.get_by_role(:cell, name: "gamma", exact: true)
              |> Locator.evaluate!(background)
            end)
          ])
        )

      assert after_ == before
    end

    test "live-added table comments remain wrapped in semantic annotation rows", %{
      page: page,
      browser: browser,
      token: token
    } do
      observer = Browser.new_page!(browser)
      load_review(page, token)
      load_review(observer, token)

      page
      |> Page.get_by_role(:cell, name: "beta", exact: true)
      |> Locator.locator("..")
      |> Locator.locator(".line-gutter")
      |> Locator.click!()

      textarea = Page.locator(page, ".comment-form textarea")
      Locator.fill!(textarea, "Broadcast table comment")
      Locator.press!(textarea, "Control+Enter")

      annotation =
        Page.locator(observer, "tr.native-table-annotation", has_text: "Broadcast table comment")

      Expect.to_be_visible!(annotation)
      assert Locator.evaluate!(annotation, "element => element.parentElement?.tagName") == "TBODY"
      Page.close!(observer)
    end
  end

  defp select_phrase(cell, phrase, occurrence \\ 0) do
    Locator.evaluate!(
      cell,
      """
      (element, requested) => {
        const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          let start = -1;
          let fromIndex = 0;
          for (let index = 0; index <= requested.occurrence; index++) {
            start = node.textContent?.indexOf(requested.phrase, fromIndex) ?? -1;
            if (start === -1) break;
            fromIndex = start + requested.phrase.length;
          }
          if (start === -1) continue;
          const range = document.createRange();
          range.setStart(node, start);
          range.setEnd(node, start + requested.phrase.length);
          const selection = window.getSelection();
          selection?.removeAllRanges();
          selection?.addRange(range);
          return;
        }
        throw new Error(`Phrase not found: ${requested.phrase}`);
      }
      """,
      %{phrase: phrase, occurrence: occurrence}
    )
  end
end
