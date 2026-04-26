defmodule CritWeb.Components.ReviewSnippet do
  @moduledoc """
  Renders the snippet preview block used in the dashboard and overview review lists.

  Computes the preview from the file path and content via
  `CritWeb.Helpers.snippet_preview/2`, rendering one of three branches: a
  syntax-highlighted code listing with line numbers, rendered markdown, or a
  "no preview" placeholder.

  The parent must include the `SnippetHighlight` colocated hook to apply
  highlight.js to elements with `[data-snippet-line]`.
  """

  use Phoenix.Component

  attr :path, :string, default: nil
  attr :content, :string, default: nil

  def review_snippet(assigns) do
    assigns =
      assigns
      |> assign(:snippet, CritWeb.Helpers.snippet_preview(assigns.path, assigns.content))
      |> assign(:lang, CritWeb.Helpers.language_for_path(assigns.path))

    ~H"""
    <%= case @snippet do %>
      <% {:code, lines} -> %>
        <div class="border border-(--crit-border) rounded-md overflow-hidden h-[200px] relative font-mono text-xs leading-5">
          <div class="py-2">
            <div
              :for={{line, idx} <- Enum.with_index(lines, 1)}
              class="grid grid-cols-[44px_1fr] gap-x-2.5 pr-3.5"
            >
              <span class="text-right text-(--crit-fg-muted) opacity-60 select-none text-[11px] pr-1.5 leading-5">
                {idx}
              </span>
              <code
                class="hljs whitespace-pre overflow-hidden !bg-transparent p-0 text-(--crit-fg-primary)"
                data-snippet-line
                data-lang={@lang}
                phx-no-format
              >{line}</code>
            </div>
          </div>
          <div class="absolute inset-x-0 bottom-0 h-9 bg-gradient-to-b from-transparent to-(--crit-bg-page) pointer-events-none">
          </div>
        </div>
      <% {:markdown, html} -> %>
        <div class="border border-(--crit-border) rounded-md overflow-hidden h-[200px] relative px-5 py-3 text-sm
                    [&_h1]:text-base [&_h1]:font-semibold [&_h1]:mt-0 [&_h1]:mb-1.5 [&_h1]:pb-1 [&_h1]:border-b [&_h1]:border-(--crit-border)
                    [&_h2]:text-[15px] [&_h2]:font-semibold [&_h2]:mt-2.5 [&_h2]:mb-1
                    [&_h3]:text-sm [&_h3]:font-semibold [&_h3]:mt-2 [&_h3]:mb-1
                    [&_p]:my-1 [&_p]:leading-relaxed
                    [&_ul]:list-disc [&_ul]:pl-5 [&_ul]:my-1
                    [&_ol]:list-decimal [&_ol]:pl-5 [&_ol]:my-1
                    [&_li]:my-0.5
                    [&_a]:text-(--crit-brand) [&_a]:underline
                    [&_code]:font-mono [&_code]:text-[12px] [&_code]:bg-(--crit-bg-elevated) [&_code]:px-1 [&_code]:py-0.5 [&_code]:rounded
                    [&_pre]:font-mono [&_pre]:text-[12px] [&_pre]:bg-(--crit-bg-elevated) [&_pre]:p-2 [&_pre]:rounded [&_pre]:my-1.5 [&_pre]:overflow-hidden
                    [&_pre_code]:bg-transparent [&_pre_code]:px-0 [&_pre_code]:py-0
                    [&_blockquote]:border-l-2 [&_blockquote]:border-(--crit-border-strong) [&_blockquote]:pl-3 [&_blockquote]:text-(--crit-fg-secondary)
                    [&_strong]:font-semibold [&_em]:italic">
          {html}
          <div class="absolute inset-x-0 bottom-0 h-9 bg-gradient-to-b from-transparent to-(--crit-bg-page) pointer-events-none">
          </div>
        </div>
      <% :none -> %>
        <div class="border border-dashed border-(--crit-border) rounded-md h-12 flex items-center justify-center text-xs text-(--crit-fg-muted)">
          No preview available
        </div>
    <% end %>
    """
  end
end
