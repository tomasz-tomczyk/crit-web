defmodule CritWeb.Org.SelectLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.AccountsFixtures
  import Crit.OrganizationsFixtures

  defp login(conn, user) do
    init_test_session(conn, %{user_id: user.id})
  end

  describe "unauthenticated" do
    test "redirects to login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/auth/login" <> _}}} = live(conn, ~p"/orgs")
    end
  end

  describe "authenticated with orgs" do
    test "shows org cards when user has orgs", %{conn: conn} do
      user = oauth_user_fixture()
      org = organization_fixture(user, %{"name" => "Test Org"})
      conn = login(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orgs")

      assert html =~ "Test Org"
      assert html =~ org.slug
    end

    test "shows empty state when no orgs and no invites", %{conn: conn} do
      user = oauth_user_fixture()
      conn = login(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orgs")

      assert html =~ "No organizations yet"
    end
  end

  describe "pending invites" do
    test "shows pending invites for user's email", %{conn: conn} do
      admin = oauth_user_fixture()
      invitee = oauth_user_fixture(%{"email" => "invitee@example.com"})
      org = organization_fixture(admin, %{"name" => "Invite Org"})
      scope = org_scope(admin, org)

      {_raw_token, _invite} = invite_fixture(scope, org, "invitee@example.com")

      conn = login(conn, invitee)
      {:ok, _view, html} = live(conn, ~p"/orgs")

      assert html =~ "Pending invites"
      assert html =~ "Invite Org"
    end
  end
end
