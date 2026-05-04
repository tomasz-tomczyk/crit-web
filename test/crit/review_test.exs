defmodule Crit.ReviewTest do
  use Crit.DataCase, async: true

  alias Crit.Review

  describe "create_changeset/2" do
    test "valid attrs produce valid changeset" do
      changeset = Review.create_changeset(%Review{}, %{})
      assert changeset.valid?
    end

    test "generates token automatically" do
      changeset = Review.create_changeset(%Review{}, %{})
      assert changeset.changes[:token] != nil
      assert String.length(changeset.changes[:token]) == 21
    end

    test "generates delete_token automatically" do
      changeset = Review.create_changeset(%Review{}, %{})
      assert changeset.changes[:delete_token] != nil
      assert String.length(changeset.changes[:delete_token]) == 21
    end

    test "token and delete_token are different" do
      changeset = Review.create_changeset(%Review{}, %{})
      assert changeset.changes[:token] != changeset.changes[:delete_token]
    end

    test "review_round defaults to 0 when not provided" do
      changeset = Review.create_changeset(%Review{}, %{})
      refute Map.has_key?(changeset.changes, :review_round)
    end

    test "accepts optional review_round" do
      changeset = Review.create_changeset(%Review{}, %{"review_round" => 2})
      assert changeset.valid?
      assert changeset.changes[:review_round] == 2
    end
  end

  describe "update_changeset/2" do
    test "default comment_policy is :open" do
      {:ok, review} =
        %Review{}
        |> Review.create_changeset(%{})
        |> Crit.Repo.insert()

      assert review.comment_policy == :open
    end

    test "update_changeset/2 accepts valid comment_policy values" do
      review = %Review{comment_policy: :open}
      assert Review.update_changeset(review, %{comment_policy: :open}).valid?
      assert Review.update_changeset(review, %{comment_policy: :logged_in_only}).valid?
      assert Review.update_changeset(review, %{comment_policy: :disallowed}).valid?
    end

    test "update_changeset/2 rejects unknown comment_policy values" do
      review = %Review{comment_policy: :open}
      refute Review.update_changeset(review, %{comment_policy: :secret}).valid?
    end
  end

  describe "visibility" do
    test "default visibility is :unlisted" do
      {:ok, review} =
        %Review{}
        |> Review.create_changeset(%{})
        |> Crit.Repo.insert()

      assert review.visibility == :unlisted
    end

    test "visibility_changeset/2 accepts :public and :unlisted, rejects others" do
      review = %Review{visibility: :unlisted}
      assert Review.visibility_changeset(review, %{visibility: :public}).valid?
      assert Review.visibility_changeset(review, %{visibility: :unlisted}).valid?
      refute Review.visibility_changeset(review, %{visibility: :secret}).valid?
    end
  end
end
