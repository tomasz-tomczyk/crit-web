defmodule CritWeb.OverviewLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.AccountsFixtures
  import Crit.ReviewsFixtures

  setup %{conn: conn} do
    Application.put_env(:crit, :selfhosted, true)

    on_exit(fn ->
      Application.delete_env(:crit, :selfhosted)
    end)

    # /overview only renders the review list for authenticated users in
    # selfhost+local-auth mode. Sign in for tests that exercise that surface.
    user = user_fixture()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  defp without_oauth(ctx) do
    original = Application.get_env(:crit, :oauth_provider)
    Application.delete_env(:crit, :oauth_provider)

    on_exit(fn ->
      if original,
        do: Application.put_env(:crit, :oauth_provider, original),
        else: Application.delete_env(:crit, :oauth_provider)
    end)

    ctx
  end

  describe "mount" do
    test "redirects to / when not in selfhosted mode", %{conn: conn} do
      Application.delete_env(:crit, :selfhosted)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/overview")
    end

    test "renders stats when selfhosted", %{conn: conn} do
      review = review_fixture()
      comment_fixture(review)

      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "Reviews"
      assert html =~ "Comments"
      assert html =~ "Files"
      assert html =~ "Activity"
    end

    test "shows all reviews regardless of user", %{conn: conn} do
      without_oauth(%{})

      review = review_fixture()
      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "All Reviews"
      assert html =~ hd(review.files).file_path
    end
  end

  describe "overview empty state" do
    setup :without_oauth

    test "shows empty message when no reviews", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ ~r/All Reviews[^<]*<[^>]*>0</
      assert html =~ "No reviews yet"
    end
  end

  describe "overview page title" do
    test "page title is Admin - Crit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/overview")

      assert page_title(view) =~ "Overview - Crit"
    end
  end

  describe "overview with review metadata" do
    setup :without_oauth

    test "shows comment and file counts for reviews", %{conn: conn} do
      review = review_fixture()
      comment_fixture(review)

      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ ~r{>\s*1\s*</span>\s*comment}
      assert html =~ ~r{>\s*1\s*</span>\s*file}
    end

    test "review links to /r/:token", %{conn: conn} do
      review = review_fixture()

      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ ~p"/r/#{review.token}"
    end
  end
end
