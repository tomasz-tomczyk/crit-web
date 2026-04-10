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

  describe "homepage redirect" do
    setup do
      Application.put_env(:crit, :selfhosted, true)

      on_exit(fn ->
        Application.delete_env(:crit, :selfhosted)
      end)
    end

    test "/ redirects to /dashboard when selfhosted", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == "/dashboard"
    end
  end
end
