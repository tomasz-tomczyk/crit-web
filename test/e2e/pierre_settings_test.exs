# Code display and theme settings (crit's pierre-settings spec, for the
# settings that apply to crit-web's files and preview modes). They live in the
# `crit-settings` cookie with crit's key names; the server applies the chosen
# palette before first paint.

defmodule CritWeb.E2E.PierreSettingsTest do
  use CritWeb.E2ECase, async: true

  defp pre(page, path), do: page |> code_file(path) |> Locator.locator("pre") |> Locator.first()

  defp open_settings(page) do
    Locator.click!(Page.locator(page, "#settingsToggle"))
    Expect.to_be_visible!(Page.locator(page, "#settingsOverlay.active"))
  end

  defp settings_cookie(page) do
    cookie =
      page
      |> Page.context()
      |> BrowserContext.cookies!()
      |> Enum.find(&(&1.name == "crit-settings"))

    if cookie, do: cookie.value |> URI.decode() |> JSON.decode!(), else: %{}
  end

  # `new AxeBuilder({ page }).include(...).withRules([...]).analyze()` from
  # @axe-core/playwright: inject axe-core's source and run it on the page.
  defp axe_violations(page, include, rules) do
    unless Page.evaluate!(page, "() => typeof window.axe === 'object'") do
      inject_axe(page)
    end

    result =
      Page.evaluate!(
        page,
        """
        ([include, rules]) => axe.run({ include }, { runOnly: { type: "rule", values: rules } })
        """,
        [include, rules]
      )

    assert is_map(result)
    result["violations"]
  end

  describe "Code display and theme settings" do
    setup %{request: request, page: page} do
      review =
        create_review(request,
          files: [
            %{
              path: "server.go",
              content:
                "package main\n\n// " <>
                  String.duplicate("long ", 60) <> "comment\nfunc main() {}\n"
            },
            %{
              path: "plan.md",
              content:
                "# Plan\n\n```go\nfunc main() {}\n// " <>
                  String.duplicate("wide ", 80) <> "\n```\n\n```mermaid\ngraph TD; A-->B;\n```\n"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      Page.emulate_media!(page, color_scheme: :dark)
      load_review(page, review.token)
      Expect.to_be_visible!(code_line(page, "server.go", 1))
      %{token: review.token, delete_token: review.delete_token}
    end

    test "files mode offers the settings that apply to a file review", %{page: page} do
      open_settings(page)

      for id <-
            ~w(lineNumbersSelect lightPaletteSelect darkPaletteSelect boostContrastSelect codeOverflowSelect) do
        Expect.to_be_visible!(Page.locator(page, "#" <> id))
      end

      # Diff-only settings have no surface in crit-web.
      for id <- ~w(inlineDiffSelect changeIndicatorsSelect unchangedContextSelect) do
        Expect.to_have_count!(Page.locator(page, "#" <> id), 0)
      end

      Expect.poll!(
        fn -> Locator.count!(Page.locator(page, "#darkPaletteSelect option")) end,
        &assert(&1 > 20)
      )

      Expect.to_have_attribute!(
        Page.get_by_role(page, :link, name: "Preview all themes"),
        "href",
        "/themes"
      )
    end

    test "a dark theme re-themes the page, code and fences, and persists", %{
      page: page,
      token: token
    } do
      html = Page.locator(page, "html")
      Expect.to_have_attribute!(html, "data-crit-palette", "tokyo-night")

      token_style = fn ->
        page
        |> code_line("server.go", 1)
        |> Locator.locator("span[style]")
        |> Locator.first()
        |> Locator.get_attribute!("style")
      end

      before = token_style.()

      open_settings(page)
      dark = Page.locator(page, "#darkPaletteSelect")
      Locator.select_option!(dark, "nord")
      Expect.to_be_enabled!(dark)
      Expect.to_have_attribute!(html, "data-crit-palette", "nord")
      Expect.to_have_attribute!(html, "data-crit-palette-dark", "nord")
      Expect.poll!(token_style, &refute(&1 == before))

      fence =
        page
        |> Page.locator(~s(.line-block[data-file-path="plan.md"] code.crit-code span[style]))
        |> Locator.first()

      Expect.poll!(
        fn -> Locator.get_attribute!(fence, "style") end,
        &assert(&1 =~ "--diffs-token-dark:")
      )

      assert Page.evaluate!(page, """
             () => getComputedStyle(document.documentElement).getPropertyValue("--crit-palette-bg").trim()
             """) == "#2e3440"

      assert settings_cookie(page)["darkPalette"] == "nord"

      # Server-rendered on the next visit: no flash of the default theme.
      load_review(page, token)
      Expect.to_have_attribute!(html, "data-crit-palette-dark", "nord")
      css = Locator.text_content!(Page.locator(page, "#crit-palette"))
      assert css =~ "--crit-palette-bg:#2e3440"
      open_settings(page)
      Expect.to_have_value!(Page.locator(page, "#darkPaletteSelect"), "nord")
    end

    test "paired palettes follow explicit and system mode", %{page: page} do
      open_settings(page)
      Locator.select_option!(Page.locator(page, "#darkPaletteSelect"), "nord")
      Expect.to_be_enabled!(Page.locator(page, "#darkPaletteSelect"))
      Locator.select_option!(Page.locator(page, "#lightPaletteSelect"), "catppuccin-latte")
      Expect.to_be_enabled!(Page.locator(page, "#lightPaletteSelect"))
      html = Page.locator(page, "html")
      Expect.to_have_attribute!(html, "data-crit-palette", "nord")
      Locator.click!(Page.locator(page, ~s([data-settings-theme="light"])))
      Expect.to_have_attribute!(html, "data-crit-palette", "catppuccin-latte")
      Locator.click!(Page.locator(page, ~s([data-settings-theme="system"])))
      Expect.to_have_attribute!(html, "data-crit-palette", "nord")
      Page.emulate_media!(page, color_scheme: :light)
      Expect.to_have_attribute!(html, "data-crit-palette", "catppuccin-latte")
      # The stylesheet itself switches halves with the OS: no script needed.
      bg =
        Page.evaluate!(page, """
        () => getComputedStyle(document.documentElement).getPropertyValue("--crit-palette-bg").trim()
        """)

      assert bg == "#eff1f5"
    end

    test "line numbers can be hidden and the setting survives a reload", %{
      page: page,
      token: token
    } do
      open_settings(page)
      Locator.select_option!(Page.locator(page, "#lineNumbersSelect"), "off")
      Keyboard.press!(Page.keyboard(page), "Escape")
      Expect.to_have_attribute!(pre(page, "server.go"), "data-disable-line-numbers", "")
      load_review(page, token)
      Expect.to_have_attribute!(pre(page, "server.go"), "data-disable-line-numbers", "")
      open_settings(page)
      Expect.to_have_value!(Page.locator(page, "#lineNumbersSelect"), "off")
      Locator.select_option!(Page.locator(page, "#lineNumbersSelect"), "on")
      Keyboard.press!(Page.keyboard(page), "Escape")
      Expect.not_to_have_attribute!(pre(page, "server.go"), "data-disable-line-numbers", "")
    end

    test "long code lines scroll or wrap", %{page: page} do
      Expect.to_have_attribute!(pre(page, "server.go"), "data-overflow", "scroll")

      height = fn ->
        Locator.evaluate!(
          code_line(page, "server.go", 3),
          "el => el.getBoundingClientRect().height"
        )
      end

      single = height.()
      open_settings(page)
      Locator.select_option!(Page.locator(page, "#codeOverflowSelect"), "wrap")
      Keyboard.press!(Page.keyboard(page), "Escape")
      Expect.to_have_attribute!(pre(page, "server.go"), "data-overflow", "wrap")
      Expect.poll!(height, &assert(&1 > single * 1.5))
      assert settings_cookie(page)["codeOverflow"] == "wrap"
    end

    test "syntax contrast raises faint theme colours", %{page: page} do
      open_settings(page)
      Locator.select_option!(Page.locator(page, "#lightPaletteSelect"), "min-light")
      Expect.to_be_enabled!(Page.locator(page, "#lightPaletteSelect"))
      Locator.click!(Page.locator(page, ~s([data-settings-theme="light"])))
      Keyboard.press!(Page.keyboard(page), "Escape")
      # Min Light's comments are #c2c3c5 (1.76:1 on white) as designed.
      comment =
        page |> code_line("server.go", 3) |> Locator.locator("span[style]") |> Locator.first()

      Expect.to_have_css!(comment, "color", "rgb(194, 195, 197)")
      open_settings(page)
      Locator.select_option!(Page.locator(page, "#boostContrastSelect"), "on")
      Expect.to_be_enabled!(Page.locator(page, "#boostContrastSelect"))

      Expect.poll!(
        fn ->
          [r, _g, b] =
            page
            |> code_line("server.go", 3)
            |> Locator.locator("span[style]")
            |> Locator.first()
            |> Locator.evaluate!("el => getComputedStyle(el).color.match(/\\d+/g).map(Number)")

          r < 120 and abs(r - b) < 20
        end,
        &assert(&1 == true)
      )
    end

    test "the comment + follows the theme accent", %{page: page} do
      open_settings(page)
      Locator.select_option!(Page.locator(page, "#darkPaletteSelect"), "monokai")
      Expect.to_be_enabled!(Page.locator(page, "#darkPaletteSelect"))
      Keyboard.press!(Page.keyboard(page), "Escape")
      # Hover + visible + color must be atomic: a re-render between hover and
      # the color read drops the button (same flake as code-files drag test).
      Expect.to_pass!(
        fn ->
          hover_code_line(page, "server.go", 4)
          utility = Locator.locator(code_file(page, "server.go"), "[data-utility-button]")
          Expect.to_be_visible!(utility, timeout: 2_000)

          assert Locator.evaluate!(utility, """
                 (el) => {
                   const probe = document.createElement("span");
                   probe.style.color = getComputedStyle(document.documentElement).getPropertyValue("--crit-palette-accent");
                   return getComputedStyle(el).backgroundColor === probe.style.color;
                 }
                 """) == true
        end,
        timeout: 20_000
      )
    end

    test "review chrome and settings keep contrast in both modes", %{page: page} do
      open_settings(page)

      Page.add_style_tag!(page,
        content: "* { transition: none !important; animation: none !important; }"
      )

      for mode <- ["dark", "light"] do
        Locator.click!(Page.locator(page, ~s([data-settings-theme="#{mode}"])))

        violations =
          axe_violations(page, [".crit-header", "#settingsOverlay"], ["color-contrast"])

        assert violations == []
      end
    end

    test "a worker failure still paints highlighted code", %{page: page, token: token} do
      # A string without an argument is the script's source, not a function to
      # call: the statement form of the spec's arrow function.
      Page.add_init_script!(page, """
      window.Worker = class { constructor() { throw new Error("Worker blocked for resilience test"); } };
      """)

      load_review(page, token)
      Expect.to_contain_text!(code_line(page, "server.go", 4), "func main")
      # Highlighted without workers: Shiki colors "func" and "main" differently.
      Expect.poll!(
        fn ->
          page
          |> code_line("server.go", 4)
          |> Locator.locator("span[style]")
          |> Locator.evaluate_all!(
            "spans => new Set(spans.map((s) => getComputedStyle(s).color)).size"
          )
        end,
        &assert(&1 > 1)
      )
    end
  end

  describe "Display settings in rendered markdown" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{
              path: "plan.md",
              content:
                "# Plan\n\n```go\n// " <>
                  String.duplicate("wide ", 80) <> "\nfunc main() {}\n```\n"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "line numbers hide in the markdown gutter, which keeps its + and width", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      num = Page.locator(page, ~s(.line-block[data-start-line="1"] .line-num))
      Expect.to_be_visible!(num)

      gutter_width = fn ->
        page
        |> Page.locator(~s(.line-block[data-start-line="1"] .line-gutter))
        |> Locator.evaluate!("el => el.getBoundingClientRect().width")
      end

      before = gutter_width.()
      open_settings(page)
      Expect.to_have_text!(Page.locator(page, ~s(label[for="lineNumbersSelect"])), "Line numbers")
      Locator.select_option!(Page.locator(page, "#lineNumbersSelect"), "off")
      Keyboard.press!(Page.keyboard(page), "Escape")
      Expect.to_have_attribute!(Page.locator(page, "html"), "data-line-numbers", "off")
      Expect.to_be_hidden!(num)
      assert gutter_width.() == before
      # Commenting from the gutter still works.
      Locator.click!(Page.locator(page, ~s(.line-block[data-start-line="1"] .line-gutter)))
      Expect.to_be_visible!(Page.locator(page, ".comment-form textarea"))
      # Server-rendered on the next load.
      load_review(page, token)
      Expect.to_have_attribute!(Page.locator(page, "html"), "data-line-numbers", "off")
      Expect.to_be_hidden!(num)
    end

    test "long lines in markdown code blocks wrap with the code setting", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      wide =
        page |> Page.locator(".line-content.code-line") |> Locator.filter(has_text: "wide wide")

      height = fn -> Locator.evaluate!(wide, "el => el.getBoundingClientRect().height") end
      single = height.()
      Expect.to_have_css!(wide, "white-space", "pre")
      open_settings(page)
      Locator.select_option!(Page.locator(page, "#codeOverflowSelect"), "wrap")
      Keyboard.press!(Page.keyboard(page), "Escape")
      Expect.to_have_attribute!(Page.locator(page, "html"), "data-code-overflow", "wrap")
      Expect.to_have_css!(wide, "white-space", "pre-wrap")
      Expect.poll!(height, &assert(&1 > single * 1.5))
    end
  end

  describe "Theme settings in preview mode" do
    test "offers only the theme choice and applies it", %{page: page, request: request} do
      review = create_preview_review(request)

      try do
        load_preview(page, review.token)
        open_settings(page)
        Expect.to_be_visible!(Page.locator(page, "#darkPaletteSelect"))
        Expect.to_be_visible!(Page.locator(page, "#lightPaletteSelect"))
        Expect.to_have_count!(Page.locator(page, "#lineNumbersSelect"), 0)
        Expect.to_have_count!(Page.locator(page, "#codeOverflowSelect"), 0)
        Expect.to_have_count!(Page.locator(page, ".settings-theme-preview-link"), 0)
        Locator.click!(Page.locator(page, ~s([data-settings-theme="dark"])))
        Locator.select_option!(Page.locator(page, "#darkPaletteSelect"), "dracula")
        Expect.to_have_attribute!(Page.locator(page, "html"), "data-crit-palette", "dracula")

        assert Page.evaluate!(page, """
               () => getComputedStyle(document.documentElement).getPropertyValue("--crit-bg-page").trim()
               """) ==
                 Page.evaluate!(page, """
                 () => getComputedStyle(document.documentElement).getPropertyValue("--crit-palette-bg").trim()
                 """)
      after
        delete_review(request, review.delete_token)
      end
    end
  end
end
