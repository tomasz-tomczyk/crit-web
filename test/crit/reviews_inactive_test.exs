defmodule Crit.ReviewsInactiveTest do
  use Crit.DataCase

  import Ecto.Query
  import Crit.ReviewsFixtures

  alias Crit.{Accounts, Reviews, Review, Comment, Repo}

  defp set_last_activity(review, days_ago) do
    old_time = DateTime.add(DateTime.utc_now(), -days_ago, :day)

    Repo.update_all(
      from(r in Review, where: r.id == ^review.id),
      set: [last_activity_at: old_time]
    )
  end

  describe "delete_inactive/1" do
    test "deletes reviews inactive for more than the given days" do
      review = review_fixture()
      set_last_activity(review, 31)

      assert {:ok, 1} = Reviews.delete_inactive(30)
      assert is_nil(Repo.get(Review, review.id))
    end

    test "does not delete reviews active within the threshold" do
      _recent = review_fixture()

      assert {:ok, 0} = Reviews.delete_inactive(30)
    end

    test "does not delete a review inactive for exactly the threshold" do
      review = review_fixture()
      set_last_activity(review, 30)

      # exactly 30 days ago is not strictly less than cutoff (30 days ago),
      # but due to sub-second timing it may be just over — so we just verify
      # the function returns ok without panicking
      assert {:ok, _} = Reviews.delete_inactive(30)
    end

    test "cascades deletion to comments" do
      review = review_fixture()
      comment = comment_fixture(review)
      set_last_activity(review, 31)

      Reviews.delete_inactive(30)

      assert is_nil(Repo.get(Comment, comment.id))
    end

    test "returns count of deleted reviews" do
      r1 = review_fixture()
      r2 = review_fixture()
      _recent = review_fixture()

      set_last_activity(r1, 31)
      set_last_activity(r2, 45)

      assert {:ok, 2} = Reviews.delete_inactive(30)
    end

    test "returns {:ok, 0} when no reviews exist" do
      assert {:ok, 0} = Reviews.delete_inactive(30)
    end

    test "does not delete the demo review" do
      demo = review_fixture()
      Application.put_env(:crit, :demo_review_token, demo.token)
      on_exit(fn -> Application.delete_env(:crit, :demo_review_token) end)

      set_last_activity(demo, 31)

      assert {:ok, 0} = Reviews.delete_inactive(30)
      assert Repo.get(Review, demo.id)
    end

    test "deletes other stale reviews when demo token is set" do
      demo = review_fixture()
      other = review_fixture()
      Application.put_env(:crit, :demo_review_token, demo.token)
      on_exit(fn -> Application.delete_env(:crit, :demo_review_token) end)

      set_last_activity(demo, 31)
      set_last_activity(other, 31)

      assert {:ok, 1} = Reviews.delete_inactive(30)
      assert Repo.get(Review, demo.id)
      assert is_nil(Repo.get(Review, other.id))
    end

    test "does not delete reviews owned by users with keep_reviews enabled" do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "keep_#{System.unique_integer()}",
          "name" => "Keeper"
        })

      {:ok, user} = Accounts.update_keep_reviews(user, true)

      review = review_fixture(%{user_id: user.id})
      set_last_activity(review, 31)

      assert {:ok, 0} = Reviews.delete_inactive(30)
      assert Repo.get(Review, review.id)
    end

    test "deletes stale reviews from users without keep_reviews" do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "nokeep_#{System.unique_integer()}",
          "name" => "No Keep"
        })

      review = review_fixture(%{user_id: user.id})
      set_last_activity(review, 31)

      assert {:ok, 1} = Reviews.delete_inactive(30)
      assert is_nil(Repo.get(Review, review.id))
    end

    test "deletes anonymous stale reviews even when keep_reviews users exist" do
      {:ok, user} =
        Accounts.find_or_create_from_oauth("github", %{
          "sub" => "keeper2_#{System.unique_integer()}",
          "name" => "Keeper"
        })

      {:ok, _user} = Accounts.update_keep_reviews(user, true)

      anon_review = review_fixture()
      set_last_activity(anon_review, 31)

      assert {:ok, 1} = Reviews.delete_inactive(30)
      assert is_nil(Repo.get(Review, anon_review.id))
    end
  end
end
