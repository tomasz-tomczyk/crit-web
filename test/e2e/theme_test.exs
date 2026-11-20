defmodule CritWeb.E2E.ThemeTest do
  use CritWeb.E2ECase, async: true

  describe "Theme Switching" do
    setup %{page: page, request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)

      # Clear theme preference
      Page.goto!(page, "/")

      Page.evaluate!(page, """
      () => {
        localStorage.removeItem("phx:theme");
      }
      """)

      %{token: review.token, delete_token: review.delete_token}
    end

    test "theme buttons set data-theme on <html> (light, dark, system)", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      open_settings_pane(page)

      html = Page.locator(page, "html")

      Locator.click!(Page.locator(page, ~s([data-settings-theme="light"])))
      Expect.to_have_attribute!(html, "data-theme", "light")

      Locator.click!(Page.locator(page, ~s([data-settings-theme="dark"])))
      Expect.to_have_attribute!(html, "data-theme", "dark")

      # System mode removes the explicit attribute entirely
      Locator.click!(Page.locator(page, ~s([data-settings-theme="system"])))
      Expect.poll!(fn -> Locator.get_attribute!(html, "data-theme") end, &assert(&1 == nil))
    end

    test "theme persists across page reload", %{page: page, token: token} do
      load_review(page, token)
      open_settings_pane(page)

      Locator.click!(Page.locator(page, ~s([data-settings-theme="dark"])))
      Expect.to_have_attribute!(Page.locator(page, "html"), "data-theme", "dark")

      # Reload the page
      load_review(page, token)

      # Should still be dark
      Expect.to_have_attribute!(Page.locator(page, "html"), "data-theme", "dark")
    end

    test "theme pill indicator moves when theme changes", %{page: page, token: token} do
      load_review(page, token)
      open_settings_pane(page)

      indicator = Page.locator(page, "#settingsThemeIndicator")
      left = fn -> Locator.evaluate!(indicator, "el => parseFloat(el.style.left)") end

      # Switch to light: indicator should move
      Locator.click!(Page.locator(page, ~s([data-settings-theme="light"])))
      # toBeCloseTo(x, 0): |actual - x| < 0.5
      Expect.poll!(left, &assert(is_number(&1) and abs(&1 - 33.333) < 0.5))

      # Switch to dark: indicator should move further
      Locator.click!(Page.locator(page, ~s([data-settings-theme="dark"])))
      Expect.poll!(left, &assert(is_number(&1) and abs(&1 - 66.666) < 0.5))
    end
  end
end
