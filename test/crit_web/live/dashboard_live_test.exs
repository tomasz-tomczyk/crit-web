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

    test "shows review list when no password and no oauth configured", %{conn: conn} do
      without_oauth(%{})

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
      refute html =~ "All Reviews"
    end

    test "shows password form when no OAuth configured", %{conn: conn} do
      Application.delete_env(:crit, :oauth_provider)

      on_exit(fn ->
        Application.put_env(:crit, :oauth_provider,
          strategy: Assent.Strategy.Github,
          client_id: "test_github_client_id",
          client_secret: "test_github_client_secret"
        )
      end)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "password"
      refute html =~ "Sign in with OAuth"
    end

    test "shows OAuth button and hides password form when OAuth configured", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Sign in with OAuth"
      refute html =~ "login-form"
    end

    test "shows review list when authenticated via OAuth", %{conn: conn} do
      review = review_fixture()
      conn = login_user(conn)

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
    setup :without_oauth

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

  describe "delete_review with OAuth" do
    test "owner can delete their own review", %{conn: conn} do
      {conn, user} = login_user_with_record(conn)
      review = review_fixture(user_id: user.id)

      {:ok, view, html} = live(conn, ~p"/dashboard")
      assert html =~ hd(review.files).file_path

      view
      |> element("button[phx-value-id='#{review.id}']")
      |> render_click()

      refute render(view) =~ hd(review.files).file_path
    end

    test "user cannot delete another user's review", %{conn: conn} do
      {:ok, other_user} =
        Crit.Accounts.find_or_create_from_oauth("github", %{
          "sub" => "other_uid_#{System.unique_integer()}",
          "email" => "other@example.com",
          "name" => "Other User"
        })

      review = review_fixture(user_id: other_user.id)
      conn = login_user(conn)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      refute has_element?(view, "button[phx-value-id='#{review.id}']")

      # Also verify the server-side guard rejects a crafted event
      view
      |> render_hook("delete_review", %{"id" => review.id})

      assert render(view) =~ hd(review.files).file_path
    end

    test "any authenticated user can delete an ownerless review", %{conn: conn} do
      review = review_fixture()
      conn = login_user(conn)

      {:ok, view, html} = live(conn, ~p"/dashboard")
      assert html =~ hd(review.files).file_path

      view
      |> element("button[phx-value-id='#{review.id}']")
      |> render_click()

      refute render(view) =~ hd(review.files).file_path
    end
  end

  describe "review links" do
    setup :without_oauth

    test "review rows link to /r/:token", %{conn: conn} do
      review = review_fixture()

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ ~p"/r/#{review.token}"
    end
  end

  describe "empty state" do
    setup :without_oauth

    test "shows message when no reviews", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No reviews yet"
    end
  end

end
