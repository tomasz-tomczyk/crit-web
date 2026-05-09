defmodule Crit.AuthorizationTest do
  use Crit.DataCase, async: false

  alias Crit.Authorization
  alias Crit.User

  setup do
    prev = Application.get_env(:crit, :admin_emails, [])
    Application.put_env(:crit, :admin_emails, ["pinned@example.com"])
    on_exit(fn -> Application.put_env(:crit, :admin_emails, prev) end)
    :ok
  end

  defp admin, do: %User{id: Ecto.UUID.generate(), role: :admin, email: "alice@example.com"}
  defp user, do: %User{id: Ecto.UUID.generate(), role: :user, email: "bob@example.com"}

  defp pinned_admin,
    do: %User{id: Ecto.UUID.generate(), role: :admin, email: "pinned@example.com"}

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

  describe "env_pinned?/1" do
    test "true when email is in ADMIN_EMAILS" do
      assert Authorization.env_pinned?(pinned_admin())
    end

    test "false when email is not in ADMIN_EMAILS" do
      refute Authorization.env_pinned?(admin())
    end

    test "case-insensitive" do
      u = %User{id: Ecto.UUID.generate(), role: :admin, email: "PINNED@example.COM"}
      assert Authorization.env_pinned?(u)
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
    test "admin can delete a non-pinned user" do
      assert Authorization.can?(admin(), :delete_user, user())
    end

    test "admin cannot delete a pinned user" do
      refute Authorization.can?(admin(), :delete_user, pinned_admin())
    end

    test "user cannot delete anyone" do
      refute Authorization.can?(user(), :delete_user, user())
      refute Authorization.can?(user(), :delete_user, admin())
    end
  end
end
