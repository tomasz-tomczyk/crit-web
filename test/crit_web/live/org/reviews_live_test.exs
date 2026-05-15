defmodule CritWeb.Org.ReviewsLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.AccountsFixtures
  import Crit.OrganizationsFixtures

  defp login(conn, user) do
    init_test_session(conn, %{user_id: user.id})
  end

  describe "unauthenticated" do
    test "redirects to login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/auth/login" <> _}}} =
               live(conn, ~p"/orgs/some-org/reviews")
    end
  end

  describe "non-member" do
    test "redirects to /orgs when not a member", %{conn: conn} do
      admin = oauth_user_fixture()
      org = organization_fixture(admin, %{"slug" => "private-org"})

      non_member = oauth_user_fixture()
      conn = login(conn, non_member)

      assert {:error, {:redirect, %{to: "/orgs"}}} =
               live(conn, ~p"/orgs/#{org.slug}/reviews")
    end
  end

  describe "member" do
    test "renders the org reviews page", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"name" => "Test Org", "slug" => "test-org"})

      conn = login(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/reviews")

      assert html =~ "Reviews"
      assert html =~ "Test Org"
    end

    test "regular member can view org reviews", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      member = oauth_user_fixture(%{"name" => "Member"})
      org = organization_fixture(admin, %{"name" => "Member Org", "slug" => "member-org"})
      _membership = membership_fixture(org, member, "member")

      conn = login(conn, member)
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/reviews")

      assert html =~ "Reviews"
      assert html =~ "Member Org"
    end
  end
end
