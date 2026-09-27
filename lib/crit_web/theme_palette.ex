defmodule CritWeb.ThemePalette do
  @moduledoc """
  UI palettes for the review page, derived from the bundled Shiki themes.

  crit generates `pierre/palettes.js` from its Shiki themes (one foundation
  palette per theme: surfaces, foreground, accent, border, status and author
  colours). crit-web vendors that file (`scripts/sync-pierre.sh`) and reads it
  here at compile time.

  The reader picks a light and a dark theme in Settings (`lightPalette` /
  `darkPalette` in the `crit-settings` cookie, same keys as crit). `css/1`
  renders both halves as `--crit-palette-*` custom properties: dark by default,
  light under `[data-theme="light"]` and under `prefers-color-scheme: light`
  when no theme is forced. The vendored `crit-palette.css` maps those onto the
  `--crit-*` tokens, so chrome, markdown, comments and code share the theme.
  The same choice rules as crit's `crit-theme-palette.js` `pair/2` apply: an
  unknown id, or one of the wrong type, falls back to the default.
  """

  @source Path.join([__DIR__, "..", "..", "priv", "static", "pierre", "palettes.js.gz"])
  @external_resource @source

  @defaults %{"light" => "github-light-default", "dark" => "tokyo-night"}
  @cookie "crit-settings"

  # Colour values are data from the vendored bundle. They are checked when
  # compiling, so a malformed file can never inject CSS.
  @color ~r/\A(?:#[0-9a-fA-F]{3,8}|rgba?\(\s*[0-9.]+\s*,\s*[0-9.]+\s*,\s*[0-9.]+\s*(?:,\s*[0-9.]+\s*)?\))\z/
  @role ~r/\A[a-z0-9-]+\z/
  @id ~r/\A[a-z0-9-]+\z/

  @palettes (fn ->
               js = @source |> File.read!() |> :zlib.gunzip()

               [_, json] =
                 Regex.run(~r/window\.crit\.palettes=(\[.*\]);?\s*\z/s, js) ||
                   raise "unexpected palettes.js format in #{@source}"

               for p <- JSON.decode!(json) do
                 %{"id" => id, "type" => type, "displayName" => name, "colors" => colors} = p

                 unless Regex.match?(@id, id) and type in ["light", "dark"] do
                   raise "invalid palette #{inspect(id)} (#{inspect(type)}) in #{@source}"
                 end

                 for {role, value} <- colors,
                     not (Regex.match?(@role, role) and Regex.match?(@color, value)) do
                   raise "invalid colour #{role}: #{inspect(value)} in palette #{id}"
                 end

                 %{id: id, type: type, display_name: name, colors: Enum.sort(colors)}
               end
             end).()

  @by_id Map.new(@palettes, &{&1.id, &1})

  for {mode, id} <- @defaults do
    unless match?(%{type: ^mode}, @by_id[id]) do
      raise "default #{mode} palette #{id} is missing from #{@source}"
    end
  end

  @doc "The cookie holding the reader's renderer settings (JSON), shared with crit."
  def cookie, do: @cookie

  @doc "Default theme ids, `%{\"light\" => ..., \"dark\" => ...}`."
  def defaults, do: @defaults

  @doc "Every bundled palette: `%{id, type, display_name, colors}`."
  def palettes, do: @palettes

  @doc """
  Decodes the `crit-settings` cookie value (URI-encoded JSON, as written by the
  browser). Anything unreadable is an empty map.
  """
  def decode_settings(nil), do: %{}

  def decode_settings(value) when is_binary(value) do
    with {:ok, json} <- safe_uri_decode(value),
         {:ok, %{} = settings} <- JSON.decode(json) do
      settings
    else
      _ -> %{}
    end
  end

  def decode_settings(_), do: %{}

  defp safe_uri_decode(value) do
    {:ok, URI.decode(value)}
  rescue
    ArgumentError -> :error
  end

  @doc """
  The light and dark theme ids for the given settings. Unknown ids and ids of
  the other mode fall back to the defaults.
  """
  def pair(settings) when is_map(settings) do
    Map.new(["light", "dark"], fn mode ->
      requested = settings[mode <> "Palette"]

      case @by_id[requested] do
        %{type: ^mode, id: id} -> {mode, id}
        _ -> {mode, @defaults[mode]}
      end
    end)
  end

  def pair(_), do: @defaults

  @doc """
  The palette stylesheet for a light/dark pair. Scoped to
  `:root[data-crit-palette]` so pages without the attribute keep the
  built-in theme.
  """
  def css(%{"light" => light, "dark" => dark}) do
    dark_vars = vars(@by_id[dark], "dark")
    light_vars = vars(@by_id[light], "light")

    ":root[data-crit-palette]{#{dark_vars}}" <>
      ":root[data-crit-palette][data-theme=\"light\"]{#{light_vars}}" <>
      "@media (prefers-color-scheme: light){:root[data-crit-palette]:not([data-theme]){#{light_vars}}}"
  end

  defp vars(%{colors: colors}, scheme) do
    Enum.map_join(colors, "", fn {role, value} -> "--crit-palette-#{role}:#{value};" end) <>
      "color-scheme:#{scheme};"
  end

  @doc """
  Reply for a page's `theme_palette` event: the reader picked another theme
  (or is previewing one). Params carry `lightPalette` / `darkPalette`; the
  reply is the validated pair and its stylesheet.
  """
  def reply(params) when is_map(params) do
    pair = pair(Map.take(params, ["lightPalette", "darkPalette"]))
    %{light: pair["light"], dark: pair["dark"], css: css(pair)}
  end

  @doc """
  Everything the root layout needs to theme a page: the chosen pair and its
  stylesheet, from the raw `crit-settings` cookie value.
  """
  def for_cookie(value) do
    pair = value |> decode_settings() |> pair()
    %{light: pair["light"], dark: pair["dark"], css: css(pair)}
  end
end
