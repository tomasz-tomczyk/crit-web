defmodule Crit.AccountsAdminRoleTest do
  @moduledoc """
  Tests for the env-driven admin role: `apply_role_for_email/1` and the
  reconciliation pass invoked from `Crit.Release.migrate/0`.
  """
  use Crit.DataCase, async: false

  alias Crit.Accounts
  alias Crit.Repo
  alias Crit.User

  setup do
    prev = Application.get_env(:crit, :admin_emails, [])
    on_exit(fn -> Application.put_env(:crit, :admin_emails, prev) end)
    :ok
  end

  defp set_admin_emails(emails), do: Application.put_env(:crit, :admin_emails, emails)

  describe "apply_role_for_email/1" do
    test "promotes a user whose email is listed" do
      set_admin_emails(["alice@example.com"])
      user = oauth_user("alice@example.com")
      assert user.role == :admin
    end

    test "leaves a user as :user when not listed" do
      set_admin_emails(["someone-else@example.com"])
      user = oauth_user("alice@example.com")
      assert user.role == :user
    end

    test "demotes an admin whose email is no longer listed" do
      set_admin_emails(["alice@example.com"])
      user = oauth_user("alice@example.com")
      assert user.role == :admin

      set_admin_emails([])
      {:ok, demoted} = Accounts.apply_role_for_email(user)
      assert demoted.role == :user
    end

    test "matches case-insensitively against the user email" do
      # The runtime parser lowercases ADMIN_EMAILS. We verify the comparison
      # downcases the user's email too (defensive — emails are also stored
      # lowercased by the changesets).
      set_admin_emails(["alice@example.com"])
      user = oauth_user("AlIcE@Example.com")
      assert user.role == :admin
    end

    test "no-op when role already matches" do
      set_admin_emails([])
      user = oauth_user("alice@example.com")
      {:ok, same} = Accounts.apply_role_for_email(user)
      assert same.role == :user
    end
  end

  describe "register_user/1" do
    test "applies admin role when email is in ADMIN_EMAILS" do
      set_admin_emails(["new@example.com"])

      {:ok, user} =
        Accounts.register_user(%{email: "new@example.com", password: "hello world!"})

      assert user.role == :admin
    end
  end

  describe "Crit.Release.reconcile_admin_emails/0" do
    test "promotes newly-listed emails and demotes no-longer-listed emails" do
      set_admin_emails([])
      a = oauth_user("a@example.com")
      b = oauth_user("b@example.com")
      assert a.role == :user
      assert b.role == :user

      # Promote `a` only.
      set_admin_emails(["a@example.com"])
      Crit.Release.reconcile_admin_emails()

      assert Repo.get!(User, a.id).role == :admin
      assert Repo.get!(User, b.id).role == :user

      # Now swap: demote `a`, promote `b`.
      set_admin_emails(["b@example.com"])
      Crit.Release.reconcile_admin_emails()

      assert Repo.get!(User, a.id).role == :user
      assert Repo.get!(User, b.id).role == :admin
    end
  end

  defp oauth_user(email) do
    {:ok, user} =
      Accounts.find_or_create_from_oauth("github", %{
        "sub" => "uid_#{System.unique_integer([:positive])}",
        "name" => "Test",
        "email" => email,
        "picture" => nil
      })

    user
  end
end
