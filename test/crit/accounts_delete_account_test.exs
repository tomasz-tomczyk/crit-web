defmodule Crit.AccountsDeleteAccountTest do
  use Crit.DataCase, async: true

  alias Crit.{Accounts, Repo, User, UserApiToken}

  @oauth_params %{
    "sub" => "delete_test_uid",
    "name" => "Delete Test",
    "email" => "delete@example.com",
    "picture" => "https://example.com/avatar.jpg"
  }

  describe "delete_account/1" do
    test "deletes the user" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      assert :ok = Accounts.delete_account(user)
      assert is_nil(Repo.get(User, user.id))
    end

    test "cascades delete to API tokens" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, {_plaintext, token}} = Accounts.create_token(user, "my token")

      assert :ok = Accounts.delete_account(user)
      assert is_nil(Repo.get(UserApiToken, token.id))
    end

    test "nilifies user_id on reviews (reviews preserved)" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      {:ok, review} =
        Crit.Reviews.create_review(
          [%{"path" => "test.md", "content" => "# Test"}],
          0,
          [],
          [],
          user_id: user.id
        )

      assert :ok = Accounts.delete_account(user)

      updated_review = Repo.get!(Crit.Review, review.id)
      assert is_nil(updated_review.user_id)
    end

    test "returns error for non-existent user" do
      fake_user = %User{id: Ecto.UUID.generate()}
      assert {:error, :not_found} = Accounts.delete_account(fake_user)
    end
  end
end
