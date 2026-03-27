defmodule CritWeb.Plugs.AuthTest do
  use CritWeb.ConnCase, async: true

  alias CritWeb.Plugs.Auth
  alias Crit.Accounts

  @oauth_params %{
    "sub" => "55443322",
    "name" => "Test User",
    "email" => "test@example.com",
    "picture" => nil
  }

  test "assigns nil current_user when no session user_id" do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> Auth.call([])

    assert conn.assigns[:current_user] == nil
  end

  test "assigns current_user when valid user_id in session" do
    {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)

    conn =
      build_conn()
      |> init_test_session(%{"user_id" => user.id})
      |> Auth.call([])

    assert conn.assigns[:current_user].id == user.id
  end

  test "clears stale user_id from session and assigns nil" do
    conn =
      build_conn()
      |> init_test_session(%{"user_id" => "00000000-0000-0000-0000-000000000000"})
      |> Auth.call([])

    assert conn.assigns[:current_user] == nil
    assert get_session(conn, "user_id") == nil
  end
end
