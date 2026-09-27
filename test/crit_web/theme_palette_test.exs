defmodule CritWeb.ThemePaletteTest do
  use ExUnit.Case, async: true

  alias CritWeb.ThemePalette

  # As the browser writes it: encodeURIComponent(JSON.stringify(settings)).
  defp cookie(map), do: map |> JSON.encode!() |> URI.encode(&URI.char_unreserved?/1)

  test "loads every bundled palette with its foundation roles" do
    palettes = ThemePalette.palettes()
    assert length(palettes) > 50

    for p <- palettes do
      assert p.type in ["light", "dark"]
      roles = Map.new(p.colors)

      for role <-
            ~w(bg fg accent on-accent muted border surface elevated red green yellow orange purple shadow overlay) do
        assert Map.has_key?(roles, role), "#{p.id} lacks #{role}"
      end
    end

    ids = Enum.map(palettes, & &1.id)
    assert "tokyo-night" in ids
    assert "github-light-default" in ids
  end

  test "defaults match crit" do
    assert ThemePalette.defaults() == %{
             "light" => "github-light-default",
             "dark" => "tokyo-night"
           }
  end

  describe "pair/1" do
    test "keeps valid choices" do
      assert ThemePalette.pair(%{"lightPalette" => "min-light", "darkPalette" => "dracula"}) ==
               %{"light" => "min-light", "dark" => "dracula"}
    end

    test "falls back for unknown ids and ids of the other mode" do
      assert ThemePalette.pair(%{"lightPalette" => "dracula", "darkPalette" => "nope"}) ==
               ThemePalette.defaults()
    end

    test "falls back for missing or non-string values" do
      assert ThemePalette.pair(%{}) == ThemePalette.defaults()
      assert ThemePalette.pair(%{"darkPalette" => 7}) == ThemePalette.defaults()
      assert ThemePalette.pair(nil) == ThemePalette.defaults()
    end
  end

  describe "decode_settings/1" do
    test "reads the browser's URI-encoded JSON" do
      value = cookie(%{"darkPalette" => "dracula", "codeOverflow" => "wrap"})

      assert ThemePalette.decode_settings(value) == %{
               "darkPalette" => "dracula",
               "codeOverflow" => "wrap"
             }
    end

    test "treats garbage as no settings" do
      assert ThemePalette.decode_settings(nil) == %{}
      assert ThemePalette.decode_settings("%E0%A4%A") == %{}
      assert ThemePalette.decode_settings("not json") == %{}
      assert ThemePalette.decode_settings(cookie(["a list"])) == %{}
    end
  end

  describe "css/1" do
    setup do
      %{css: ThemePalette.css(%{"light" => "github-light-default", "dark" => "tokyo-night"})}
    end

    test "dark by default, light when forced or when the system is light", %{css: css} do
      [dark, light_forced, light_system] =
        Regex.run(
          ~r/\A:root\[data-crit-palette\]\{(.*?)\}:root\[data-crit-palette\]\[data-theme="light"\]\{(.*?)\}@media \(prefers-color-scheme: light\)\{:root\[data-crit-palette\]:not\(\[data-theme\]\)\{(.*?)\}\}\z/,
          css,
          capture: :all_but_first
        )

      tokyo = Enum.find(ThemePalette.palettes(), &(&1.id == "tokyo-night"))
      github = Enum.find(ThemePalette.palettes(), &(&1.id == "github-light-default"))

      assert dark =~ "--crit-palette-bg:#{Map.new(tokyo.colors)["bg"]};"
      assert dark =~ "color-scheme:dark;"
      assert light_forced == light_system
      assert light_forced =~ "--crit-palette-bg:#{Map.new(github.colors)["bg"]};"
      assert light_forced =~ "color-scheme:light;"
    end

    test "emits every role of the palette", %{css: css} do
      tokyo = Enum.find(ThemePalette.palettes(), &(&1.id == "tokyo-night"))

      for {role, value} <- tokyo.colors do
        assert css =~ "--crit-palette-#{role}:#{value};"
      end
    end
  end

  test "for_cookie/1 returns the validated pair with its stylesheet" do
    result =
      ThemePalette.for_cookie(cookie(%{"darkPalette" => "dracula", "lightPalette" => "bogus"}))

    assert result.dark == "dracula"
    assert result.light == "github-light-default"

    assert result.css ==
             ThemePalette.css(%{"light" => "github-light-default", "dark" => "dracula"})
  end

  test "reply/1 validates the requested pair and ignores other params" do
    reply =
      ThemePalette.reply(%{"darkPalette" => "dracula", "lightPalette" => "nord", "css" => "x"})

    assert reply.dark == "dracula"
    assert reply.light == "github-light-default"

    assert reply.css ==
             ThemePalette.css(%{"light" => "github-light-default", "dark" => "dracula"})
  end
end
