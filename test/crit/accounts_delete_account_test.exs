defmodule Crit.AccountsDeleteUserTest do
  use Crit.DataCase, async: true

  alias Crit.{Accounts, Comment, Repo, Review, User, UserApiToken}
  alias Crit.Accounts.Scope
  alias Crit.DeviceCodes
  alias Crit.DeviceCode

  @oauth_params %{
    "sub" => "delete_test_uid",
    "name" => "Delete Test",
    "email" => "delete@example.com",
    "picture" => "https://example.com/avatar.jpg"
  }

  describe "delete_user/1" do
    test "deletes the user" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      assert :ok = Accounts.delete_user(user)
      assert is_nil(Repo.get(User, user.id))
    end

    test "cascades delete to API tokens" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)
      {:ok, {_plaintext, token}} = Accounts.create_token(user, "my token")

      assert :ok = Accounts.delete_user(user)
      assert is_nil(Repo.get(UserApiToken, token.id))
    end

    test "hard-cascades reviews owned by the user" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      {:ok, review} =
        Crit.Reviews.create_review(
          Scope.for_user(user),
          [%{"path" => "test.md", "content" => "# Test"}],
          0,
          [],
          []
        )

      assert :ok = Accounts.delete_user(user)
      assert is_nil(Repo.get(Review, review.id))
    end

    test "hard-cascades comments authored by the user" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      # Create a review owned by another user, then a comment by `user` on it.
      {:ok, owner} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "owner_uid",
          "name" => "Owner",
          "email" => "owner@example.com"
        })

      {:ok, review} =
        Crit.Reviews.create_review(
          Scope.for_user(owner),
          [%{"path" => "test.md", "content" => "# Test"}],
          0,
          [],
          []
        )

      {:ok, comment} =
        Crit.Reviews.create_comment(
          Scope.for_user(user),
          review,
          %{"start_line" => 1, "end_line" => 1, "body" => "hello", "scope" => "line"}
        )

      assert :ok = Accounts.delete_user(user)
      assert is_nil(Repo.get(Comment, comment.id))
      # The review (owned by `owner`) is preserved.
      assert Repo.get(Review, review.id)
    end

    test "cascades device codes" do
      {:ok, user} = Accounts.find_or_create_from_oauth("github", @oauth_params)

      {:ok, %{record: dc}} = DeviceCodes.create_device_code()
      {:ok, _} = DeviceCodes.authorize_device_code(dc.id, user)

      assert :ok = Accounts.delete_user(user)
      assert is_nil(Repo.get(DeviceCode, dc.id))
    end

    test "returns error for non-existent user" do
      fake_user = %User{id: Ecto.UUID.generate()}
      assert {:error, :not_found} = Accounts.delete_user(fake_user)
    end
  end
end
