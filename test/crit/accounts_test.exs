defmodule Crit.AccountsTest do
  use Crit.DataCase, async: true

  alias Crit.Accounts
  alias Crit.User

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

    test "updates email and avatar but preserves name on subsequent login" do
      {:ok, _} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      updated =
        Map.merge(@oauth_params, %{
          "name" => "Ada Byron",
          "email" => "ada2@example.com",
          "picture" => "https://example.com/new-avatar.png"
        })

      {:ok, user} = Accounts.find_or_create_from_oauth("github", updated)

      # Name from OAuth profile must NOT clobber the stored value.
      assert user.name == "Ada Lovelace"
      assert user.email == "ada2@example.com"
      assert user.avatar_url == "https://example.com/new-avatar.png"
    end

    test "preserves a user-edited name across re-login" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, _} = Accounts.update_user_profile(user, %{"name" => "Custom"})

      changed = Map.put(@oauth_params, "name", "Different From OAuth")
      {:ok, reloaded} = Accounts.find_or_create_from_oauth("github", changed)

      assert reloaded.name == "Custom"
    end

    test "treats same uid from different providers as different users" do
      {:ok, github_user} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      custom_params = Map.put(@oauth_params, "email", "ada+custom@example.com")
      {:ok, custom_user} = Accounts.find_or_create_from_oauth("custom", custom_params)
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

      other_params =
        @oauth_params
        |> Map.put("sub", "other_uid")
        |> Map.put("email", "other@example.com")

      {:ok, user2} = Accounts.find_or_create_from_oauth("github", other_params)
      {:ok, {_plaintext, token}} = Accounts.create_token(user2, "User2 token")

      assert {:error, :not_found} = Accounts.revoke_token(token.id, user1.id)
    end

    test "returns error when token id does not exist" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      assert {:error, :not_found} = Accounts.revoke_token(Ecto.UUID.generate(), user.id)
    end
  end

  describe "revoke_token_by_plaintext/1" do
    test "deletes the token and returns :ok" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, {plaintext, _token}} = Accounts.create_token(user, "To revoke")

      assert :ok = Accounts.revoke_token_by_plaintext(plaintext)
      assert {:error, :invalid} = Accounts.verify_token(plaintext)
    end

    test "returns :ok when token does not exist (idempotent)" do
      assert :ok = Accounts.revoke_token_by_plaintext("crit_nonexistent_token")
    end
  end

  describe "register_user/1" do
    alias Crit.AccountsFixtures

    test "creates a user with valid attributes" do
      attrs = AccountsFixtures.valid_user_attributes()
      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.email == attrs.email
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
    end

    test "rejects duplicate email case-insensitively" do
      attrs = AccountsFixtures.valid_user_attributes(email: "Dup@Example.com")
      assert {:ok, _user} = Accounts.register_user(attrs)

      dup_attrs =
        AccountsFixtures.valid_user_attributes(email: "dup@EXAMPLE.com")

      assert {:error, changeset} = Accounts.register_user(dup_attrs)
      assert %{email: [_ | _]} = errors_on(changeset)
    end
  end

  describe "get_user_by_email/1" do
    alias Crit.AccountsFixtures

    test "looks up a user case-insensitively" do
      user = AccountsFixtures.user_fixture(email: "Mixed@Case.com")
      assert found = Accounts.get_user_by_email("mixed@case.com")
      assert found.id == user.id
      assert found2 = Accounts.get_user_by_email("MIXED@CASE.COM")
      assert found2.id == user.id
    end

    test "returns nil for unknown email" do
      assert is_nil(Accounts.get_user_by_email("nobody@example.com"))
    end
  end

  describe "get_user_by_email_and_password/2" do
    alias Crit.AccountsFixtures

    test "returns the user when the password is correct" do
      password = AccountsFixtures.valid_user_password()
      user = AccountsFixtures.user_fixture(%{password: password})
      assert found = Accounts.get_user_by_email_and_password(user.email, password)
      assert found.id == user.id
    end

    test "returns nil when the password is wrong" do
      user = AccountsFixtures.user_fixture()
      assert is_nil(Accounts.get_user_by_email_and_password(user.email, "wrong password"))
    end

    test "returns nil when the email is unknown" do
      assert is_nil(
               Accounts.get_user_by_email_and_password(
                 "nobody@example.com",
                 AccountsFixtures.valid_user_password()
               )
             )
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

      other_params =
        @oauth_params
        |> Map.put("sub", "other_uid2")
        |> Map.put("email", "other2@example.com")

      {:ok, user2} = Accounts.find_or_create_from_oauth("github", other_params)
      {:ok, {_, _t}} = Accounts.create_token(user2, "User2 token")

      assert Accounts.list_tokens(user1.id) == []
    end
  end

  describe "update_user_password/3" do
    alias Crit.AccountsFixtures

    test "updates with correct current password" do
      user = AccountsFixtures.user_fixture()

      {:ok, updated} =
        Accounts.update_user_password(
          user,
          AccountsFixtures.valid_user_password(),
          %{password: "another-strong-pw-1234", password_confirmation: "another-strong-pw-1234"}
        )

      assert User.valid_password?(updated, "another-strong-pw-1234")
    end

    test "rejects wrong current password" do
      user = AccountsFixtures.user_fixture()

      {:error, changeset} =
        Accounts.update_user_password(user, "wrong", %{
          password: "another-strong-pw-1234",
          password_confirmation: "another-strong-pw-1234"
        })

      assert "is not valid" in errors_on(changeset).current_password
    end
  end

  describe "find_or_create_from_oauth/2 — email linking" do
    alias Crit.AccountsFixtures

    test "links to an existing local-only user with matching email" do
      local = AccountsFixtures.user_fixture(email: "shared@example.com")

      {:ok, linked} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid-123",
          "email" => "shared@example.com",
          "name" => "OAuth"
        })

      assert linked.id == local.id
      assert linked.provider == "github"
      assert linked.provider_uid == "uid-123"
      assert is_binary(linked.hashed_password)
    end

    test "still creates a new row when emails don't match" do
      _local = AccountsFixtures.user_fixture(email: "alice@example.com")

      {:ok, new_user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "uid-999",
          "email" => "bob@example.com",
          "name" => "Bob"
        })

      refute new_user.hashed_password
      assert new_user.email == "bob@example.com"
    end
  end

  describe "update_user_profile/2" do
    alias Crit.AccountsFixtures

    test "updates name only when email key is absent" do
      user = AccountsFixtures.user_fixture()
      original_email = user.email

      {:ok, updated} = Accounts.update_user_profile(user, %{"name" => "Just A Name"})
      assert updated.name == "Just A Name"
      assert updated.email == original_email
    end

    test "updates name and email atomically when both present" do
      user = AccountsFixtures.user_fixture()
      new_email = "combined-#{System.unique_integer([:positive])}@example.com"

      {:ok, updated} =
        Accounts.update_user_profile(user, %{"name" => "Both", "email" => new_email})

      assert updated.name == "Both"
      assert updated.email == new_email
    end

    test "returns error changeset on invalid email" do
      user = AccountsFixtures.user_fixture()

      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.update_user_profile(user, %{"name" => "x", "email" => "bogus"})

      assert "must have the @ sign and no spaces" in errors_on(cs).email
    end

    test "rejects empty email when key is present (treated as required)" do
      user = AccountsFixtures.user_fixture()

      assert {:error, %Ecto.Changeset{} = cs} =
               Accounts.update_user_profile(user, %{"name" => "x", "email" => ""})

      assert "can't be blank" in errors_on(cs).email
    end

    test "accepts oversize-bordering name (80 chars) and rejects 81" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, _} =
               Accounts.update_user_profile(user, %{"name" => String.duplicate("a", 80)})

      assert {:error, _} =
               Accounts.update_user_profile(user, %{"name" => String.duplicate("a", 81)})
    end
  end
end
