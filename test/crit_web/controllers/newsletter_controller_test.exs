defmodule CritWeb.NewsletterControllerTest do
  use CritWeb.ConnCase, async: false

  setup do
    orig = Application.get_env(:crit, :selfhosted)

    on_exit(fn ->
      if is_nil(orig),
        do: Application.delete_env(:crit, :selfhosted),
        else: Application.put_env(:crit, :selfhosted, orig)
    end)

    :ok
  end

  test "serves newsletter HTML on hosted instances", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    conn = get(conn, ~p"/newsletter/2026-09-first-update")
    assert response(conn, 200) =~ "Story mode, a new renderer, and finish hooks"
    assert response(conn, 200) =~ ~s(src="https://assets.crit.md/newsletter/2026-09-first-update/)
    refute response(conn, 200) =~ "{{{ pm:unsubscribe }}}"
  end

  test "serves newsletter images on hosted instances", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    conn = get(conn, ~p"/newsletter/2026-09-first-update/images/crit-logo.png")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
  end

  test "404s newsletter on selfhosted instances", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, true)

    conn = get(conn, ~p"/newsletter/2026-09-first-update")
    assert response(conn, 404)
  end

  test "404s unknown slug", %{conn: conn} do
    Application.put_env(:crit, :selfhosted, false)

    conn = get(conn, ~p"/newsletter/does-not-exist")
    assert response(conn, 404)
  end
end
