defmodule CritWeb.Components.PopoverMenu do
  @moduledoc """
  Generic popover-menu shell: ghost trigger button + click-away-dismissible
  panel, with ARIA wiring (`role="dialog"`, `aria-haspopup`,
  `aria-controls`, `aria-expanded`) and `data-test` hooks.

  Owns no policy: each call site composes its own trigger label and panel
  contents (status row, option rows, badge, etc.) inline. See
  `lib/crit_web/live/review_live.html.heex` for the visibility and
  comment_policy callers.
  """

  use Phoenix.Component
  alias Phoenix.LiveView.JS

  @doc """
  Returns a `JS` chain that closes the popover panel with the given `id`.

  Chain this onto an option button's `phx-click` so selecting an option
  both fires the server event and dismisses the menu:

      phx-click={
        PopoverMenu.close_js("comment-policy-menu")
        |> JS.push("update_comment_policy", value: %{policy: "open"})
      }
  """
  def close_js(id, %JS{} = js \\ %JS{}) when is_binary(id) do
    js
    |> JS.set_attribute({"data-open", "false"}, to: "##{id}-panel")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "##{id}-trigger")
  end

  attr :id, :string, required: true
  attr :open?, :boolean, default: false
  attr :placement, :atom, default: :below, values: [:below]
  attr :test_prefix, :string, required: true
  attr :panel_label, :string, default: "Menu"

  slot :trigger, required: true
  slot :inner_block, required: true

  def popover_menu(assigns) do
    ~H"""
    <div
      class="crit-popover-menu"
      data-test={"#{@test_prefix}-menu"}
      phx-click-away={
        JS.set_attribute({"data-open", "false"}, to: "##{@id}-panel")
        |> JS.set_attribute({"aria-expanded", "false"}, to: "##{@id}-trigger")
      }
    >
      <button
        type="button"
        id={"#{@id}-trigger"}
        class="crit-popover-menu-trigger"
        aria-haspopup="dialog"
        aria-expanded={to_string(@open?)}
        aria-controls={"#{@id}-panel"}
        phx-click={
          JS.toggle_attribute({"data-open", "true", "false"}, to: "##{@id}-panel")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{@id}-trigger")
        }
      >
        {render_slot(@trigger)}
      </button>
      <div
        id={"#{@id}-panel"}
        class="crit-popover-menu-panel"
        role="dialog"
        aria-label={@panel_label}
        data-open={to_string(@open?)}
        data-test={"#{@test_prefix}-panel"}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
