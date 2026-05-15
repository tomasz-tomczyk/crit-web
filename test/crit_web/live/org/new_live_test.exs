defmodule CritWeb.Org.NewLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Crit.AccountsFixtures

  defp login(conn, user) do
    init_test_session(conn, %{user_id: user.id})
  end

  describe "unauthenticated" do
    test "redirects to login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/auth/login" <> _}}} = live(conn, ~p"/orgs/new")
    end
  end

  describe "authenticated" do
    test "renders creation form", %{conn: conn} do
      user = oauth_user_fixture()
      conn = login(conn, user)

      {:ok, _view, html} = live(conn, ~p"/orgs/new")

      assert html =~ "New organization"
      assert html =~ "Organization name"
      assert html =~ "URL slug"
    end

    test "creates org on submit and redirects to settings", %{conn: conn} do
      user = oauth_user_fixture()
      conn = login(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orgs/new")

      result =
        view
        |> form("#new_org_form", org: %{name: "My New Org", slug: "my-new-org"})
        |> render_submit()

      assert {:error, {:live_redirect, %{to: "/orgs/my-new-org/settings"}}} = result
    end

    test "shows validation errors for invalid input", %{conn: conn} do
      user = oauth_user_fixture()
      conn = login(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orgs/new")

      html =
        view
        |> form("#new_org_form", org: %{name: "", slug: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "auto-generates slug from name during validation", %{conn: conn} do
      user = oauth_user_fixture()
      conn = login(conn, user)

      {:ok, view, _html} = live(conn, ~p"/orgs/new")

      html =
        view
        |> form("#new_org_form", org: %{name: "Cool Team"})
        |> render_change()

      assert html =~ "cool-team"
    end
  end
end
