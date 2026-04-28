defmodule CritWeb.UserAuthTest do
  # async: false because some tests mutate Application env (`:oauth_provider`)
  # which is read by other tests that run in parallel.
  use CritWeb.ConnCase, async: false

  alias Crit.Accounts.Scope
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

  defp create_user!(attrs \\ []) do
    base = %{
      provider: "test",
      provider_uid: "uid-#{System.unique_integer([:positive])}",
      email: "u-#{System.unique_integer([:positive])}@example.com",
      name: "Alex"
    }

    %Crit.User{}
    |> Crit.User.changeset(Map.merge(base, Map.new(attrs)))
    |> Crit.Repo.insert!()
  end
end
