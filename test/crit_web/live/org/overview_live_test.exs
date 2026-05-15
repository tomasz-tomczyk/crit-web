defmodule CritWeb.Org.OverviewLiveTest do
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
               live(conn, ~p"/orgs/some-org")
    end
  end

  describe "non-member" do
    test "redirects to /orgs when not a member", %{conn: conn} do
      admin = oauth_user_fixture()
      org = organization_fixture(admin, %{"name" => "Private Org", "slug" => "private-org"})

      non_member = oauth_user_fixture()
      conn = login(conn, non_member)

      assert {:error, {:redirect, %{to: "/orgs"}}} = live(conn, ~p"/orgs/#{org.slug}")
    end
  end

  describe "member" do
    test "shows org name and greeting", %{conn: conn} do
      user = oauth_user_fixture(%{"name" => "Alice"})
      org = organization_fixture(user, %{"name" => "Acme Corp", "slug" => "acme-corp"})

      conn = login(conn, user)
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}")

      assert html =~ "Acme Corp"
      assert html =~ "Welcome back, Alice"
    end

    test "shows members list", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin User"})
      member = oauth_user_fixture(%{"name" => "Member User"})
      org = organization_fixture(admin, %{"slug" => "team-org"})
      _membership = membership_fixture(org, member)

      conn = login(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}")

      assert html =~ "Admin User"
      assert html =~ "Member User"
    end
  end
end
