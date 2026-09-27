defmodule CritWeb.ReviewLiveThemePaletteTest do
  use CritWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

  alias CritWeb.ThemePalette

  defp settings_cookie(conn, settings) do
    value = settings |> JSON.encode!() |> URI.encode(&URI.char_unreserved?/1)
    put_req_cookie(conn, "crit-settings", value)
  end

  setup do
    %{review: review_fixture()}
  end

  test "the review page renders the default palette before any JS runs", %{
    conn: conn,
    review: review
  } do
    html = conn |> get(~p"/r/#{review.token}") |> html_response(200)
    doc = LazyHTML.from_document(html)

    root = LazyHTML.query(doc, "html")
    assert LazyHTML.attribute(root, "data-crit-palette") == [""]
    assert LazyHTML.attribute(root, "data-crit-palette-dark") == ["tokyo-night"]
    assert LazyHTML.attribute(root, "data-crit-palette-light") == ["github-light-default"]

    css = doc |> LazyHTML.query("style#crit-palette") |> LazyHTML.text()
    assert css =~ ThemePalette.css(ThemePalette.defaults())
  end

  test "the saved palette comes from the crit-settings cookie", %{conn: conn, review: review} do
    html =
      conn
      |> settings_cookie(%{
        "darkPalette" => "dracula",
        "lightPalette" => "min-light",
        "codeOverflow" => "wrap"
      })
      |> get(~p"/r/#{review.token}")
      |> html_response(200)

    doc = LazyHTML.from_document(html)
    root = LazyHTML.query(doc, "html")
    assert LazyHTML.attribute(root, "data-crit-palette-dark") == ["dracula"]
    assert LazyHTML.attribute(root, "data-crit-palette-light") == ["min-light"]

    css = doc |> LazyHTML.query("style#crit-palette") |> LazyHTML.text()
    assert css =~ ThemePalette.css(%{"light" => "min-light", "dark" => "dracula"})
  end

  test "rendered markdown gets the display settings before first paint", %{
    conn: conn,
    review: review
  } do
    html = conn |> get(~p"/r/#{review.token}") |> html_response(200)
    assert html =~ ~s(data-line-numbers="on")
    assert html =~ ~s(data-code-overflow="scroll")

    html =
      build_conn()
      |> settings_cookie(%{"lineNumbers" => "off", "codeOverflow" => "wrap"})
      |> get(~p"/r/#{review.token}")
      |> html_response(200)

    assert html =~ ~s(data-line-numbers="off")
    assert html =~ ~s(data-code-overflow="wrap")
  end

  test "an invalid cookie falls back to the defaults", %{conn: conn, review: review} do
    html =
      conn
      |> put_req_cookie("crit-settings", "%7Bbroken")
      |> get(~p"/r/#{review.token}")
      |> html_response(200)

    assert html =~ ~s(data-crit-palette-dark="tokyo-night")
  end

  test "theme_palette replies with the validated pair and stylesheet", %{
    conn: conn,
    review: review
  } do
    {:ok, view, _html} = live(conn, ~p"/r/#{review.token}")

    render_hook(view, "theme_palette", %{"darkPalette" => "nord", "lightPalette" => "dracula"})

    assert_reply(view, %{
      dark: "nord",
      light: "github-light-default",
      css: css
    })

    assert css == ThemePalette.css(%{"light" => "github-light-default", "dark" => "nord"})
  end

  test "pages other than reviews keep the built-in theme", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    refute html =~ "data-crit-palette"
    refute html =~ ~s(id="crit-palette")
    refute html =~ "data-line-numbers"
  end
end
