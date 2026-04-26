defmodule CritWeb.Components.ReviewListingHeader do
  @moduledoc """
  Header row used by the dashboard review list and the review page meta bar.

  Renders title (dimmed dir + emphasized filename), an "Active {time_ago}"
  subline, and a stats group on the right (file count, comment count, optional
  delete). The title can be a link; an optional author chip replaces the
  "Active" subline with avatar + name when provided.
  """

  use Phoenix.Component

  import CritWeb.Helpers, only: [time_ago: 1, split_path: 1]
  import CritWeb.CoreComponents, only: [icon: 1]

  attr :path, :string, default: nil
  attr :last_activity_at, :any, required: true
  attr :file_count, :integer, required: true
  attr :comment_count, :integer, required: true
  attr :link_to, :string, default: nil
  attr :author, :map, default: nil

  slot :actions

  def review_listing_header(assigns) do
    {dir, file} = split_path(assigns.path)
    assigns = assigns |> assign(:dir, dir) |> assign(:file, file)

    ~H"""
    <header class="flex items-start justify-between gap-4 max-sm:flex-col max-sm:gap-1.5">
      <div class={[
        "min-w-0 flex max-sm:w-full",
        if(@author,
          do: "items-start gap-3 max-sm:items-center",
          else: "flex-col gap-0.5"
        )
      ]}>
        <%= if @author do %>
          <%= if @author.avatar_url do %>
            <img
              src={@author.avatar_url}
              alt={@author.name || @author.email || ""}
              class="size-7 rounded-full mt-0.5 shrink-0 max-sm:mt-0"
            />
          <% else %>
            <div class="size-7 rounded-full mt-0.5 shrink-0 max-sm:mt-0 bg-(--crit-bg-elevated) border border-(--crit-border) flex items-center justify-center text-xs font-semibold text-(--crit-fg-secondary) uppercase">
              {String.first(@author.name || @author.email || "?")}
            </div>
          <% end %>
          <div class="min-w-0 flex flex-col gap-0.5 max-sm:w-full">
            <div class="flex items-baseline gap-1.5 min-w-0">
              <%= if @author.name || @author.email do %>
                <span class="font-medium text-(--crit-fg-primary) truncate max-w-[160px] max-sm:max-w-[180px]">
                  {@author.name || @author.email}
                </span>
                <span class="text-(--crit-fg-muted) shrink-0">/</span>
              <% end %>
              <%= if @link_to do %>
                <.link
                  navigate={@link_to}
                  class={[
                    "font-semibold truncate leading-tight",
                    if(@path, do: "crit-link", else: "text-(--crit-fg-secondary) italic")
                  ]}
                >
                  <span class="text-(--crit-fg-muted) font-normal">{@dir}</span>{@file}
                </.link>
              <% else %>
                <span class={[
                  "font-semibold truncate leading-tight",
                  if(@path,
                    do: "text-(--crit-fg-primary)",
                    else: "text-(--crit-fg-secondary) italic"
                  )
                ]}>
                  <span class="text-(--crit-fg-muted) font-normal">{@dir}</span>{@file}
                </span>
              <% end %>
            </div>
            <span class="text-xs text-(--crit-fg-muted) max-sm:hidden">
              Active {time_ago(@last_activity_at)}
            </span>
          </div>
        <% else %>
          <%= if @link_to do %>
            <.link
              navigate={@link_to}
              class={[
                "font-semibold truncate block w-fit max-w-[720px] max-sm:max-w-full leading-tight",
                if(@path, do: "crit-link", else: "text-(--crit-fg-secondary) italic")
              ]}
            >
              <span class="text-(--crit-fg-muted) font-normal">{@dir}</span>{@file}
            </.link>
          <% else %>
            <span class={[
              "font-semibold truncate block max-w-[720px] max-sm:max-w-full leading-tight",
              if(@path, do: "text-(--crit-fg-primary)", else: "text-(--crit-fg-secondary) italic")
            ]}>
              <span class="text-(--crit-fg-muted) font-normal">{@dir}</span>{@file}
            </span>
          <% end %>
          <span class="text-xs text-(--crit-fg-muted) max-sm:hidden">
            Active {time_ago(@last_activity_at)}
          </span>
        <% end %>
      </div>
      <div class="flex items-center gap-3.5 text-xs text-(--crit-fg-secondary) shrink-0 max-sm:w-full max-sm:gap-3">
        <span class="hidden max-sm:inline-flex items-center text-(--crit-fg-muted)">
          Active {time_ago(@last_activity_at)}
        </span>
        <span class="inline-flex items-center gap-1 tabular-nums">
          <.icon name="hero-document-text-micro" class="size-3.5 text-(--crit-fg-muted)" />
          <span class="text-(--crit-fg-primary) font-medium">{@file_count}</span>
          {if @file_count == 1, do: "file", else: "files"}
        </span>
        <span class={[
          "inline-flex items-center gap-1 tabular-nums",
          @comment_count == 0 && "text-(--crit-fg-muted)"
        ]}>
          <.icon name="hero-chat-bubble-left-micro" class="size-3.5 text-(--crit-fg-muted)" />
          <span class={[
            if(@comment_count == 0,
              do: "text-(--crit-fg-muted)",
              else: "text-(--crit-fg-primary) font-medium"
            )
          ]}>
            {@comment_count}
          </span>
          {if @comment_count == 1, do: "comment", else: "comments"}
        </span>
        {render_slot(@actions)}
      </div>
    </header>
    """
  end
end
