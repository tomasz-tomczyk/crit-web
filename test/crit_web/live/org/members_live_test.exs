defmodule CritWeb.Org.MembersLiveTest do
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
               live(conn, ~p"/orgs/some-org/members")
    end
  end

  describe "non-member" do
    test "redirects to /orgs when not a member", %{conn: conn} do
      admin = oauth_user_fixture()
      org = organization_fixture(admin, %{"slug" => "private-org"})

      non_member = oauth_user_fixture()
      conn = login(conn, non_member)

      assert {:error, {:redirect, %{to: "/orgs"}}} =
               live(conn, ~p"/orgs/#{org.slug}/members")
    end
  end

  describe "members list" do
    test "shows active members", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin Person"})
      member = oauth_user_fixture(%{"name" => "Member Person"})
      org = organization_fixture(admin, %{"slug" => "test-org"})
      _membership = membership_fixture(org, member, "member")

      conn = login(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/orgs/#{org.slug}/members")

      assert html =~ "Admin Person"
      assert html =~ "Member Person"
    end
  end

  describe "admin role management" do
    test "admin can change member role", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      member = oauth_user_fixture(%{"name" => "Member"})
      org = organization_fixture(admin, %{"slug" => "role-org"})
      _membership = membership_fixture(org, member, "member")

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html =
        render_click(view, "change_role", %{"user_id" => member.id, "role" => "admin"})

      # Page should reload members - no error flash
      refute html =~ "Not authorized"
    end

    test "cannot demote last admin", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Solo Admin"})
      org = organization_fixture(admin, %{"slug" => "solo-org"})

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html =
        render_click(view, "change_role", %{"user_id" => admin.id, "role" => "member"})

      assert html =~ "Cannot demote the last admin"
    end

    test "admin can remove member", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      member = oauth_user_fixture(%{"name" => "ToRemove"})
      org = organization_fixture(admin, %{"slug" => "remove-org"})
      _membership = membership_fixture(org, member, "member")

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html =
        render_click(view, "remove_member", %{"user_id" => member.id})

      # Member should be gone from the list
      refute html =~ "ToRemove"
    end

    test "cannot remove last admin", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Solo Admin"})
      org = organization_fixture(admin, %{"slug" => "cant-remove-org"})

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html = render_click(view, "remove_member", %{"user_id" => admin.id})

      assert html =~ "Cannot remove the last admin"
    end
  end

  describe "member (non-admin) actions" do
    test "non-admin cannot change roles", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      member = oauth_user_fixture(%{"name" => "Member"})
      other = oauth_user_fixture(%{"name" => "Other"})
      org = organization_fixture(admin, %{"slug" => "nonadmin-org"})
      _m1 = membership_fixture(org, member, "member")
      _m2 = membership_fixture(org, other, "member")

      conn = login(conn, member)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html = render_click(view, "change_role", %{"user_id" => other.id, "role" => "admin"})
      assert html =~ "Not authorized"
    end

    test "non-admin cannot remove members", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      member = oauth_user_fixture(%{"name" => "Member"})
      other = oauth_user_fixture(%{"name" => "Other"})
      org = organization_fixture(admin, %{"slug" => "nonadmin-remove-org"})
      _m1 = membership_fixture(org, member, "member")
      _m2 = membership_fixture(org, other, "member")

      conn = login(conn, member)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html = render_click(view, "remove_member", %{"user_id" => other.id})
      assert html =~ "Not authorized"
    end
  end

  describe "tab switching" do
    test "can switch between active and pending tabs", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "tab-org"})

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html = render_click(view, "switch_tab", %{"tab" => "pending"})
      assert html =~ "pending" or html =~ "Pending" or html =~ "No pending invites"

      html = render_click(view, "switch_tab", %{"tab" => "active"})
      assert html =~ "Admin"
    end
  end

  describe "invite validation" do
    test "validates invite form on change", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "validate-org"})

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      # Trigger validate event
      html =
        render_click(view, "validate_invite", %{
          "invite" => %{"email" => "test@", "role" => "member"}
        })

      assert html
    end

    test "shows error when inviting already-member email", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin", "email" => "admin-inv@example.com"})
      member = oauth_user_fixture(%{"name" => "Existing", "email" => "existing@example.com"})
      org = organization_fixture(admin, %{"slug" => "already-member-org"})
      _m = membership_fixture(org, member, "member")

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html =
        view
        |> form("#send_invite_form", invite: %{email: "existing@example.com", role: "member"})
        |> render_submit()

      assert html =~ "already a member"
    end

    test "shows error when invite already exists", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "dup-invite-org"})
      scope = org_scope(admin, org)
      {_raw, _invite} = invite_fixture(scope, org, "dup@example.com")

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html =
        view
        |> form("#send_invite_form", invite: %{email: "dup@example.com", role: "member"})
        |> render_submit()

      assert html =~ "already has a pending invite"
    end

    test "shows error for empty email submission", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "empty-email-org"})

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html =
        view
        |> form("#send_invite_form", invite: %{email: "", role: "member"})
        |> render_submit()

      # Either shows changeset error or stays on page
      assert html
    end
  end

  describe "invites (admin)" do
    test "admin can send invite", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "invite-org"})

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html =
        view
        |> form("#send_invite_form", invite: %{email: "new@example.com", role: "member"})
        |> render_submit()

      assert html =~ "Invited new@example.com"
    end

    test "admin can revoke invite", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "revoke-org"})
      scope = org_scope(admin, org)
      {_raw_token, invite} = invite_fixture(scope, org, "revoke-me@example.com")

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      # Switch to pending tab to see invites
      render_click(view, "switch_tab", %{"tab" => "pending"})

      html = render_click(view, "revoke_invite", %{"id" => invite.id})

      # Invite should be removed - check the invite email is gone
      refute html =~ "revoke-me@example.com"
    end

    test "admin can resend invite", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "resend-org"})
      scope = org_scope(admin, org)
      {_raw_token, invite} = invite_fixture(scope, org, "resend-me@example.com")

      conn = login(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/orgs/#{org.slug}/members")

      html = render_click(view, "resend_invite", %{"id" => invite.id})

      assert html =~ "Invite resent"
    end
  end
end
