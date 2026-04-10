defmodule CritWeb.SettingsLiveTest do
  use CritWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp login_user(conn) do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "settings_uid_#{System.unique_integer()}",
        "email" => "settings@example.com",
        "name" => "Settings User"
      })

    {init_test_session(conn, %{user_id: user.id}), user}
  end

  describe "mount requires user" do
    test "redirects to /auth/login when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/auth/login?return_to=/settings"}}} =
               live(conn, ~p"/settings")
    end

    test "renders settings page when authenticated", %{conn: conn} do
      {conn, _user} = login_user(conn)

      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "Settings"
    end
  end

  describe "API tokens section" do
    test "shows existing tokens", %{conn: conn} do
      {conn, user} = login_user(conn)
      {:ok, {_plaintext, _token}} = Crit.Accounts.create_token(user, "my cli token")

      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "my cli token"
      refute html =~ "No tokens yet"
    end

    test "creates a token and shows plaintext", %{conn: conn} do
      {conn, _user} = login_user(conn)

      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("#create-token-form")
      |> render_submit(%{name: "my laptop"})

      html = render(view)
      assert html =~ "my laptop"
      assert html =~ "copy it now"
      assert html =~ "crit_"
    end

    test "revokes a token", %{conn: conn} do
      {conn, user} = login_user(conn)
      {:ok, {_plaintext, token}} = Crit.Accounts.create_token(user, "to revoke")

      {:ok, view, html} = live(conn, ~p"/settings")
      assert html =~ "to revoke"

      view
      |> element("button[phx-value-id='#{token.id}']")
      |> render_click()

      html = render(view)
      refute html =~ "to revoke"
    end
  end

  describe "delete account" do
    test "shows confirmation form", %{conn: conn} do
      {conn, user} = login_user(conn)

      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ "Delete account"
      assert html =~ "Delete this account"
      assert html =~ user.email
    end

    test "button is disabled when confirmation text does not match", %{conn: conn} do
      {conn, _user} = login_user(conn)

      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("#delete-account-form")
      |> render_change(%{confirmation: "wrong text"})

      assert has_element?(view, "button[disabled]", "Delete this account")
    end

    test "button is enabled when confirmation text matches", %{conn: conn} do
      {conn, user} = login_user(conn)

      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("#delete-account-form")
      |> render_change(%{confirmation: user.email})

      refute has_element?(view, "button[disabled]", "Delete this account")
    end

    test "deletes account and redirects to home", %{conn: conn} do
      {conn, user} = login_user(conn)

      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("#delete-account-form")
      |> render_change(%{confirmation: user.email})

      view
      |> element("#delete-account-form")
      |> render_submit(%{confirmation: user.email})

      assert_redirect(view, ~p"/")

      # Verify user is deleted
      assert {:error, :not_found} = Crit.Accounts.get_user(user.id)
    end

    test "rejects delete when confirmation text is wrong", %{conn: conn} do
      {conn, user} = login_user(conn)

      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> element("#delete-account-form")
      |> render_submit(%{confirmation: "wrong"})

      html = render(view)
      assert html =~ "Confirmation text does not match"

      # User should still exist
      assert {:ok, _} = Crit.Accounts.get_user(user.id)
    end
  end

  describe "account section" do
    test "shows user profile info", %{conn: conn} do
      {conn, user} = login_user(conn)

      {:ok, _view, html} = live(conn, ~p"/settings")

      assert html =~ user.name
      assert html =~ user.email
      assert html =~ "github"
    end
  end
end
