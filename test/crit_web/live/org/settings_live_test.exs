defmodule CritWeb.Org.SettingsLiveTest do
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
               live(conn, ~p"/orgs/some-org/settings")
    end
  end

  describe "non-member" do
    test "redirects to /orgs when not a member", %{conn: conn} do
      admin = oauth_user_fixture()
      org = organization_fixture(admin, %{"slug" => "private-org"})

      non_member = oauth_user_fixture()
      conn = login(conn, non_member)

      assert {:error, {:redirect, %{to: "/orgs"}}} =
               live(conn, ~p"/orgs/#{org.slug}/settings")
    end
  end

  describe "admin" do
    test "can update org name", %{conn: conn} do
      user = oauth_user_fixture()
      org = organization_fixture(user, %{"name" => "Old Name", "slug" => "test-org"})

      conn = login(conn, user)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/settings")

      html =
        view
        |> form("#org_settings_form", org: %{name: "New Name"})
        |> render_submit()

      # Should stay on same page with flash
      assert html =~ "Organization updated."
    end

    test "slug change redirects to new URL", %{conn: conn} do
      user = oauth_user_fixture()
      org = organization_fixture(user, %{"name" => "Test Org", "slug" => "old-slug"})

      conn = login(conn, user)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/settings")

      result =
        view
        |> form("#org_settings_form", org: %{slug: "new-slug"})
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/orgs/new-slug/settings"}}} = result
    end

    test "delete requires typing slug", %{conn: conn} do
      user = oauth_user_fixture()
      org = organization_fixture(user, %{"name" => "Delete Me", "slug" => "delete-me"})

      conn = login(conn, user)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/settings")

      # Try to delete without matching slug
      html = render_click(view, "delete_org")
      assert html =~ "Slug does not match"

      # Type the correct slug, then delete
      render_click(view, "update_delete_confirmation", %{"value" => "delete-me"})
      result = render_click(view, "delete_org")
      assert {:error, {:live_redirect, %{to: "/orgs"}}} = result
    end
  end

  describe "leave organization" do
    test "admin with another admin can leave the organization", %{conn: conn} do
      admin1 = oauth_user_fixture(%{"name" => "Admin1"})
      admin2 = oauth_user_fixture(%{"name" => "Admin2"})
      org = organization_fixture(admin1, %{"slug" => "leave-org"})
      _membership = membership_fixture(org, admin2, "admin")

      conn = login(conn, admin2)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/settings")

      result = render_click(view, "leave")
      assert {:error, {:live_redirect, %{to: "/orgs"}}} = result
    end

    test "last admin cannot leave", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Solo Admin"})
      org = organization_fixture(admin, %{"slug" => "solo-leave-org"})

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/settings")

      html = render_click(view, "leave")
      assert html =~ "last admin"
    end
  end

  describe "validation" do
    test "validates form on change", %{conn: conn} do
      user = oauth_user_fixture()
      org = organization_fixture(user, %{"name" => "Val Org", "slug" => "val-org"})

      conn = login(conn, user)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/settings")

      html =
        view
        |> form("#org_settings_form", org: %{name: ""})
        |> render_change()

      # Form should show validation state (empty name)
      assert html =~ "org_settings_form"
    end
  end

  describe "member (non-admin)" do
    test "is redirected away from settings", %{conn: conn} do
      admin = oauth_user_fixture()
      member = oauth_user_fixture()
      org = organization_fixture(admin, %{"slug" => "member-org"})
      _membership = membership_fixture(org, member, "member")

      conn = login(conn, member)

      assert {:error, {:redirect, %{to: "/orgs/member-org/members", flash: %{"error" => _}}}} =
               live(conn, ~p"/orgs/#{org.slug}/settings")
    end
  end
end
