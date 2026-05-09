defmodule Crit.AuthorizationTest do
  use Crit.DataCase, async: false

  alias Crit.Authorization
  alias Crit.User

  defp admin, do: %User{id: Ecto.UUID.generate(), role: :admin, email: "alice@example.com"}
  defp user, do: %User{id: Ecto.UUID.generate(), role: :user, email: "bob@example.com"}

  describe "admin?/1" do
    test "true for admin role" do
      assert Authorization.admin?(admin())
    end

    test "false for user role" do
      refute Authorization.admin?(user())
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
  end

  describe "can?/3 :delete_review" do
    test "admin can delete any review" do
      assert Authorization.can?(admin(), :delete_review, %{user_id: Ecto.UUID.generate()})
    end

    test "user can delete their own review" do
      u = user()
      assert Authorization.can?(u, :delete_review, %{user_id: u.id})
    end

    test "user cannot delete someone else's review" do
      refute Authorization.can?(user(), :delete_review, %{user_id: Ecto.UUID.generate()})
    end
  end

  describe "can?/3 :delete_comment" do
    test "admin can delete any comment" do
      assert Authorization.can?(admin(), :delete_comment, %{user_id: Ecto.UUID.generate()})
    end

    test "user can delete their own comment" do
      u = user()
      assert Authorization.can?(u, :delete_comment, %{user_id: u.id})
    end

    test "user cannot delete someone else's comment" do
      refute Authorization.can?(user(), :delete_comment, %{user_id: Ecto.UUID.generate()})
    end
  end

  describe "can?/3 :delete_user" do
    test "admin can delete any user" do
      assert Authorization.can?(admin(), :delete_user, user())
      assert Authorization.can?(admin(), :delete_user, admin())
    end

    test "user cannot delete anyone" do
      refute Authorization.can?(user(), :delete_user, user())
      refute Authorization.can?(user(), :delete_user, admin())
    end
  end
end
