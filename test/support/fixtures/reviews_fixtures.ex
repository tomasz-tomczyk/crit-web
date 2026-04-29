defmodule Crit.ReviewsFixtures do
  @moduledoc false

  alias Crit.Accounts.Scope
  alias Crit.Reviews

  def valid_review_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      files: [
        %{
          "path" => "test.md",
          "content" => "# Test Document\n\nLine 1\nLine 2\nLine 3\nLine 4\nLine 5"
        }
      ],
      review_round: 0
    })
  end

  def review_fixture(attrs \\ %{}) do
    attrs = valid_review_attrs(attrs)

    scope =
      case attrs[:user_id] do
        nil -> Scope.for_visitor("fixture-#{System.unique_integer([:positive])}")
        user_id -> Scope.for_user(%Crit.User{id: user_id})
      end

    {:ok, review} =
      Reviews.create_review(
        scope,
        attrs[:files],
        attrs[:review_round],
        attrs[:comments] || [],
        []
      )

    Reviews.get_by_token(review.token)
  end

  def valid_comment_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "start_line" => 1,
      "end_line" => 1,
      "body" => "Test comment"
    })
  end

  def comment_fixture(%Crit.Review{} = review, attrs \\ %{}) do
    identity = attrs[:identity] || Ecto.UUID.generate()
    display_name = attrs[:display_name]
    scope = Scope.for_visitor(identity, display_name)

    {:ok, comment} =
      attrs
      |> valid_comment_attrs()
      |> then(&Reviews.create_comment(scope, review, &1))

    comment
  end
end
