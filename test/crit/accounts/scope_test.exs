defmodule Crit.Accounts.ScopeTest do
  use Crit.DataCase, async: true

  alias Crit.Accounts.Scope
  alias Crit.User

  describe "for_visitor/2" do
    test "builds anonymous scope with identity and display_name" do
      scope = Scope.for_visitor("ident-1", "Pat")
      assert %Scope{user: nil, identity: "ident-1", display_name: "Pat"} = scope
    end

    test "display_name defaults to nil" do
      assert Scope.for_visitor("ident-1").display_name == nil
    end
  end

  describe "for_user/1" do
    test "builds scope from user; identity is nil; display_name is user.name" do
      user = %User{id: "u-1", name: "Alex", email: "a@example.com"}
      scope = Scope.for_user(user)
      assert %Scope{user: ^user, identity: nil, display_name: "Alex"} = scope
    end

    test "display_name falls back to literal \"User\" when name is blank — never email" do
      user = %User{id: "u-1", name: nil, email: "a@example.com"}
      assert Scope.for_user(user).display_name == "User"

      user = %User{id: "u-1", name: "", email: "a@example.com"}
      assert Scope.for_user(user).display_name == "User"
    end

    test "for_user(nil) returns an empty scope, not nil" do
      assert %Scope{user: nil, identity: nil, display_name: nil} = Scope.for_user(nil)
    end
  end

  describe "for_session/1" do
    test "builds anonymous scope when no user_id" do
      session = %{"identity" => "ident-1", "display_name" => "Pat"}

      assert %Scope{user: nil, identity: "ident-1", display_name: "Pat"} =
               Scope.for_session(session)
    end

    test "builds authenticated scope when user_id resolves; clears stale identity" do
      user = insert_user!(%{name: "Alex"})
      session = %{"user_id" => user.id, "identity" => "ident-1"}
      scope = Scope.for_session(session)
      assert scope.user.id == user.id
      assert scope.identity == nil
    end

    test "treats invalid user_id as anonymous" do
      session = %{"user_id" => Ecto.UUID.generate(), "identity" => "ident-1"}
      scope = Scope.for_session(session)
      assert scope.user == nil
      assert scope.identity == "ident-1"
    end
  end

  describe "user_id/1" do
    test "nil for anonymous" do
      assert Scope.user_id(%Scope{}) == nil
    end

    test "user.id for authenticated" do
      assert Scope.user_id(Scope.for_user(%User{id: "u-1"})) == "u-1"
    end
  end

  describe "put_user/2 and put_display_name/2" do
    test "put_user replaces user and refreshes display_name" do
      user = %User{id: "u-1", name: "Alex"}
      scope = Scope.for_visitor("ident-1", "Pat") |> Scope.put_user(user)
      assert scope.user == user
      assert scope.display_name == "Alex"
    end

    test "put_display_name only touches display_name" do
      scope = Scope.for_visitor("ident-1") |> Scope.put_display_name("Robin")
      assert scope.identity == "ident-1"
      assert scope.display_name == "Robin"
    end
  end

  describe "mutual exclusion invariant" do
    test "for_user/1 produces nil identity" do
      assert Scope.for_user(%User{id: "u-1", name: "X"}).identity == nil
    end

    test "for_visitor/2 produces nil user" do
      assert Scope.for_visitor("ident-1").user == nil
    end
  end

  defp insert_user!(attrs) do
    base = %{
      provider: "test",
      provider_uid: "uid-#{System.unique_integer([:positive])}",
      email: "u-#{System.unique_integer([:positive])}@example.com"
    }

    %Crit.User{}
    |> Crit.User.changeset(Map.merge(base, attrs))
    |> Crit.Repo.insert!()
  end
end
