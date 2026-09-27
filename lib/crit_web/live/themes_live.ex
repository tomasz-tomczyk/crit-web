defmodule CritWeb.ThemesLive do
  @moduledoc """
  `/themes`: flip through the bundled themes on fixed review samples (a code
  file with a comment, a file-level thread, rendered Markdown) and pick a
  light and a dark theme. Linked from the review page's Settings. Same page as
  crit's `/themes`; the samples use crit-web's review markup.

  The list is rendered here from `CritWeb.ThemePalette`; the `ThemePreview`
  hook (assets/js/theme-preview.js) previews a theme by asking for its
  stylesheet (`theme_palette`, same event as the review page) and saves the
  choice to the `crit-settings` cookie.
  """
  use CritWeb, :live_view

  alias CritWeb.ThemePalette

  # The review page's code display settings (settings-panel.js rendererRows),
  # minus the theme selects this page replaces.
  @display_settings [
    %{
      key: "lineNumbers",
      label: "Line numbers",
      fallback: "on",
      options: [{"on", "On"}, {"off", "Off"}]
    },
    %{
      key: "codeOverflow",
      label: "Long lines",
      fallback: "scroll",
      options: [{"scroll", "Scroll"}, {"wrap", "Wrap"}]
    },
    %{
      key: "boostContrast",
      label: "Syntax contrast",
      fallback: "off",
      options: [{"off", "Theme default"}, {"on", "Increased"}]
    }
  ]

  def session_opts(conn) do
    %{"crit_settings" => conn.req_cookies[ThemePalette.cookie()]}
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Themes - Crit")
     |> assign(:noindex, true)
     |> assign(:crit_palette, ThemePalette.for_cookie(session["crit_settings"]))
     |> assign(:crit_display, CritWeb.ReviewDisplay.for_cookie(session["crit_settings"]))
     |> assign(
       :palettes,
       Enum.sort_by(ThemePalette.palettes(), &String.downcase(&1.display_name))
     )
     |> assign(:display_settings, @display_settings), layout: false}
  end

  @impl true
  def handle_event("theme_palette", params, socket) do
    {:reply, ThemePalette.reply(params), socket}
  end

  defp swatch(colors, role), do: Map.new(colors)[role]
end
