defmodule CritWeb.E2E.MarkdownSourceTest do
  use CritWeb.E2ECase, async: true

  # Markdown files get a Document / Source toggle (crit #1106). Source shows
  # the whole file in the code view; Document is the rendered default.

  @plan "plan.md"
  @notes "notes.md"

  defp comments_of(request, token) do
    res = APIRequestContext.get!(request, "#{base_url()}/api/reviews/#{token}/comments")
    assert APIResponse.ok(res) == true
    APIResponse.json!(res)
  end

  defp section(page, path),
    do: Page.locator(page, ~s(details.file-section[data-file-path="#{path}"]))

  describe "Markdown Document / Source toggle" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{path: @plan, content: "# Plan\n\nFirst **step**.\n\nSecond step.\n"},
            %{path: @notes, content: "# Notes\n\nSome notes.\n"}
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "opens on Document, Source shows the file as code, Document switches back",
         %{page: page, request: request, token: token} do
      seed_comment(request, token, file: @plan, start_line: 3, body: "Spell out the step")
      load_review(page, token)
      file = section(page, @plan)
      toggle = Locator.locator(file, ".file-header .file-header-toggle")
      Expect.to_have_text!(Locator.get_by_role(toggle, :button), ["Document", "Source"])

      Expect.to_have_attribute!(
        Locator.locator(toggle, ~s([data-mode="rendered"])),
        "aria-pressed",
        "true"
      )

      Expect.to_have_text!(Locator.locator(file, ".line-content h1"), "Plan")
      # The Raw link stays.
      Expect.to_have_text!(Locator.locator(file, ".file-header .crit-round-diff-btn"), "Raw")

      Locator.click!(Locator.locator(toggle, ~s([data-mode="source"])))

      Expect.to_have_attribute!(
        Locator.locator(toggle, ~s([data-mode="source"])),
        "aria-pressed",
        "true"
      )

      Expect.to_contain_text!(code_line(page, @plan, 3), "First **step**.")
      Expect.to_have_count!(Locator.locator(file, ".line-block"), 0)
      Expect.to_contain_text!(Locator.locator(file, ".comment-card"), "Spell out the step")
      # The click switched views; it did not collapse the file.
      Expect.to_have_attribute!(file, "open", "")
      # The other file keeps its own view.
      Expect.to_have_text!(Locator.locator(section(page, @notes), ".line-content h1"), "Notes")

      Locator.click!(Locator.locator(toggle, ~s([data-mode="rendered"])))
      Expect.to_have_text!(Locator.locator(file, ".line-content h1"), "Plan")
      Expect.to_have_count!(Locator.locator(file, ".crit-code-file"), 0)
      Expect.to_contain_text!(Locator.locator(file, ".comment-card"), "Spell out the step")
    end

    test "j/k and c comment on a source line", %{page: page, request: request, token: token} do
      load_review(page, token)
      file = section(page, @notes)
      Locator.click!(Locator.locator(file, ~s(.file-header-toggle [data-mode="source"])))
      Expect.to_contain_text!(code_line(page, @notes, 1), "# Notes")
      # Collapse plan.md so j starts in notes.md.
      Locator.click!(Locator.locator(section(page, @plan), ".file-header-chevron"))
      Expect.not_to_have_attribute!(section(page, @plan), "open", "")

      keyboard = Page.keyboard(page)
      Keyboard.press!(keyboard, "j")
      Keyboard.press!(keyboard, "j")
      Keyboard.press!(keyboard, "c")
      form = Locator.locator(file, ".comment-form")
      Expect.to_be_visible!(form)
      Locator.fill!(Locator.locator(form, "textarea"), "On line two")
      Locator.press!(Locator.locator(form, "textarea"), "Control+Enter")
      Expect.to_contain_text!(Locator.locator(file, ".comment-card"), "On line two")
      # j twice: lines 1 and 2 of notes.md.
      Expect.poll!(
        fn ->
          comments_of(request, token)
          |> Enum.filter(&(&1["body"] == "On line two"))
          |> Enum.map(&"#{&1["start_line"]}-#{&1["end_line"]}")
        end,
        &assert(&1 == ["2-2"])
      )
    end

    test "the toggle is hidden while the round diff is on",
         %{page: page, request: request, token: token, delete_token: delete_token} do
      # Two updates leave a previous round to diff against.
      for step <- ["Second step, changed.", "Second step, changed again."] do
        res =
          APIRequestContext.put!(request, "#{base_url()}/api/reviews/#{token}",
            data: %{
              delete_token: delete_token,
              files: [
                %{path: @plan, content: "# Plan\n\nFirst **step**.\n\n#{step}\n"},
                %{path: @notes, content: "# Notes\n\nSome notes.\n"}
              ],
              comments: []
            }
          )

        assert APIResponse.ok(res)
      end

      load_review(page, token)
      toggle = Locator.locator(section(page, @plan), ".file-header-toggle")
      Locator.click!(Locator.locator(toggle, ~s([data-mode="source"])))
      Expect.to_contain_text!(code_line(page, @plan, 1), "# Plan")

      round_diff = Page.locator(page, "button.crit-round-diff-btn")
      Locator.click!(round_diff)
      Expect.to_be_visible!(Locator.locator(section(page, @plan), ".diff-view"))
      Expect.to_have_count!(Page.locator(page, ".file-header-toggle"), 0)
      Expect.to_have_count!(Locator.locator(section(page, @plan), ".crit-code-file"), 0)

      # Round diff off: the toggle and the Source view come back.
      Locator.click!(round_diff)

      Expect.to_have_attribute!(
        Locator.locator(toggle, ~s([data-mode="source"])),
        "aria-pressed",
        "true"
      )

      Expect.to_contain_text!(code_line(page, @plan, 1), "# Plan")
    end
  end
end
