defmodule Crit.ReviewsFixtures do
  @moduledoc false

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
    opts = if user_id = attrs[:user_id], do: [user_id: user_id], else: []

    {:ok, review} =
      Reviews.create_review(
        attrs[:files],
        attrs[:review_round],
        attrs[:comments] || [],
        [],
        opts
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

    {:ok, comment} =
      attrs
      |> valid_comment_attrs()
      |> then(&Reviews.create_comment(review, &1, identity, display_name))

    comment
  end
end
