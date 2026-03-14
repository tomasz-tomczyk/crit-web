defmodule CritWeb.DashboardLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

  setup do
    Application.put_env(:crit, :selfhosted, true)

    on_exit(fn ->
      Application.delete_env(:crit, :selfhosted)
      Application.delete_env(:crit, :admin_password)
    end)
  end

  describe "mount" do
    test "redirects to / when not in selfhosted mode", %{conn: conn} do
      Application.delete_env(:crit, :selfhosted)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
    end

    test "renders stats when selfhosted", %{conn: conn} do
      review = review_fixture()
      comment_fixture(review)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Reviews"
      assert html =~ "Comments"
      assert html =~ "Files"
      assert html =~ "Activity"
    end

    test "shows review list when no password set", %{conn: conn} do
      review = review_fixture()

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "All Reviews"
      assert html =~ hd(review.files).file_path
    end
  end

  describe "with admin password" do
    setup do
      Application.put_env(:crit, :admin_password, "secret123")
    end

    test "shows login prompt when not authenticated", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Sign in to view and manage reviews"
      assert html =~ "password"
      refute html =~ "All Reviews"
    end

    test "shows review list when authenticated", %{conn: conn} do
      review = review_fixture()

      conn = conn |> init_test_session(%{admin_authenticated: true})
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "All Reviews"
      assert html =~ hd(review.files).file_path
    end

    test "shows stats even when not authenticated", %{conn: conn} do
      _review = review_fixture()

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Reviews"
      assert html =~ "Comments"
    end
  end

  describe "homepage redirect" do
    test "/ redirects to /dashboard when selfhosted", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == "/dashboard"
    end
  end

  describe "delete_review" do
    test "removes review from list", %{conn: conn} do
      review = review_fixture()

      {:ok, view, html} = live(conn, ~p"/dashboard")
      assert html =~ hd(review.files).file_path

      view
      |> element("button[phx-value-id='#{review.id}']")
      |> render_click()

      html = render(view)
      refute html =~ hd(review.files).file_path
      assert html =~ "All Reviews (0)"
    end
  end

  describe "review links" do
    test "review rows link to /r/:token", %{conn: conn} do
      review = review_fixture()

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ ~p"/r/#{review.token}"
    end
  end

  describe "empty state" do
    test "shows message when no reviews", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No reviews yet"
    end
  end
end
