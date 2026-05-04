defmodule CritWeb.Components.PopoverMenuTest do
  use CritWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component

  import CritWeb.Components.PopoverMenu

  test "renders trigger button and panel with shared shell wiring" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.popover_menu id="visibility-menu" test_prefix="visibility">
        <:trigger>
          <span>Trigger label</span>
        </:trigger>
        <span class="option-row">option content</span>
      </.popover_menu>
      """)

    assert html =~ ~s(data-test="visibility-menu")
    assert html =~ ~s(id="visibility-menu-trigger")
    assert html =~ ~s(id="visibility-menu-panel")
    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-haspopup="dialog")
    assert html =~ ~s(aria-controls="visibility-menu-panel")
    assert html =~ "Trigger label"
    assert html =~ "option content"
  end

  test "panel is closed by default (no data-open=true) and trigger has aria-expanded=false" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.popover_menu id="m" test_prefix="m"><:trigger>t</:trigger>x</.popover_menu>
      """)

    assert html =~ ~s(aria-expanded="false")
    refute html =~ ~s(data-open="true")
  end

  test "test_prefix namespaces the data-test attributes" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.popover_menu id="comment-policy-menu" test_prefix="comment-policy">
        <:trigger>x</:trigger>
        body
      </.popover_menu>
      """)

    assert html =~ ~s(data-test="comment-policy-menu")
    refute html =~ "visibility-menu"
  end
end
