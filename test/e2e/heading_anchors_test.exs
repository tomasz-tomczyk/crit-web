defmodule CritWeb.E2E.HeadingAnchorsTest do
  use CritWeb.E2ECase, async: true

  test "GitHub-style links jump to headings in shared documents", %{page: page, request: request} do
    content =
      Enum.join(
        ["# Plan", "", "See [phase 2](#rollout--phase-2).", ""] ++
          Enum.map(0..49, &"Paragraph #{&1}: work to complete before rollout.\n") ++
          ["## Rollout — [Phase 2](https://example.com/phase-2)", "", "Per-tenant rate limits."],
        "\n"
      )

    review = create_review(request, files: [%{path: "plan.md", content: content}])

    try do
      load_review(page, review.token)
      target = Page.locator(page, "#document-renderer h2#rollout--phase-2")
      Expect.to_be_attached!(target)
      Expect.not_to_be_in_viewport!(target)

      page
      |> Page.locator(~s(#document-renderer a[href="#rollout--phase-2"]), has_text: "phase 2")
      |> Locator.click!()

      Expect.to_have_url!(page, ~r/#rollout--phase-2$/)
      Expect.to_be_in_viewport!(target)
    after
      delete_review(request, review.delete_token)
    end
  end

  test "shared headings keep GitHub's spaces, underscores, and duplicate suffixes", %{
    page: page,
    request: request
  } do
    review =
      create_review(request,
        files: [
          %{
            path: "headings.md",
            content:
              Enum.join(
                [
                  "## S7 — Data collection",
                  "## Step 1 – Checkout",
                  "## my_var settings",
                  "## Shop 🚀 launch",
                  "## See [shop-api](https://example.com)",
                  "## S7 — Data collection"
                ],
                "\n\n"
              )
          }
        ]
      )

    try do
      load_review(page, review.token)

      for id <- [
            "s7--data-collection",
            "step-1--checkout",
            "my_var-settings",
            "shop--launch",
            "see-shop-api",
            "s7--data-collection-1"
          ] do
        Expect.to_have_count!(Page.locator(page, ~s(#document-renderer h2[id="#{id}"])), 1)
      end
    after
      delete_review(request, review.delete_token)
    end
  end
end
