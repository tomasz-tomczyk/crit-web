defmodule CritWeb.ReviewsLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.AccountsFixtures
  import Crit.ReviewsFixtures

  defp login(conn, user) do
    init_test_session(conn, %{user_id: user.id})
  end

  describe "unauthenticated" do
    test "redirects to login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/auth/login" <> _}}} =
               live(conn, ~p"/reviews")
    end
  end

  describe "mount" do
    test "renders the reviews page for an authenticated user", %{conn: conn} do
      user = oauth_user_fixture(%{"name" => "Test User"})
      conn = login(conn, user)
      {:ok, _view, html} = live(conn, ~p"/reviews")

      assert html =~ "My reviews"
    end

    test "shows reviews belonging to the user", %{conn: conn} do
      user = oauth_user_fixture(%{"name" => "Review Owner"})
      _review = review_fixture(user_id: user.id)

      conn = login(conn, user)
      {:ok, _view, html} = live(conn, ~p"/reviews")

      assert html =~ "test.md"
    end

    test "does not show reviews from other users", %{conn: conn} do
      other = oauth_user_fixture(%{"name" => "Other"})
      _review = review_fixture(user_id: other.id)

      user = oauth_user_fixture(%{"name" => "Viewer"})
      conn = login(conn, user)
      {:ok, _view, html} = live(conn, ~p"/reviews")

      # The review table should be empty or not contain the other user's file
      refute html =~ "test.md" or html =~ "Page 1 of 0"
    end
  end
end
