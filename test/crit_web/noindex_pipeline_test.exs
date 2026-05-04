defmodule CritWeb.NoindexPipelineTest do
  @moduledoc """
  Regression coverage for the router pipeline split that moved `/r/:token` out
  of the `:noindex` pipeline (see `lib/crit_web/router.ex`). Every other route
  that lives in `:noindex` must still emit `<meta name="robots" content="noindex,
  nofollow">` via the layout.
  """

  use CritWeb.ConnCase, async: true

  defp login_conn(conn) do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "noindex-#{System.unique_integer([:positive])}",
        "email" => "noindex-#{System.unique_integer([:positive])}@example.com",
        "name" => "Noindex User"
      })

    init_test_session(conn, %{user_id: user.id})
  end

  defp assert_noindex(conn, path) do
    body = conn |> get(path) |> response(200)

    assert body =~ ~s(name="robots" content="noindex, nofollow"),
           "expected noindex meta on #{path}"

    assert body =~ ~s(name="referrer" content="no-referrer"),
           "expected no-referrer meta on #{path}"
  end

  test "GET /dashboard emits noindex meta", %{conn: conn} do
    conn |> login_conn() |> assert_noindex(~p"/dashboard")
  end

  test "GET /settings emits noindex meta", %{conn: conn} do
    conn |> login_conn() |> assert_noindex(~p"/settings")
  end

  test "GET /auth/cli/success goes through the :noindex pipeline (header)", %{conn: conn} do
    conn = get(conn, ~p"/auth/cli/success")
    assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
  end
end
