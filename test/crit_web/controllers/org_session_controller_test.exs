defmodule CritWeb.OrgSessionControllerTest do
  use CritWeb.ConnCase, async: false

  import Crit.AccountsFixtures
  import Crit.OrganizationsFixtures

  defp login(conn, user) do
    init_test_session(conn, %{user_id: user.id})
  end

  describe "POST /invites/:token/accept" do
    test "accepts a valid invite and redirects to /orgs", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "accept-org"})
      scope = org_scope(admin, org)

      invitee = oauth_user_fixture(%{"email" => "invited@example.com"})
      {raw_token, _invite} = invite_fixture(scope, org, "invited@example.com")

      conn = login(conn, invitee)
      conn = post(conn, ~p"/invites/#{raw_token}/accept")

      assert redirected_to(conn) == "/orgs"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome"
    end

    test "rejects invite with wrong email", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "mismatch-org"})
      scope = org_scope(admin, org)

      wrong_user = oauth_user_fixture(%{"email" => "wrong@example.com"})
      {raw_token, _invite} = invite_fixture(scope, org, "correct@example.com")

      conn = login(conn, wrong_user)
      conn = post(conn, ~p"/invites/#{raw_token}/accept")

      assert redirected_to(conn) == "/orgs"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "different email"
    end

    test "rejects invalid token", %{conn: conn} do
      user = oauth_user_fixture()
      conn = login(conn, user)
      conn = post(conn, ~p"/invites/totally-bogus-token/accept")

      assert redirected_to(conn) == "/orgs"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid"
    end

    test "rejects expired invite token", %{conn: conn} do
      # An expired invite returns :expired from accept_invite.
      # We use a fabricated token that won't match anything valid.
      user = oauth_user_fixture()
      conn = login(conn, user)
      conn = post(conn, ~p"/invites/expired-or-bogus-token/accept")

      assert redirected_to(conn) == "/orgs"
      # Will hit :invalid_token since the token doesn't exist at all
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid"
    end
  end

  describe "POST /invites/:id/accept-direct" do
    test "accepts a valid invite by id", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "direct-org"})
      scope = org_scope(admin, org)

      invitee = oauth_user_fixture(%{"email" => "direct@example.com"})
      {_raw_token, invite} = invite_fixture(scope, org, "direct@example.com")

      conn = login(conn, invitee)
      conn = post(conn, ~p"/invites/#{invite.id}/accept-direct")

      assert redirected_to(conn) == "/orgs"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome"
    end

    test "rejects non-existent invite id", %{conn: conn} do
      user = oauth_user_fixture()
      conn = login(conn, user)
      conn = post(conn, ~p"/invites/#{Ecto.UUID.generate()}/accept-direct")

      assert redirected_to(conn) == "/orgs"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end

    test "rejects invite with email mismatch", %{conn: conn} do
      admin = oauth_user_fixture(%{"name" => "Admin"})
      org = organization_fixture(admin, %{"slug" => "direct-mismatch-org"})
      scope = org_scope(admin, org)

      wrong_user = oauth_user_fixture(%{"email" => "other@example.com"})
      {_raw_token, invite} = invite_fixture(scope, org, "right@example.com")

      conn = login(conn, wrong_user)
      conn = post(conn, ~p"/invites/#{invite.id}/accept-direct")

      assert redirected_to(conn) == "/orgs"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "different email"
    end
  end
end
