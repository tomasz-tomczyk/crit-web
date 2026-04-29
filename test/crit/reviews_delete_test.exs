defmodule Crit.ReviewsDeleteTest do
  use Crit.DataCase

  alias Crit.Accounts.Scope
  alias Crit.{Reviews, Review, Repo}

  defp insert_review do
    scope = Scope.for_visitor("delete-test-#{System.unique_integer([:positive])}")

    {:ok, review} =
      Reviews.create_review(scope, [%{"path" => "test.md", "content" => "# Hello"}], 0, [])

    review
  end

  test "delete_by_delete_token/1 deletes the review and returns :ok" do
    review = insert_review()
    assert :ok = Reviews.delete_by_delete_token(review.delete_token)
    assert is_nil(Repo.get(Review, review.id))
  end

  test "delete_by_delete_token/1 returns :not_found for unknown token" do
    assert {:error, :not_found} = Reviews.delete_by_delete_token("nonexistent_token_xyz")
  end
end
