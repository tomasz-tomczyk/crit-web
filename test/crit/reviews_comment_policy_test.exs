defmodule Crit.ReviewsCommentPolicyTest do
  use Crit.DataCase, async: true

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  defp owner_user_fixture do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "cp-#{System.unique_integer([:positive])}",
        "email" => "cp-#{System.unique_integer([:positive])}@example.com",
        "name" => "CP Owner"
      })

    user
  end

  defp create_review_for(user) do
    {:ok, review} =
      Reviews.create_review(
        Scope.for_user(user),
        [%{"path" => "a.md", "content" => "x"}],
        0,
        []
      )

    review
  end

  describe "update_review/3 — comment_policy" do
    test "owner can change comment_policy through every value" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)

      for policy <- [:logged_in_only, :disallowed, :open] do
        assert {:ok, updated} = Reviews.update_review(scope, review.id, %{comment_policy: policy})
        assert updated.comment_policy == policy
      end
    end

    test "non-owner authenticated user cannot change comment_policy" do
      owner = owner_user_fixture()
      other = owner_user_fixture()
      review = create_review_for(owner)

      assert {:error, :unauthorized} =
               Reviews.update_review(Scope.for_user(other), review.id, %{comment_policy: :disallowed})
    end

    test "anonymous scope cannot change comment_policy" do
      owner = owner_user_fixture()
      review = create_review_for(owner)

      assert {:error, :unauthorized} =
               Reviews.update_review(Scope.for_visitor("ident"), review.id, %{comment_policy: :disallowed})
    end

    test "anonymous-owned review cannot have comment_policy changed by an authed visitor" do
      other = owner_user_fixture()

      {:ok, review} =
        Reviews.create_review(
          Scope.for_visitor("anon-#{System.unique_integer([:positive])}"),
          [%{"path" => "a.md", "content" => "x"}],
          0,
          []
        )

      assert review.user_id == nil

      assert {:error, :unauthorized} =
               Reviews.update_review(Scope.for_user(other), review.id, %{comment_policy: :disallowed})
    end

    test "missing review returns :not_found" do
      user = owner_user_fixture()

      assert {:error, :not_found} =
               Reviews.update_review(Scope.for_user(user), Ecto.UUID.generate(), %{comment_policy: :disallowed})
    end

    test "non-UUID review_id returns :not_found instead of raising" do
      user = owner_user_fixture()

      assert {:error, :not_found} =
               Reviews.update_review(Scope.for_user(user), "not-a-uuid", %{comment_policy: :disallowed})
    end

    test "invalid policy atom returns a changeset error" do
      user = owner_user_fixture()
      review = create_review_for(user)

      assert {:error, %Ecto.Changeset{}} =
               Reviews.update_review(Scope.for_user(user), review.id, %{comment_policy: :bogus})
    end

    test "unknown attrs keys are silently dropped by the changeset cast list" do
      user = owner_user_fixture()
      review = create_review_for(user)

      assert {:ok, updated} =
               Reviews.update_review(Scope.for_user(user), review.id, %{comment_policy: :disallowed, evil: 1})

      assert updated.comment_policy == :disallowed
    end

    test "setting comment_policy to its current value is a no-op success" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)
      assert review.comment_policy == :open

      assert {:ok, updated} = Reviews.update_review(scope, review.id, %{comment_policy: :open})
      assert updated.comment_policy == :open
    end

    test "string-keyed attrs work too (API-style payloads)" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)

      assert {:ok, updated} =
               Reviews.update_review(scope, review.id, %{"comment_policy" => "logged_in_only"})

      assert updated.comment_policy == :logged_in_only
    end

    test "broadcasts {:policy_changed, ...} on a real comment_policy change" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)
      assert review.comment_policy == :open

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      assert {:ok, _updated} =
               Reviews.update_review(scope, review.id, %{comment_policy: :disallowed})

      assert_receive {:policy_changed, review_id, %{comment_policy: :disallowed}}
      assert review_id == review.id
    end

    test "does NOT broadcast {:policy_changed, ...} when comment_policy is unchanged" do
      user = owner_user_fixture()
      scope = Scope.for_user(user)
      review = create_review_for(user)
      assert review.comment_policy == :open

      Phoenix.PubSub.subscribe(Crit.PubSub, "review:#{review.token}")

      assert {:ok, _updated} =
               Reviews.update_review(scope, review.id, %{comment_policy: :open})

      refute_receive {:policy_changed, _, _}, 100
    end
  end
end
