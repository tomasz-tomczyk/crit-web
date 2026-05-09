defmodule Crit.AuthorizationTest do
  use Crit.DataCase, async: false

  alias Crit.Accounts.Scope
  alias Crit.Authorization
  alias Crit.User

  defp admin do
    Scope.for_user(%User{
      id: Ecto.UUID.generate(),
      role: :admin,
      email: "alice@example.com",
      name: "Alice"
    })
  end

  defp user do
    Scope.for_user(%User{
      id: Ecto.UUID.generate(),
      role: :user,
      email: "bob@example.com",
      name: "Bob"
    })
  end

  defp anon, do: Scope.for_visitor(Ecto.UUID.generate())

  describe "admin?/1" do
    test "true for admin scope" do
      assert Authorization.admin?(admin())
    end

    test "false for user scope" do
      refute Authorization.admin?(user())
    end

    test "false for anonymous scope" do
      refute Authorization.admin?(anon())
    end

    test "false for nil" do
      refute Authorization.admin?(nil)
    end
  end

  describe "can?/3 :manage_users + :edit_settings" do
    test "admin can" do
      assert Authorization.can?(admin(), :manage_users)
      assert Authorization.can?(admin(), :edit_settings)
    end

    test "user cannot" do
      refute Authorization.can?(user(), :manage_users)
      refute Authorization.can?(user(), :edit_settings)
    end

    test "anon cannot" do
      refute Authorization.can?(anon(), :manage_users)
      refute Authorization.can?(anon(), :edit_settings)
    end
  end

  describe "can?/3 :delete_review" do
    test "admin can delete any review" do
      assert Authorization.can?(admin(), :delete_review, %{user_id: Ecto.UUID.generate()})
    end

    test "user can delete their own review" do
      scope = user()
      assert Authorization.can?(scope, :delete_review, %{user_id: scope.user.id})
    end

    test "user cannot delete someone else's review" do
      refute Authorization.can?(user(), :delete_review, %{user_id: Ecto.UUID.generate()})
    end

    test "anon cannot delete any review" do
      refute Authorization.can?(anon(), :delete_review, %{user_id: Ecto.UUID.generate()})
    end
  end

  describe "can?/3 :delete_comment" do
    test "admin can delete any comment" do
      assert Authorization.can?(admin(), :delete_comment, %{user_id: Ecto.UUID.generate()})
    end

    test "user can delete their own comment" do
      scope = user()
      assert Authorization.can?(scope, :delete_comment, %{user_id: scope.user.id})
    end

    test "user cannot delete someone else's comment" do
      refute Authorization.can?(user(), :delete_comment, %{user_id: Ecto.UUID.generate()})
    end

    test "anon cannot delete any comment" do
      refute Authorization.can?(anon(), :delete_comment, %{user_id: Ecto.UUID.generate()})
    end
  end

  describe "can?/3 :delete_user" do
    test "admin can delete any user" do
      assert Authorization.can?(admin(), :delete_user, %User{id: Ecto.UUID.generate()})
    end

    test "user cannot delete anyone" do
      refute Authorization.can?(user(), :delete_user, %User{id: Ecto.UUID.generate()})
    end

    test "anon cannot delete anyone" do
      refute Authorization.can?(anon(), :delete_user, %User{id: Ecto.UUID.generate()})
    end
  end
end
