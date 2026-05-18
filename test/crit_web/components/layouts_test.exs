defmodule CritWeb.LayoutsTest do
  @moduledoc """
  Verifies the header sign-in / Settings / Log out links per the 4-combo
  table in the local-auth plan:

      registration | oauth      | target
      ------------ | ---------- | --------------
      true         | false      | /users/log_in
      true         | true       | /users/log_in
      false        | true       | /auth/login
      false        | false      | hidden

  Settings + Log out are rendered for authenticated users regardless of
  combo. Both link to the universal routes (Settings → /settings,
  Log out → DELETE /auth/logout) so they work in hosted (OAuth-only)
  mode as well as selfhost — the /users/* routes are SelfhostedOnly-gated.
  """
  use CritWeb.ConnCase, async: false

  import Crit.AccountsFixtures

  setup do
    original_registration = Application.get_env(:crit, :local_registration_enabled)
    original_oauth = Application.get_env(:crit, :oauth_provider)
    original_selfhosted = Application.get_env(:crit, :selfhosted)

    on_exit(fn ->
      restore(:local_registration_enabled, original_registration)
      restore(:oauth_provider, original_oauth)
      restore(:selfhosted, original_selfhosted)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:crit, key)
  defp restore(key, value), do: Application.put_env(:crit, key, value)

  defp configure(registration, oauth) do
    # selfhosted=false so the homepage renders (selfhosted mode redirects
    # `/` to `/overview`). The link generation under test only depends on
    # `:local_registration_enabled` and `:oauth_provider`.
    Application.put_env(:crit, :selfhosted, false)
    Application.put_env(:crit, :local_registration_enabled, registration)

    if oauth do
      Application.put_env(:crit, :oauth_provider,
        strategy: Assent.Strategy.Github,
        client_id: "x",
        client_secret: "y"
      )
    else
      Application.delete_env(:crit, :oauth_provider)
    end
  end

  describe "anonymous header sign-in target (4-combo)" do
    test "registration=true, oauth=false → /users/log_in", %{conn: conn} do
      configure(true, false)

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s|href="/users/log_in"|
      assert html =~ "Sign in"
      refute html =~ ~s|href="/auth/login" class="inline-flex|
    end

    test "registration=true, oauth=true → /users/log_in", %{conn: conn} do
      configure(true, true)

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s|href="/users/log_in"|
      assert html =~ "Sign in"
    end

    test "registration=false, oauth=true → /auth/login", %{conn: conn} do
      configure(false, true)

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s|href="/auth/login|
      assert html =~ "Sign in"
      refute html =~ ~s|href="/users/log_in"|
    end

    test "registration=false, oauth=false → hidden", %{conn: conn} do
      configure(false, false)

      html = conn |> get(~p"/") |> html_response(200)

      refute html =~ ~s|href="/users/log_in"|
      refute html =~ ~s|href="/auth/login" class="inline-flex|
    end
  end

  describe "/overview header (selfhost)" do
    test "renders sign-in link when unauthenticated in selfhost+local-auth mode",
         %{conn: conn} do
      Application.put_env(:crit, :selfhosted, true)
      Application.put_env(:crit, :local_registration_enabled, true)
      Application.delete_env(:crit, :oauth_provider)

      html = conn |> get(~p"/overview") |> html_response(200)

      assert html =~ "Sign in"
      assert html =~ ~s|href="/users/log_in"|
    end

    test "hides sign-in link when neither registration nor oauth configured",
         %{conn: conn} do
      Application.put_env(:crit, :selfhosted, true)
      Application.put_env(:crit, :local_registration_enabled, false)
      Application.delete_env(:crit, :oauth_provider)

      html = conn |> get(~p"/overview") |> html_response(200)

      refute html =~ ~s|href="/users/log_in"|
      refute html =~ ~s|href="/auth/login|
    end
  end

  describe "authenticated header" do
    test "renders Settings + Log out (DELETE) in selfhost mode", %{conn: conn} do
      configure(true, false)
      user = user_fixture()

      html =
        conn
        |> log_in_user(user)
        |> get(~p"/dashboard")
        |> html_response(200)

      assert html =~ ~s|href="/settings"|
      assert html =~ "Settings"
      # Log out link uses DELETE — Phoenix's <.link href method="delete">
      # injects data-method="delete" on the anchor.
      assert html =~ ~s|href="/auth/logout"|
      assert html =~ ~s|data-method="delete"|
    end

    test "renders /auth/logout (not /users/log_out) in hosted OAuth-only mode",
         %{conn: conn} do
      # Hosted: registration=false, oauth=true. /users/* routes are
      # SelfhostedOnly-gated and would 404, so the header MUST link to the
      # universal /auth/logout + /settings routes.
      configure(false, true)
      user = oauth_user_fixture()

      html =
        conn
        |> log_in_user(user)
        |> get(~p"/dashboard")
        |> html_response(200)

      assert html =~ ~s|href="/auth/logout"|
      assert html =~ ~s|data-method="delete"|
      assert html =~ ~s|href="/settings"|
      refute html =~ ~s|href="/users/log_out"|
      refute html =~ ~s|href="/users/settings"|
    end
  end
end
