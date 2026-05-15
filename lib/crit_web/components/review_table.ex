defmodule CritWeb.Components.ReviewTable do
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: CritWeb.Endpoint, router: CritWeb.Router

  import CritWeb.CoreComponents, only: [icon: 1]
  import CritWeb.Helpers, only: [split_path: 1, date_label: 1, time_ago: 1]

  @doc """
  Renders a paginated review table.

  ## Variants

  - `:personal` — shows VISIBILITY and UPDATED columns
  - `:org` — shows VISIBILITY and AUTHOR columns
  """
  attr :variant, :atom, required: true, values: [:personal, :org]
  attr :reviews, :list, required: true
  attr :review_count, :integer, required: true
  attr :page, :integer, default: 1
  attr :per_page, :integer, default: 15

  def review_table(assigns) do
    total_pages = max(1, ceil(assigns.review_count / assigns.per_page))
    assigns = assign(assigns, :total_pages, total_pages)

    ~H"""
    <div class="border border-(--crit-border) rounded-lg overflow-hidden">
      <%!-- Column headers --%>
      <div class="flex items-center px-4 py-2.5 text-[11px] uppercase tracking-[0.08em] text-(--crit-fg-muted) font-medium border-b border-(--crit-border) bg-(--crit-bg-card) max-sm:hidden">
        <div class="flex-1 min-w-0 pl-8">Review</div>
        <div class="w-[130px] shrink-0 text-left">Visibility</div>
        <div class="w-[130px] shrink-0 text-left">
          {if @variant == :org, do: "Author", else: "Updated"}
        </div>
        <div class="w-[50px] shrink-0 text-right">
          <.icon name="hero-chat-bubble-left-micro" class="size-3.5" />
        </div>
      </div>

      <%!-- Rows --%>
      <div id="reviews-table" phx-update="stream">
        <.link
          :for={{dom_id, review} <- @reviews}
          id={dom_id}
          navigate={~p"/r/#{review.token}"}
          class="flex items-center px-4 py-3 border-b border-(--crit-border) last:border-b-0 no-underline hover:bg-(--crit-bg-elevated) transition-colors group max-sm:gap-3"
        >
          <div class="flex items-center gap-3 flex-1 min-w-0">
            <.icon
              name="hero-document-text"
              class="size-[18px] text-(--crit-fg-muted) shrink-0"
            />
            <div class="min-w-0">
              <% {dir, file} = split_path(review.first_file_path) %>
              <div class="font-semibold text-sm text-(--crit-fg-primary) leading-tight truncate">
                <span class="text-(--crit-fg-muted) font-normal">{dir}</span>{file}
              </div>
              <div class="text-xs text-(--crit-fg-muted) mt-0.5 truncate font-mono">
                {review.first_file_path || "Untitled"}
              </div>
            </div>
          </div>

          <div class="w-[130px] shrink-0 max-sm:hidden">
            <.visibility_badge review={review} />
          </div>

          <div class="w-[130px] shrink-0 text-sm text-(--crit-fg-muted) max-sm:hidden">
            <%= if @variant == :org do %>
              <.author_cell review={review} />
            <% else %>
              <span class="text-xs">{date_label(review.last_activity_at)}</span>
            <% end %>
          </div>

          <div class="w-[50px] shrink-0 text-right text-xs text-(--crit-fg-muted) tabular-nums inline-flex items-center justify-end gap-1 max-sm:hidden">
            <.icon name="hero-chat-bubble-left-micro" class="size-3.5" />
            {review.comment_count}
          </div>

          <%!-- Mobile: compact meta below file name --%>
          <div class="hidden max-sm:flex items-center gap-2 text-xs text-(--crit-fg-muted) shrink-0">
            <span :if={review.comment_count > 0} class="inline-flex items-center gap-0.5">
              <.icon name="hero-chat-bubble-left-micro" class="size-3" />
              {review.comment_count}
            </span>
            <span>{date_label(review.last_activity_at)}</span>
          </div>
        </.link>
      </div>

      <%!-- Pagination footer --%>
      <div class="flex items-center justify-between px-4 py-3 border-t border-(--crit-border) bg-(--crit-bg-card) text-xs text-(--crit-fg-muted)">
        <span>
          Page <span class="font-mono text-(--crit-fg-primary)">{@page}</span> of {@total_pages}
        </span>
        <div class="flex items-center gap-1">
          <button
            phx-click="change_page"
            phx-value-page={@page - 1}
            disabled={@page <= 1}
            class="inline-flex items-center gap-0.5 px-2.5 py-1.5 rounded border border-(--crit-border) text-(--crit-fg-muted) hover:bg-(--crit-bg-elevated) transition-colors disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
          >
            <.icon name="hero-chevron-left-mini" class="size-3.5" /> Previous
          </button>
          <button
            phx-click="change_page"
            phx-value-page={@page + 1}
            disabled={@page >= @total_pages}
            class="inline-flex items-center gap-0.5 px-2.5 py-1.5 rounded border border-(--crit-border) text-(--crit-fg-primary) font-medium hover:bg-(--crit-bg-elevated) transition-colors disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
          >
            Next <.icon name="hero-chevron-right-mini" class="size-3.5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp visibility_badge(assigns) do
    {icon, label, classes} =
      case {assigns.review.visibility, assigns.review.organization_id} do
        {:organization, org_id} when not is_nil(org_id) ->
          initial = String.first(assigns.review.org_name || "?") |> String.upcase()

          {"org_initial:#{initial}", assigns.review.org_name || "Org",
           "bg-[rgba(122,162,247,0.15)] text-[#7aa2f7]"}

        {:public, _} ->
          {"hero-globe-alt-mini", "Public",
           "bg-[rgba(122,162,247,0.10)] text-(--crit-fg-secondary)"}

        {:unlisted, org_id} when not is_nil(org_id) ->
          {"hero-share-mini", "Unlisted", "bg-(--crit-bg-elevated) text-(--crit-fg-secondary)"}

        {:unlisted, nil} ->
          {"hero-share-mini", "Unlisted", "bg-(--crit-bg-elevated) text-(--crit-fg-secondary)"}

        _ ->
          {"hero-lock-closed-mini", "Private",
           "bg-(--crit-bg-elevated) text-(--crit-fg-secondary)"}
      end

    assigns = assign(assigns, icon: icon, label: label, classes: classes)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium",
      @classes
    ]}>
      <%= if String.starts_with?(@icon, "org_initial:") do %>
        <% initial = String.replace_prefix(@icon, "org_initial:", "") %>
        <span class="w-4 h-4 rounded bg-[rgba(122,162,247,0.3)] text-[#7aa2f7] inline-flex items-center justify-center text-[9px] font-bold leading-none">
          {initial}
        </span>
      <% else %>
        <.icon name={@icon} class="size-3.5" />
      <% end %>
      <span class="truncate max-w-[80px]">{@label}</span>
    </span>
    """
  end

  defp author_cell(assigns) do
    initials =
      case assigns.review.author_name do
        nil ->
          "?"

        name ->
          name
          |> String.split(~r/\s+/, trim: true)
          |> Enum.take(2)
          |> Enum.map(&String.first/1)
          |> Enum.join()
          |> String.upcase()
      end

    assigns = assign(assigns, :initials, initials)

    ~H"""
    <div class="flex items-center gap-2">
      <%= if @review.author_avatar_url do %>
        <img
          src={@review.author_avatar_url}
          alt=""
          class="size-6 rounded-full shrink-0"
        />
      <% else %>
        <span class="size-6 rounded-full bg-[rgba(122,162,247,0.18)] text-[#7aa2f7] inline-flex items-center justify-center text-[9px] font-semibold shrink-0">
          {@initials}
        </span>
      <% end %>
      <div class="min-w-0">
        <div class="text-xs text-(--crit-fg-primary) font-medium truncate leading-tight">
          {@review.author_name || "Unknown"}
        </div>
        <div class="text-[11px] text-(--crit-fg-muted) leading-tight">
          {time_ago(@review.last_activity_at)}
        </div>
      </div>
    </div>
    """
  end
end
