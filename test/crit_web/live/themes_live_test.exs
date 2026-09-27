defmodule CritWeb.ThemesLiveTest do
  use CritWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CritWeb.ThemePalette

  test "lists every bundled theme with its mode", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/themes")

    for p <- ThemePalette.palettes() do
      assert has_element?(view, ~s(#theme-#{p.id}[data-type="#{p.type}"]))
    end

    assert html =~ "Themes"
    assert has_element?(view, "#lineNumbersSelect[data-preview-setting=lineNumbers]")
    assert has_element?(view, "#codeOverflowSelect[data-preview-setting=codeOverflow]")
    assert has_element?(view, "#boostContrastSelect[data-preview-setting=boostContrast]")
  end

  test "applies the saved palette server-side", %{conn: conn} do
    value = %{"darkPalette" => "nord"} |> JSON.encode!() |> URI.encode(&URI.char_unreserved?/1)

    html =
      conn |> put_req_cookie("crit-settings", value) |> get(~p"/themes") |> html_response(200)

    assert html =~ ~s(data-crit-palette-dark="nord")
    assert html =~ "--crit-palette-bg:#2e3440"
  end

  test "previewing a theme replies with its stylesheet", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/themes")

    render_hook(view, "theme_palette", %{
      "lightPalette" => "min-light",
      "darkPalette" => "tokyo-night"
    })

    assert_reply(view, %{light: "min-light", dark: "tokyo-night", css: css})
    assert css =~ "--crit-palette-bg:#ffffff"
  end

  test "is not indexed", %{conn: conn} do
    html = conn |> get(~p"/themes") |> html_response(200)
    assert html =~ ~s(<meta name="robots" content="noindex, nofollow")
  end
end
