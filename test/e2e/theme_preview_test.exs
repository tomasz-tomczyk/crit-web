defmodule CritWeb.E2E.ThemePreviewTest do
  use CritWeb.E2ECase, async: true

  defp crit_settings(context) do
    cookie = Enum.find(BrowserContext.cookies!(context), &(&1.name == "crit-settings"))
    Jason.decode!(URI.decode(cookie.value))
  end

  # /themes: flip through the bundled themes on fixed samples (crit's
  # theme-preview spec, on crit-web's page).
  describe "Theme preview page" do
    test "switches themes with the keyboard and saves the choice", %{page: page, context: context} do
      Page.goto!(page, "/themes#dark/dracula")
      html = Page.locator(page, "html")
      Expect.to_have_attribute!(html, "data-crit-palette", "dracula")
      Expect.to_have_attribute!(html, "data-theme", "dark")
      # The sample is a real Pierre render in the chosen theme, with a comment.
      Expect.to_be_visible!(Locator.first(Page.locator(page, "#previewCode [data-line]")))
      Expect.to_be_visible!(Page.locator(page, "#previewCode .comment-card"))

      Expect.to_be_visible!(
        Locator.first(Page.locator(page, "#themeSamples code.crit-code span[style]"))
      )

      Locator.focus!(Page.locator(page, "#themeList"))
      Keyboard.press!(Page.keyboard(page), "ArrowDown")
      Expect.not_to_have_attribute!(html, "data-crit-palette", "dracula")
      next = Locator.get_attribute!(html, "data-crit-palette")
      Expect.to_have_url!(page, ~r/#dark\/#{Regex.escape(next)}$/)
      Expect.to_have_attribute!(Page.locator(page, "#theme-#{next}"), "aria-selected", "true")

      Locator.click!(Page.locator(page, "#useTheme"))
      Expect.to_be_disabled!(Page.locator(page, "#useTheme"))
      assert crit_settings(context)["darkPalette"] == next

      # The saved theme is applied server-side on the next page load.
      Page.goto!(page, "/themes")
      Expect.to_have_attribute!(html, "data-crit-palette-dark", next)

      assert Locator.text_content!(Page.locator(page, "#crit-palette")) =~
               "--crit-palette-bg:"

      Expect.to_have_attribute!(html, "data-crit-palette-dark", next)
    end

    test "light and dark lists only offer their own themes", %{page: page} do
      Page.goto!(page, "/themes#light/github-light-default")
      Expect.to_have_attribute!(Page.locator(page, "html"), "data-theme", "light")
      Expect.to_be_visible!(Page.locator(page, "#theme-github-light-default"))
      Expect.to_be_hidden!(Page.locator(page, "#theme-dracula"))
      Locator.click!(Page.locator(page, ~s([data-preview-mode="dark"])))
      Expect.to_have_attribute!(Page.locator(page, "html"), "data-theme", "dark")
      Expect.to_be_visible!(Page.locator(page, "#theme-dracula"))
      Expect.to_be_hidden!(Page.locator(page, "#theme-github-light-default"))

      Expect.to_have_attribute!(
        Page.locator(page, ~s([data-preview-mode="dark"])),
        "aria-pressed",
        "true"
      )
    end

    test "follows and edits the display settings", %{page: page, context: context} do
      Page.goto!(page, "/themes#dark/tokyo-night")
      pre = Locator.first(Page.locator(page, "#previewCode pre"))
      Expect.to_be_visible!(pre)
      Expect.not_to_have_attribute!(pre, "data-disable-line-numbers", "")
      Locator.select_option!(Page.locator(page, "#lineNumbersSelect"), "off")

      Expect.to_have_attribute!(
        Locator.first(Page.locator(page, "#previewCode pre")),
        "data-disable-line-numbers",
        ""
      )

      Locator.select_option!(Page.locator(page, "#codeOverflowSelect"), "wrap")

      Expect.to_have_attribute!(
        Locator.first(Page.locator(page, "#previewCode pre")),
        "data-overflow",
        "wrap"
      )

      settings = crit_settings(context)
      assert %{"lineNumbers" => "off", "codeOverflow" => "wrap"} = settings
      Page.reload!(page)

      Expect.to_have_attribute!(
        Locator.first(Page.locator(page, "#previewCode pre")),
        "data-disable-line-numbers",
        ""
      )
    end

    test "boosting syntax contrast darkens faint theme colours", %{page: page} do
      Page.goto!(page, "/themes#light/min-light")
      # Min Light's comments are #c2c3c5 (1.76:1 on white) as designed.
      comment = fn ->
        page
        |> Page.locator("#previewCode [data-line] span",
          has_text: "authMiddleware checks the API"
        )
        |> Locator.first()
      end

      Expect.to_have_css!(comment.(), "color", "rgb(194, 195, 197)")
      Locator.select_option!(Page.locator(page, "#boostContrastSelect"), "on")

      Expect.poll!(
        fn ->
          [r, _g, b | _] =
            Locator.evaluate!(
              comment.(),
              "(el) => getComputedStyle(el).color.match(/\\d+/g).map(Number)"
            )

          r < 120 and abs(r - b) < 20
        end,
        &assert(&1 == true)
      )

      Locator.select_option!(Page.locator(page, "#boostContrastSelect"), "off")
      Expect.to_have_css!(comment.(), "color", "rgb(194, 195, 197)")
    end

    test "is not indexed", %{page: page} do
      Page.goto!(page, "/themes")

      Expect.to_have_attribute!(
        Page.locator(page, ~s(meta[name="robots"])),
        "content",
        ~r/noindex/
      )
    end
  end
end
