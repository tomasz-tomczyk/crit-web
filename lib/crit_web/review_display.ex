defmodule CritWeb.ReviewDisplay do
  @moduledoc """
  The reader's code display settings that rendered markdown follows too:
  `lineNumbers` ("on" | "off") and `codeOverflow` ("scroll" | "wrap") from the
  `crit-settings` cookie (same keys as crit). Pierre applies them to code
  files in the browser; for markdown the root layout renders them on `<html>`
  as `data-line-numbers` / `data-code-overflow`, so the CSS applies before
  first paint. Unknown values fall back to the defaults.
  """

  alias CritWeb.ThemePalette

  def for_cookie(value) do
    settings = ThemePalette.decode_settings(value)

    %{
      line_numbers: if(settings["lineNumbers"] == "off", do: "off", else: "on"),
      code_overflow: if(settings["codeOverflow"] == "wrap", do: "wrap", else: "scroll")
    }
  end
end
