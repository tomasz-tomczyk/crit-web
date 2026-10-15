defmodule CritWeb.SiteComponents do
  @moduledoc """
  Building blocks for the public pages (home, modes, features, integrations,
  articles, legal, newsletter). One layout system: a 1200px column, sections
  that alternate between the page and panel surfaces, a mono eyebrow over each
  heading, and a brand-coloured full stop.

  Tailwind only. The review page has its own CSS in `app.css`; nothing here
  belongs there.
  """
  use Phoenix.Component

  @doc "The page column: 1200px of content with the side margins."
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def wrap(assigns) do
    ~H"""
    <div
      class={["mx-auto w-full max-w-[1312px] px-14 max-lg:px-10 max-md:px-5", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A page section. `panel` puts it on the card surface; consecutive sections
  get a hairline between them.
  """
  attr :id, :string, default: nil
  attr :panel, :boolean, default: false
  attr :class, :any, default: nil
  attr :wrap_class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "py-24 max-md:py-18 scroll-mt-[72px] max-md:scroll-mt-16 border-(--crit-border) [section+&]:border-t",
        @panel && "bg-(--crit-bg-card)",
        @class
      ]}
      {@rest}
    >
      <.wrap class={@wrap_class}>{render_slot(@inner_block)}</.wrap>
    </section>
    """
  end

  @doc "Eyebrow, heading and intro above a section's content."
  attr :eyebrow, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true, doc: "the heading text"
  slot :text

  def section_head(assigns) do
    ~H"""
    <div class={["max-w-[720px] mb-14 max-md:mb-10", @class]}>
      <.eyebrow :if={@eyebrow} blue>{@eyebrow}</.eyebrow>
      <.title>{render_slot(@inner_block)}</.title>
      <p
        :for={text <- @text}
        class="mt-4 text-lg leading-relaxed text-(--crit-fg-secondary) max-w-[62ch] text-pretty"
      >
        {render_slot(text)}
      </p>
    </div>
    """
  end

  @doc "Section heading. `display` is the larger size used for calls to action."
  attr :tag, :string, default: "h2"
  attr :display, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def title(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={[
        "font-semibold tracking-[-0.02em] text-balance text-(--crit-fg-primary)",
        @display && "text-[clamp(36px,5vw,64px)] leading-[1.02]",
        !@display && "text-[clamp(30px,3.6vw,48px)] leading-[1.08]",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  @doc "The brand full stop that ends headings."
  def dot(assigns) do
    ~H"""
    <span class="text-(--crit-brand)">.</span>
    """
  end

  @doc """
  Heading text that may end in a full stop: the stop is drawn as `dot/1`.
  Text without one gets none.
  """
  attr :text, :string, required: true

  def dotted(assigns) do
    assigns =
      case String.split_at(assigns.text, -1) do
        {head, "."} -> assign(assigns, text: head, dot: true)
        _ -> assign(assigns, dot: false)
      end

    ~H"""
    {@text}<.dot :if={@dot} />
    """
  end

  @doc "Small mono label above a heading."
  attr :blue, :boolean, default: false
  attr :tag, :string, default: "p"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={[
        "font-mono text-xs font-normal tracking-[0.12em] uppercase mb-3",
        @blue && "text-(--crit-brand)",
        !@blue && "text-(--crit-fg-muted)",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  @doc "A text link with an arrow, in the brand colour."
  attr :href, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def link_arrow(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "inline-block py-2 font-semibold text-(--crit-brand) no-underline hover:text-(--crit-fg-primary) transition-colors",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)} <span aria-hidden="true">&rarr;</span>
    </a>
    """
  end

  @doc "A row of `link_arrow`s."
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def links(assigns) do
    ~H"""
    <p class={["flex flex-wrap gap-x-6 mt-4", @class]}>{render_slot(@inner_block)}</p>
    """
  end

  @doc "Button link. `primary` is the brand fill; `ghost` is an outline."
  attr :href, :string, required: true
  attr :variant, :string, default: "primary", values: ~w(primary ghost)
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def btn(assigns) do
    ~H"""
    <a href={@href} class={[btn_class(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </a>
    """
  end

  @doc false
  def btn_class("primary"),
    do:
      "inline-flex items-center justify-center gap-2.5 px-6 py-[15px] rounded-md font-semibold leading-none no-underline bg-(--crit-brand) text-(--crit-bg-page) hover:bg-(--crit-fg-primary) transition-colors"

  def btn_class("ghost"),
    do:
      "inline-flex items-center justify-center gap-2.5 px-6 py-[15px] rounded-md font-semibold leading-none no-underline text-(--crit-fg-primary) shadow-[inset_0_0_0_1px_var(--crit-border-strong)] hover:bg-(--crit-bg-elevated) transition-colors"

  @doc "Pill labels, e.g. what a mode does."
  attr :items, :list, required: true
  attr :class, :any, default: nil
  attr :label, :string, default: nil

  def chips(assigns) do
    ~H"""
    <ul class={["flex flex-wrap gap-2", @class]} aria-label={@label}>
      <li
        :for={item <- @items}
        class="font-mono text-xs leading-snug text-(--crit-fg-secondary) border border-(--crit-border-strong) rounded-full px-3 py-[5px]"
      >
        {item}
      </li>
    </ul>
    """
  end

  @doc "A grid of cards: three columns, two on laptops, one on phones."
  attr :cols, :integer, default: 3, values: [2, 3]
  attr :class, :any, default: nil
  attr :tag, :string, default: "ul"
  slot :inner_block, required: true

  def cards(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={[
        "grid gap-6",
        @cols == 3 && "grid-cols-3 max-lg:grid-cols-2 max-md:grid-cols-1",
        @cols == 2 && "grid-cols-2 max-md:grid-cols-1",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  @doc "The panel card used for features, modes and notes."
  attr :href, :string, default: nil
  attr :tag, :string, default: "div"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    assigns =
      assign(
        assigns,
        :base,
        "group flex flex-col gap-3 h-full px-6 py-10 max-md:py-8 rounded-xl border border-(--crit-border) bg-(--crit-bg-card)"
      )

    ~H"""
    <a
      :if={@href}
      href={@href}
      class={[
        @base,
        "no-underline text-inherit hover:border-(--crit-brand) transition-colors",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </a>
    <.dynamic_tag :if={!@href} tag_name={@tag} class={[@base, @class]} {@rest}>
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  @doc "Card heading."
  attr :tag, :string, default: "h3"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card_title(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={[
        "text-xl font-semibold leading-tight tracking-[-0.01em] text-(--crit-fg-primary)",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  @doc "Card body text."
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card_text(assigns) do
    ~H"""
    <p class={["text-sm leading-relaxed text-(--crit-fg-secondary)", @class]}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc "Numbered steps with a rule above each one."
  attr :class, :any, default: nil
  attr :cols, :integer, default: 4, values: [2, 3, 4]

  slot :step, required: true do
    attr :title, :string, required: true
  end

  def steps(assigns) do
    ~H"""
    <ol class={[
      "grid gap-6",
      @cols == 4 && "grid-cols-4 max-lg:grid-cols-2 max-md:grid-cols-1",
      @cols == 3 && "grid-cols-3 max-md:grid-cols-1",
      @cols == 2 && "grid-cols-2 max-md:grid-cols-1",
      @class
    ]}>
      <li
        :for={{step, idx} <- Enum.with_index(@step, 1)}
        class="border-t border-(--crit-border-strong) pt-4"
      >
        <span class="block font-mono text-xs text-(--crit-brand) mb-3">
          {String.pad_leading(Integer.to_string(idx), 2, "0")}
        </span>
        <h3 class="text-xl font-semibold leading-tight tracking-[-0.01em] mb-2 text-(--crit-fg-primary)">
          {step.title}
        </h3>
        <div class="text-sm leading-relaxed text-(--crit-fg-secondary)">{render_slot(step)}</div>
      </li>
    </ol>
    """
  end

  @doc """
  The top of an inner page: eyebrow, the page title, a lede and whatever
  follows (chips, actions, a film).
  """
  attr :eyebrow, :string, default: nil
  attr :class, :any, default: nil
  attr :title_class, :any, default: nil
  attr :tag, :string, default: "header"
  slot :title, required: true
  slot :lede
  slot :inner_block

  def page_head(assigns) do
    ~H"""
    <.dynamic_tag tag_name={@tag} class={["pt-24 pb-14 max-md:pt-14 max-md:pb-10", @class]}>
      <.wrap>
        <.eyebrow :if={@eyebrow} blue>{@eyebrow}</.eyebrow>
        <h1 class={[
          "font-semibold tracking-[-0.02em] text-balance max-w-[16em] text-[clamp(36px,5vw,64px)] leading-[1.02] text-(--crit-fg-primary)",
          @title_class
        ]}>
          {render_slot(@title)}
        </h1>
        <p
          :for={lede <- @lede}
          class="mt-6 max-w-[62ch] text-[clamp(18px,1.6vw,21px)] leading-normal text-(--crit-fg-secondary) text-pretty"
        >
          {render_slot(lede)}
        </p>
        {render_slot(@inner_block)}
      </.wrap>
    </.dynamic_tag>
    """
  end

  @doc "Pill links to sibling pages."
  attr :label, :string, required: true
  attr :current, :string, default: nil

  slot :item, required: true do
    attr :href, :string, required: true
  end

  def subnav(assigns) do
    ~H"""
    <nav class="flex flex-wrap gap-2" aria-label={@label}>
      <a
        :for={item <- @item}
        href={item.href}
        aria-current={item.href == @current && "page"}
        class="inline-flex items-center min-h-11 px-4 rounded-full border border-(--crit-border-strong) text-sm font-medium text-(--crit-fg-secondary) no-underline hover:border-(--crit-brand) hover:text-(--crit-fg-primary) aria-[current=page]:border-(--crit-brand) aria-[current=page]:text-(--crit-fg-primary)"
      >
        {render_slot(item)}
      </a>
    </nav>
    """
  end

  @doc "A terminal frame: three dots and a label over mono content."
  attr :label, :string, default: nil
  attr :class, :any, default: nil
  attr :body_class, :any, default: nil
  slot :inner_block, required: true

  def terminal(assigns) do
    ~H"""
    <div class={[
      "rounded-xl border border-(--crit-border-strong) bg-(--crit-bg-card) overflow-hidden",
      @class
    ]}>
      <div
        class="flex items-center gap-1.5 px-4 py-3 border-b border-(--crit-border)"
        aria-hidden="true"
      >
        <i class="size-2.5 rounded-full bg-(--crit-border-strong)"></i>
        <i class="size-2.5 rounded-full bg-(--crit-border-strong)"></i>
        <i class="size-2.5 rounded-full bg-(--crit-border-strong)"></i>
        <span :if={@label} class="ml-auto font-mono text-xs text-(--crit-fg-muted)">{@label}</span>
      </div>
      <div class={[
        "p-6 max-md:p-4 font-mono text-sm leading-[1.7] text-(--crit-fg-primary) overflow-x-auto",
        @body_class
      ]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "A 16:9 frame around a screenshot or film."
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def media(assigns) do
    ~H"""
    <div
      class={[
        "relative block overflow-hidden rounded-xl border border-(--crit-border-strong) bg-(--crit-bg-card)",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end
end
