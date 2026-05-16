defmodule CritWeb.Components.MarketingToggle do
  @moduledoc """
  Shared marketing opt-in toggle switch used on the dashboard and settings pages.
  """
  use Phoenix.Component

  import CritWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders a marketing email opt-in toggle switch.

  ## Attributes

    * `id` - Required. Unique DOM id for the toggle container.
    * `marketing_opted_in` - Required. Boolean indicating current opt-in state.
    * `variant` - Optional. `:card` (dashboard style with icon + description card)
      or `:inline` (settings style, toggle only). Defaults to `:card`.
  """
  attr :id, :string, required: true
  attr :marketing_opted_in, :boolean, required: true
  attr :variant, :atom, default: :card

  def marketing_toggle(%{variant: :card} = assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex items-center gap-3.5 px-5 py-4 rounded-xl border transition-all duration-300",
        if(@marketing_opted_in,
          do: "bg-(--crit-bg-card) border-(--crit-border-strong)",
          else: "bg-(--crit-bg-card) border-(--crit-border)"
        )
      ]}
    >
      <span class="shrink-0 w-9 h-9 rounded-[10px] flex items-center justify-center bg-(--crit-brand-subtle)">
        <.icon
          name="hero-bell-solid"
          class={[
            "size-5 transition-all duration-300",
            if(@marketing_opted_in,
              do: "text-(--crit-green) -rotate-12",
              else: "text-(--crit-brand)"
            )
          ]}
        />
      </span>
      <div class="flex-1 min-w-0">
        <div class="text-sm font-semibold text-(--crit-fg-primary) leading-snug">
          Email me about new features and releases
        </div>
        <span class="text-xs text-(--crit-fg-muted)">
          We email when it's actually worth your time.
        </span>
      </div>
      <.toggle_switch marketing_opted_in={@marketing_opted_in} />
    </div>
    """
  end

  def marketing_toggle(%{variant: :inline} = assigns) do
    ~H"""
    <.toggle_switch id={@id} marketing_opted_in={@marketing_opted_in} />
    """
  end

  attr :id, :string, default: nil
  attr :marketing_opted_in, :boolean, required: true

  defp toggle_switch(assigns) do
    ~H"""
    <button
      id={@id}
      phx-click="toggle_marketing_consent"
      phx-throttle="500"
      role="switch"
      aria-checked={to_string(@marketing_opted_in)}
      aria-label="Email me about new features and releases"
      class={[
        "relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-(--crit-brand) focus-visible:ring-offset-2",
        if(@marketing_opted_in,
          do: "bg-(--crit-brand)",
          else: "bg-(--crit-border)"
        )
      ]}
    >
      <span class={[
        "pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow transform transition duration-200 ease-in-out",
        if(@marketing_opted_in, do: "translate-x-5", else: "translate-x-0")
      ]} />
    </button>
    """
  end
end
