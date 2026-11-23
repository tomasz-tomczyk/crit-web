defmodule CritWeb.E2E.DragSelectionTest do
  use CritWeb.E2ECase, async: true

  describe "Drag Selection — Multi-line Comment Range" do
    setup %{request: request} do
      # Use a markdown list so each item becomes its own line-block
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

    test "dragging across gutter elements opens comment form with multi-line header", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      gutters = Page.locator(page, ".line-gutter")
      first_gutter = Locator.nth(gutters, 0)
      third_gutter = Locator.nth(gutters, 2)

      # Boxes + mouse must be atomic: a layout shift between two separate
      # boundingBox reads nulls one out. dragGutterRange retries as one unit.
      drag_gutter_range(page, first_gutter, third_gutter)

      # Comment form should open with "Lines" in the header (multi-line range)
      form = Page.locator(page, ".comment-form")
      Expect.to_be_visible!(form, timeout: 5_000)

      header = Page.locator(page, ".comment-form-header")
      Expect.to_contain_text!(header, "Lines")

      # Submitting the range form creates one comment card
      textarea = Locator.locator(form, "textarea")
      Locator.fill!(textarea, "Comment spanning three lines")
      Locator.press!(textarea, "Control+Enter")

      Expect.to_be_visible!(
        Locator.filter(Page.locator(page, ".comment-card"),
          has_text: "Comment spanning three lines"
        ),
        timeout: 5_000
      )
    end

    test "after drag, selected line blocks have .selected class", %{page: page, token: token} do
      load_review(page, token)

      gutters = Page.locator(page, ".line-gutter")
      first_gutter = Locator.nth(gutters, 0)
      third_gutter = Locator.nth(gutters, 2)

      drag_gutter_range(page, first_gutter, third_gutter)

      # At least one line block should have the selected class
      selected_blocks = Page.locator(page, ".line-block.selected")
      count = Locator.count!(selected_blocks)
      assert count >= 1
    end

    test "single click on gutter opens single-line comment form", %{page: page, token: token} do
      load_review(page, token)

      # Click on a specific line block's gutter (skip the heading, use a list item)
      gutters = Page.locator(page, ".line-gutter")
      count = Locator.count!(gutters)
      # Use the second gutter (first list item) to avoid the heading block
      gutter = if count > 1, do: Locator.nth(gutters, 1), else: Locator.first(gutters)
      Locator.click!(gutter)

      form = Page.locator(page, ".comment-form")
      Expect.to_be_visible!(form, timeout: 5_000)

      header = Page.locator(page, ".comment-form-header")
      Expect.to_contain_text!(header, "Line")
    end

    test "Shift+click extends selection from anchor to a multi-line range", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      gutters = Page.locator(page, ".line-gutter")
      count = Locator.count!(gutters)
      assert count >= 4

      # Plain click sets the anchor (single-line form)
      Locator.click!(Locator.nth(gutters, 1))
      Expect.to_contain_text!(Page.locator(page, ".comment-form-header"), "Line")

      # Shift+click a lower gutter: the anchor extends into a range and the
      # form re-opens with a "Lines x–y" header
      Locator.click!(Locator.nth(gutters, 3), modifiers: [:shift])

      form = Page.locator(page, ".comment-form")
      Expect.to_be_visible!(form, timeout: 5_000)
      Expect.to_contain_text!(Page.locator(page, ".comment-form-header"), "Lines")
      Expect.to_have_count!(form, 1)
    end
  end
end
