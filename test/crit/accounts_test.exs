defmodule Crit.AccountsTest do
  use Crit.DataCase, async: true

  alias Crit.Accounts

  # Matches the normalized user map assent returns for GitHub and OIDC providers.
  # "sub" is the provider's unique user ID.
  @oauth_params %{
    "sub" => "99887766",
    "name" => "Ada Lovelace",
    "email" => "ada@example.com",
    "picture" => "https://avatars.githubusercontent.com/u/99887766"
  }

  describe "find_or_create_from_oauth/2" do
    test "creates a new user on first login" do
      assert {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      assert user.provider == "github"
      assert user.provider_uid == "99887766"
      assert user.name == "Ada Lovelace"
      assert user.email == "ada@example.com"
      assert user.avatar_url == "https://avatars.githubusercontent.com/u/99887766"
    end

    test "returns existing user on subsequent login" do
      {:ok, user1} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, user2} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      assert user1.id == user2.id
    end

    test "updates profile on subsequent login" do
      {:ok, _} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      updated = Map.merge(@oauth_params, %{"name" => "Ada Byron", "email" => "ada2@example.com"})
      {:ok, user} = Accounts.find_or_create_from_oauth("github", updated)

      assert user.name == "Ada Byron"
      assert user.email == "ada2@example.com"
    end

    test "treats same uid from different providers as different users" do
      {:ok, github_user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, custom_user} = Accounts.find_or_create_from_oauth("custom", @oauth_params)
      refute github_user.id == custom_user.id
    end

    test "returns error when sub (provider uid) is missing" do
      assert {:error, _changeset} =
               Accounts.find_or_create_from_oauth("github", %{"name" => "No ID"})
    end
  end

  describe "get_user/1" do
    test "returns user by id" do
      {:ok, created} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      assert {:ok, found} = Accounts.get_user(created.id)
      assert found.id == created.id
    end

    test "returns error for unknown id" do
      assert {:error, :not_found} = Accounts.get_user(0)
    end
  end
end
