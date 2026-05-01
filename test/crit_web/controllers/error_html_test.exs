defmodule CritWeb.ErrorHTMLTest do
  use CritWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html with headline and recovery links" do
    html = render_to_string(CritWeb.ErrorHTML, "404", "html", current_scope: nil, flash: %{})

    assert html =~ "This page was"
    assert html =~ "not found"
    assert html =~ "Back to home"
    assert html =~ "Get started"
  end

  test "renders 500.html" do
    assert render_to_string(CritWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
