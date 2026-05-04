defmodule Crit.ReviewsVisibilityTest do
  use Crit.DataCase, async: true

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  defp owner_user_fixture do
    {:ok, user} =
      Crit.Accounts.find_or_create_from_oauth("github", %{
        "sub" => "vis-#{System.unique_integer([:positive])}",
        "email" => "vis-#{System.unique_integer([:positive])}@example.com",
        "name" => "Vis Owner"
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

  test "owner can promote an unlisted review to :public" do
    user = owner_user_fixture()
    scope = Scope.for_user(user)
    review = create_review_for(user)

    assert review.visibility == :unlisted
    assert {:ok, updated} = Reviews.make_public(scope, review.id)
    assert updated.visibility == :public
  end

  test "make_public/2 on an already-public review returns :already_public" do
    user = owner_user_fixture()
    scope = Scope.for_user(user)
    review = create_review_for(user)

    {:ok, _} = Reviews.make_public(scope, review.id)
    assert {:error, :already_public} = Reviews.make_public(scope, review.id)
  end

  test "non-owner authenticated user cannot promote" do
    owner = owner_user_fixture()
    other = owner_user_fixture()
    review = create_review_for(owner)

    assert {:error, :unauthorized} =
             Reviews.make_public(Scope.for_user(other), review.id)
  end

  test "anonymous scope cannot promote" do
    owner = owner_user_fixture()
    review = create_review_for(owner)

    assert {:error, :unauthorized} =
             Reviews.make_public(Scope.for_visitor("ident"), review.id)
  end

  test "missing review returns :not_found" do
    user = owner_user_fixture()

    assert {:error, :not_found} =
             Reviews.make_public(Scope.for_user(user), Ecto.UUID.generate())
  end

  test "non-UUID review_id returns :not_found instead of raising" do
    user = owner_user_fixture()

    assert {:error, :not_found} =
             Reviews.make_public(Scope.for_user(user), "not-a-uuid")
  end

  test "anonymous-owned review cannot be promoted by an authed visitor" do
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
             Reviews.make_public(Scope.for_user(other), review.id)
  end

  test "list_public_review_tokens/0 returns only public review tokens" do
    user = owner_user_fixture()
    scope = Scope.for_user(user)
    public_review = create_review_for(user)
    _unlisted_review = create_review_for(user)

    {:ok, _} = Reviews.make_public(scope, public_review.id)

    assert Reviews.list_public_review_tokens() == [public_review.token]
  end
end
