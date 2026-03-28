defmodule CritWeb.TokensLiveTest do
  use CritWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    Application.put_env(:crit, :selfhosted, true)

    on_exit(fn ->
      Application.delete_env(:crit, :selfhosted)
    end)
  end

  defp login_user(conn) do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "test_uid_#{System.unique_integer()}",
        "email" => "test@example.com",
        "name" => "Test User"
      })

    {init_test_session(conn, %{user_id: user.id}), user}
  end

  describe "mount requires auth" do
    test "redirects to / when not in selfhosted mode", %{conn: conn} do
      Application.delete_env(:crit, :selfhosted)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/tokens")
    end

    test "redirects to /dashboard when not authenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/tokens")
    end

    test "renders tokens page when authenticated", %{conn: conn} do
      {conn, _user} = login_user(conn)

      {:ok, _view, html} = live(conn, ~p"/tokens")

      assert html =~ "API Tokens"
      assert html =~ "No tokens yet"
    end
  end

  describe "list tokens" do
    test "shows existing tokens", %{conn: conn} do
      {conn, user} = login_user(conn)
      {:ok, {_plaintext, _token}} = Crit.Accounts.create_token(user, "my cli token")

      {:ok, _view, html} = live(conn, ~p"/tokens")

      assert html =~ "my cli token"
      refute html =~ "No tokens yet"
    end
  end

  describe "create token" do
    test "creates a token and shows plaintext", %{conn: conn} do
      {conn, _user} = login_user(conn)

      {:ok, view, _html} = live(conn, ~p"/tokens")

      view
      |> element("#create-token-form")
      |> render_submit(%{name: "my laptop"})

      html = render(view)
      assert html =~ "my laptop"
      assert html =~ "copy it now"
      assert html =~ "crit_"
    end
  end

  describe "revoke token" do
    test "removes a token from the list", %{conn: conn} do
      {conn, user} = login_user(conn)
      {:ok, {_plaintext, token}} = Crit.Accounts.create_token(user, "to revoke")

      {:ok, view, html} = live(conn, ~p"/tokens")
      assert html =~ "to revoke"

      view
      |> element("button[phx-value-id='#{token.id}']")
      |> render_click()

      html = render(view)
      refute html =~ "to revoke"
    end
  end
end
