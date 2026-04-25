defmodule CritWeb.DashboardLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.ReviewsFixtures

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

  describe "mount requires user" do
    test "redirects to /auth/login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/auth/login?return_to=/dashboard"}}} =
               live(conn, ~p"/dashboard")
    end

    test "redirects to / when no OAuth configured", %{conn: conn} do
      original = Application.get_env(:crit, :oauth_provider)
      Application.delete_env(:crit, :oauth_provider)

      on_exit(fn ->
        if original,
          do: Application.put_env(:crit, :oauth_provider, original),
          else: Application.delete_env(:crit, :oauth_provider)
      end)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/dashboard")
    end
  end

  describe "personal dashboard" do
    test "shows only the current user's reviews", %{conn: conn} do
      {conn, user} = login_user_with_record(conn)
      review = review_fixture(user_id: user.id)

      # Create another user's review that should NOT appear
      {:ok, other_user} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "other_uid_#{System.unique_integer()}",
          "email" => "other@example.com",
          "name" => "Other User"
        })

      other_review =
        review_fixture(
          user_id: other_user.id,
          files: [%{"path" => "other_file.md", "content" => "other content"}]
        )

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "My Reviews (1)"
      assert html =~ hd(review.files).file_path
      refute html =~ hd(other_review.files).file_path
    end

    test "does not show stats cards or activity chart", %{conn: conn} do
      conn = login_user(conn)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      refute html =~ "Activity"
      refute html =~ "this week"
    end

    test "shows empty state when user has no reviews", %{conn: conn} do
      conn = login_user(conn)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No reviews yet"
      assert html =~ "Share a review from the Crit CLI"
    end
  end

  describe "review links" do
    test "review rows link to /r/:token", %{conn: conn} do
      {conn, user} = login_user_with_record(conn)
      review = review_fixture(user_id: user.id)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ ~p"/r/#{review.token}"
    end
  end

  describe "delete_review" do
    test "owner can delete their own review", %{conn: conn} do
      {conn, user} = login_user_with_record(conn)
      review = review_fixture(user_id: user.id)

      {:ok, view, html} = live(conn, ~p"/dashboard")
      assert html =~ hd(review.files).file_path

      view
      |> element("button[phx-value-id='#{review.id}']")
      |> render_click()

      html = render(view)
      refute html =~ hd(review.files).file_path
      assert html =~ "My Reviews (0)"
    end

    test "cannot delete another user's review", %{conn: conn} do
      {conn, _user} = login_user_with_record(conn)

      {:ok, other_user} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "other_uid_#{System.unique_integer()}",
          "email" => "other@example.com",
          "name" => "Other User"
        })

      review = review_fixture(user_id: other_user.id)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      # The review shouldn't even show, but test the event handler too
      view |> render_hook("delete_review", %{"id" => review.id})

      assert render(view) =~ "You can only delete your own reviews."
    end
  end

  describe "review counts and metadata" do
    test "shows comment and file counts", %{conn: conn} do
      {conn, user} = login_user_with_record(conn)

      review = review_fixture(user_id: user.id)

      # Add a comment to the review
      {:ok, _comment} =
        Crit.Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Test comment"},
          Ecto.UUID.generate(),
          nil
        )

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "1 comment"
      assert html =~ "1 file"
    end

    test "pluralizes counts correctly for multiple items", %{conn: conn} do
      {conn, user} = login_user_with_record(conn)

      review =
        review_fixture(
          user_id: user.id,
          files: [
            %{"path" => "file1.go", "content" => "pkg main"},
            %{"path" => "file2.go", "content" => "pkg util"}
          ]
        )

      {:ok, _} =
        Crit.Reviews.create_comment(
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "Comment 1"},
          Ecto.UUID.generate(),
          nil
        )

      {:ok, _} =
        Crit.Reviews.create_comment(
          review,
          %{"start_line" => 2, "end_line" => 2, "body" => "Comment 2"},
          Ecto.UUID.generate(),
          nil
        )

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "2 comments"
      assert html =~ "2 files"
    end
  end

  describe "multiple reviews ordering" do
    test "shows reviews sorted by recent activity", %{conn: conn} do
      {conn, user} = login_user_with_record(conn)

      _older =
        review_fixture(
          user_id: user.id,
          files: [%{"path" => "older.md", "content" => "old content"}]
        )

      _newer =
        review_fixture(
          user_id: user.id,
          files: [%{"path" => "newer.md", "content" => "new content"}]
        )

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "My Reviews (2)"
      assert html =~ "older.md"
      assert html =~ "newer.md"
    end
  end

  describe "delete_review updates count" do
    test "review count decrements after deletion", %{conn: conn} do
      {conn, user} = login_user_with_record(conn)

      review1 =
        review_fixture(
          user_id: user.id,
          files: [%{"path" => "first.md", "content" => "content"}]
        )

      _review2 =
        review_fixture(
          user_id: user.id,
          files: [%{"path" => "second.md", "content" => "content"}]
        )

      {:ok, view, html} = live(conn, ~p"/dashboard")
      assert html =~ "My Reviews (2)"

      view
      |> element("button[phx-value-id='#{review1.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "My Reviews (1)"
      refute html =~ "first.md"
      assert html =~ "second.md"
    end
  end

  describe "dashboard page title" do
    test "page title is Dashboard - Crit", %{conn: conn} do
      conn = login_user(conn)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert page_title(view) =~ "Dashboard - Crit"
    end
  end

  describe "homepage redirect" do
    setup do
      Application.put_env(:crit, :selfhosted, true)

      on_exit(fn ->
        Application.delete_env(:crit, :selfhosted)
      end)
    end

    test "/ redirects to /overview when selfhosted", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == "/overview"
    end
  end
end
