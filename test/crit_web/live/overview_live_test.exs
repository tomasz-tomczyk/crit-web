defmodule CritWeb.OverviewLiveTest do
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

  defp login_user(conn) do
    {conn, _user} = login_user_with_record(conn)
    conn
  end

  defp login_user_with_record(conn) do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "test_uid_#{System.unique_integer()}",
        "email" => "test@example.com",
        "name" => "Test User"
      })

    {init_test_session(conn, %{user_id: user.id}), user}
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

  describe "with admin password" do
    setup do
      Application.put_env(:crit, :admin_password, "secret123")
    end

    test "shows login prompt when not authenticated", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "Sign in to view and manage reviews"
      refute html =~ "All Reviews"
    end

    test "shows password form when no OAuth configured", %{conn: conn} do
      without_oauth(%{})

      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "password"
      refute html =~ "Sign in with OAuth"
    end

    test "shows OAuth button when OAuth configured", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "Sign in with OAuth"
      refute html =~ "login-form"
    end

    test "shows review list when authenticated via OAuth", %{conn: conn} do
      review = review_fixture()
      conn = login_user(conn)

      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "All Reviews"
      assert html =~ hd(review.files).file_path
    end

    test "shows stats even when not authenticated", %{conn: conn} do
      _review = review_fixture()

      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "Reviews"
      assert html =~ "Comments"
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

  describe "with admin password and no OAuth" do
    setup do
      Application.put_env(:crit, :admin_password, "secret123")
    end

    test "authenticated via password session shows reviews", %{conn: conn} do
      without_oauth(%{})
      review = review_fixture()

      conn = init_test_session(conn, %{admin_authenticated: true})
      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "All Reviews"
      assert html =~ hd(review.files).file_path
    end

    test "unauthenticated password session shows login form", %{conn: conn} do
      without_oauth(%{})

      {:ok, _view, html} = live(conn, ~p"/overview")

      assert html =~ "password"
      refute html =~ "All Reviews"
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
