defmodule CritWeb.E2E.DiagramOverlayTest do
  use CritWeb.E2ECase, async: true

  describe "Diagram fullscreen overlay" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [%{path: "plan.md", content: "# Plan\n\n```mermaid\ngraph TD; A-->B;\n```\n"}]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "opens from the expand button, closes on Escape and returns focus", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      block = Locator.first(Page.locator(page, ".line-content.render-block"))

      Expect.to_be_visible!(Locator.first(Locator.locator(block, ".crit-render-output svg")),
        timeout: 10_000
      )

      expand = Locator.locator(block, ".crit-render-expand")
      Expect.to_have_accessible_name!(expand, ~r/diagram fullscreen/)
      Locator.hover!(block)
      Locator.click!(expand)

      overlay = Page.locator(page, "#diagramOverlay")
      Expect.to_have_class!(overlay, ~r/\bactive\b/)
      Expect.to_be_visible!(Locator.locator(overlay, "#diagramOverlayCanvas svg"))
      Expect.to_be_focused!(Page.locator(page, "#diagramOverlayClose"))

      Keyboard.press!(Page.keyboard(page), "Escape")
      Expect.not_to_have_class!(overlay, ~r/\bactive\b/)
      Expect.to_be_hidden!(overlay)
      Expect.to_be_focused!(expand)
    end
  end
end
