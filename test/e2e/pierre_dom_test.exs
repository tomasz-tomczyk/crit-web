defmodule CritWeb.E2E.PierreDomTest do
  use CritWeb.E2ECase, async: true

  # crit-pierre-dom.js is crit's compatibility boundary for Pierre's shadow DOM
  # (labels, line lookup, quote highlights). crit-web vendors it; this checks
  # its selectors still match the vendored Pierre build.
  test "Pierre controls are labelled and lines resolve through the shared helpers", %{
    page: page,
    request: request
  } do
    review =
      create_review(request,
        files: [
          %{path: "a.go", content: "package a\n\nfunc A() {\n\treturn\n}\n"},
          %{path: "b.md", content: "# B\n"}
        ],
        comments: [%{start_line: 3, end_line: 3, body: "Quoted", file: "a.go"}]
      )

    try do
      load_review(page, review.token)
      # Re-hover inside the retry: Pierre re-renders drop a hover that landed
      # outside the retry, leaving no utility button (flaked in CI).
      Expect.to_pass!(
        fn ->
          code_file(page, "a.go")
          |> Locator.locator(~s([data-line="3"]))
          |> Locator.scroll_into_view_if_needed!(timeout: 2_000)

          hover_code_line(page, "a.go", 3)

          Expect.to_have_attribute!(
            Locator.locator(code_file(page, "a.go"), "[data-utility-button]"),
            "aria-label",
            "Add comment",
            timeout: 2_000
          )
        end,
        timeout: 20_000
      )

      host = Locator.locator(code_file(page, "a.go"), "diffs-container")
      Expect.to_have_attribute!(host, "data-crit-path", "a.go")

      text =
        Locator.evaluate!(code_file(page, "a.go"), """
        (el) => {
          const root = el.querySelector("diffs-container").shadowRoot;
          return root.querySelector('code [data-line="3"]').textContent;
        }
        """)

      assert text =~ "func A()"
    after
      delete_review(request, review.delete_token)
    end
  end
end
