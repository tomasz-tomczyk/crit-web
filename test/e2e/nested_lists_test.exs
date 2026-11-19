defmodule CritWeb.E2E.NestedListsTest do
  use CritWeb.E2ECase, async: true

  describe "Nested list rendering — per-item line blocks" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{
              path: "nested.md",
              content:
                Enum.join(
                  [
                    "# Nested",
                    "",
                    "- Top alpha lead.",
                    "  - Nested alpha-one.",
                    "  - Nested alpha-two.",
                    "    - Deep alpha-two-a.",
                    "- Top beta lead.",
                    "  - Nested beta-one.",
                    ""
                  ],
                  "\n"
                )
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "each nested bullet item is its own commentable line block", %{page: page, token: token} do
      load_review(page, token)

      items = [
        "Top alpha lead.",
        "Nested alpha-one.",
        "Nested alpha-two.",
        "Deep alpha-two-a.",
        "Top beta lead.",
        "Nested beta-one."
      ]

      start_lines =
        for text <- items, into: MapSet.new() do
          block =
            page
            |> Page.locator("#document-renderer .line-block")
            |> Locator.filter(has_text: text)
            |> Locator.first()

          Expect.to_be_visible!(block)
          start_line = Locator.get_attribute!(block, "data-start-line")
          assert start_line, ~s(block for "#{text}" should have data-start-line)
          start_line
        end

      assert MapSet.size(start_lines) == length(items)

      Expect.to_be_attached!(
        Locator.first(Page.locator(page, "#document-renderer ul.crit-list-wrapper"))
      )
    end
  end
end
