defmodule CritWeb.Org.InviteAcceptLiveTest do
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
               live(conn, ~p"/invites/some-token")
    end
  end

  describe "valid invite" do
    test "shows accept UI for valid invite", %{conn: conn} do
      admin = oauth_user_fixture()
      invitee = oauth_user_fixture(%{"email" => "invitee@example.com"})
      org = organization_fixture(admin, %{"name" => "Cool Org"})
      scope = org_scope(admin, org)
      {raw_token, _invite} = invite_fixture(scope, org, "invitee@example.com")

      conn = login(conn, invitee)
      {:ok, _view, html} = live(conn, ~p"/invites/#{raw_token}")

      assert html =~ "Cool Org"
      assert html =~ "Accept invitation"
    end
  end

  describe "expired invite" do
    test "shows expired message", %{conn: conn} do
      admin = oauth_user_fixture()
      invitee = oauth_user_fixture(%{"email" => "expired@example.com"})
      org = organization_fixture(admin)
      scope = org_scope(admin, org)
      {raw_token, invite} = invite_fixture(scope, org, "expired@example.com")

      # Manually expire the invite
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-8, :day)
        |> DateTime.truncate(:second)

      invite
      |> Ecto.Changeset.change(%{inserted_at: expired_at})
      |> Crit.Repo.update!()

      conn = login(conn, invitee)
      {:ok, _view, html} = live(conn, ~p"/invites/#{raw_token}")

      assert html =~ "expired"
    end
  end

  describe "email mismatch" do
    test "shows email mismatch message", %{conn: conn} do
      admin = oauth_user_fixture()
      wrong_user = oauth_user_fixture(%{"email" => "wrong@example.com"})
      org = organization_fixture(admin)
      scope = org_scope(admin, org)
      {raw_token, _invite} = invite_fixture(scope, org, "correct@example.com")

      conn = login(conn, wrong_user)
      {:ok, _view, html} = live(conn, ~p"/invites/#{raw_token}")

      assert html =~ "someone else" or html =~ "correct@example.com"
    end
  end

  describe "invalid token" do
    test "shows not found for invalid token", %{conn: conn} do
      user = oauth_user_fixture()
      conn = login(conn, user)

      {:ok, _view, html} = live(conn, ~p"/invites/invalid-token-value")

      assert html =~ "not found" or html =~ "invalid" or html =~ "Not found"
    end
  end
end
