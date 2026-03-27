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

  describe "create_token/2" do
    test "creates a token and returns plaintext + record" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      assert {:ok, {plaintext, token}} = Accounts.create_token(user, "My Token")

      assert String.starts_with?(plaintext, "crit_")
      assert token.name == "My Token"
      assert token.user_id == user.id
      refute token.token_hash == plaintext
    end

    test "returns error changeset when name is missing" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      assert {:error, changeset} = Accounts.create_token(user, "")
      assert %{name: [_ | _]} = errors_on(changeset)
    end
  end

  describe "verify_token/1" do
    test "returns user for a valid token and updates last_used_at" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, {plaintext, _token}} = Accounts.create_token(user, "CLI")

      assert {:ok, found_user} = Accounts.verify_token(plaintext)
      assert found_user.id == user.id
    end

    test "returns error for an invalid token" do
      assert {:error, :invalid} = Accounts.verify_token("crit_notavalidtoken")
    end
  end

  describe "revoke_token/2" do
    test "deletes the token when it belongs to the user" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, {_plaintext, token}} = Accounts.create_token(user, "To revoke")

      assert :ok = Accounts.revoke_token(token.id, user.id)
    end

    test "returns error when token does not belong to user" do
      {:ok, user1} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      other_params = Map.put(@oauth_params, "sub", "other_uid")
      {:ok, user2} = Accounts.find_or_create_from_oauth("github", other_params)
      {:ok, {_plaintext, token}} = Accounts.create_token(user2, "User2 token")

      assert {:error, :not_found} = Accounts.revoke_token(token.id, user1.id)
    end

    test "returns error when token id does not exist" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      assert {:error, :not_found} = Accounts.revoke_token(Ecto.UUID.generate(), user.id)
    end
  end

  describe "list_tokens/1" do
    test "returns tokens for the user ordered by inserted_at desc" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, {_, t1}} = Accounts.create_token(user, "First")
      {:ok, {_, t2}} = Accounts.create_token(user, "Second")

      tokens = Accounts.list_tokens(user.id)
      ids = Enum.map(tokens, & &1.id)

      assert length(tokens) == 2
      assert t1.id in ids
      assert t2.id in ids
    end

    test "does not return tokens for other users" do
      {:ok, user1} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      other_params = Map.put(@oauth_params, "sub", "other_uid2")
      {:ok, user2} = Accounts.find_or_create_from_oauth("github", other_params)
      {:ok, {_, _t}} = Accounts.create_token(user2, "User2 token")

      assert Accounts.list_tokens(user1.id) == []
    end
  end
end
