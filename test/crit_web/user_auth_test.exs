defmodule CritWeb.UserAuthTest do
  # async: false because some tests mutate Application env (`:oauth_provider`)
  # which is read by other tests that run in parallel.
  use CritWeb.ConnCase, async: false

  alias Crit.Accounts.Scope
  alias Crit.AccountsFixtures
  alias CritWeb.UserAuth

  describe "fetch_current_scope_for_user/2" do
    test "assigns anonymous scope and seeds identity when missing", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.fetch_current_scope_for_user([])

      assert %Scope{user: nil, identity: identity} = conn.assigns.current_scope
      assert is_binary(identity)
      assert Plug.Conn.get_session(conn, "identity") == identity
    end

    test "preserves existing session identity", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{"identity" => "existing-ident"})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.identity == "existing-ident"
      assert Plug.Conn.get_session(conn, "identity") == "existing-ident"
    end

    test "loads user from session user_id", %{conn: conn} do
      user = create_user!()

      conn =
        conn
        |> Plug.Test.init_test_session(%{"user_id" => user.id})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      assert conn.assigns.current_scope.identity == nil
    end

    test "clears stale user_id and falls back to anonymous", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{"user_id" => Ecto.UUID.generate()})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user == nil
      assert Plug.Conn.get_session(conn, "user_id") == nil
    end

    test "loads user from remember-me cookie when session has no user_id", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      logged_in =
        %{conn | secret_key_base: CritWeb.Endpoint.config(:secret_key_base)}
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      remember_cookie = logged_in.resp_cookies["_crit_web_user_remember_me"]
      assert remember_cookie

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:secret_key_base, CritWeb.Endpoint.config(:secret_key_base))
        |> Plug.Test.put_req_cookie("_crit_web_user_remember_me", remember_cookie.value)
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      assert Plug.Conn.get_session(conn, "user_id") == user.id
    end

    test "remember-me cookie hit clears stale session keys (no fixation)", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      logged_in =
        %{conn | secret_key_base: CritWeb.Endpoint.config(:secret_key_base)}
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      remember_cookie = logged_in.resp_cookies["_crit_web_user_remember_me"]

      # An attacker plants attacker_identity in the session; the legitimate
      # remember-me cookie must not carry it into the now-authenticated session.
      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:secret_key_base, CritWeb.Endpoint.config(:secret_key_base))
        |> Plug.Test.put_req_cookie("_crit_web_user_remember_me", remember_cookie.value)
        |> Plug.Test.init_test_session(%{"identity" => "attacker-planted-identity"})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      refute Plug.Conn.get_session(conn, "identity") == "attacker-planted-identity"
    end

    test "deletes cookie and stays anonymous when remember-me token is unknown", %{conn: conn} do
      # Build a conn with an unsigned/garbage cookie value — signed-cookie verification fails.
      conn =
        %{conn | secret_key_base: CritWeb.Endpoint.config(:secret_key_base)}
        |> Plug.Test.put_req_cookie("_crit_web_user_remember_me", "not-a-valid-signed-cookie")
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user == nil
      assert Plug.Conn.get_session(conn, "user_id") == nil
    end

    test "deletes cookie when token row is missing from DB", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      logged_in =
        %{conn | secret_key_base: CritWeb.Endpoint.config(:secret_key_base)}
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      remember_cookie = logged_in.resp_cookies["_crit_web_user_remember_me"]

      # Wipe the remember_me row so the signed cookie verifies but the DB lookup misses.
      Crit.Repo.delete_all(Crit.Accounts.UserToken)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:secret_key_base, CritWeb.Endpoint.config(:secret_key_base))
        |> Plug.Test.put_req_cookie("_crit_web_user_remember_me", remember_cookie.value)
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user == nil
      assert Plug.Conn.get_session(conn, "user_id") == nil
      assert conn.resp_cookies["_crit_web_user_remember_me"].max_age == 0
    end

    test "puts session display_name into anonymous scope", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{"display_name" => "Pat"})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.display_name == "Pat"
    end

    test "authenticated scope's display_name comes from user, never email", %{conn: conn} do
      user = create_user!(name: nil)

      conn =
        conn
        |> Plug.Test.init_test_session(%{"user_id" => user.id})
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.display_name == "User"
      refute conn.assigns.current_scope.display_name == user.email
    end
  end

  describe "on_mount :mount_current_scope_for_user" do
    test "assigns scope from session" do
      session = %{"identity" => "ident-1", "display_name" => "Pat"}
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

      assert {:cont, %{assigns: %{current_scope: %Scope{identity: "ident-1"}}}} =
               UserAuth.on_mount(:mount_current_scope_for_user, %{}, session, socket)
    end
  end

  describe "on_mount :require_authenticated_user" do
    test "halts and redirects when no user and OAuth configured" do
      # config/test.exs already sets :oauth_provider — no need to mutate Application env
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:halt, redirected} =
               UserAuth.on_mount(
                 :require_authenticated_user,
                 %{},
                 %{"request_path" => "/x"},
                 socket
               )

      assert redirected.redirected
    end

    test "continues when user is present" do
      user = create_user!()
      session = %{"user_id" => user.id}
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:cont, %{assigns: %{current_scope: %Scope{user: %{id: id}}}}} =
               UserAuth.on_mount(:require_authenticated_user, %{}, session, socket)

      assert id == user.id
    end
  end

  describe "log_in_user/3" do
    test "writes user_id to the session", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.log_in_user(user, %{})

      assert get_session(conn, "user_id") == user.id
    end

    test "writes a remember_me cookie when requested", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn =
        %{conn | secret_key_base: CritWeb.Endpoint.config(:secret_key_base)}
        |> Plug.Test.init_test_session(%{})
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      assert conn.resp_cookies["_crit_web_user_remember_me"]
      assert Crit.Repo.aggregate(Crit.Accounts.UserToken, :count) == 1
    end
  end

  describe "log_out_user/1" do
    test "clears session and remember-me cookie", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> Plug.Test.init_test_session(%{"user_id" => user.id})
        |> UserAuth.log_out_user()

      refute get_session(conn, "user_id")
    end
  end

  defp create_user!(attrs \\ []) do
    base = %{
      provider: "test",
      provider_uid: "uid-#{System.unique_integer([:positive])}",
      email: "u-#{System.unique_integer([:positive])}@example.com",
      name: "Alex"
    }

    %Crit.User{}
    |> Crit.User.oauth_changeset(Map.merge(base, Map.new(attrs)))
    |> Crit.Repo.insert!()
  end
end
