defmodule Crit.Comment do
  use Crit.Schema

  schema "comments" do
    field :start_line, :integer
    field :end_line, :integer
    field :body, :string
    field :author_identity, :string
    field :author_display_name, :string
    field :review_round, :integer, default: 0
    field :file_path, :string
    field :quote, :string

    field :resolved, :boolean, default: false
    belongs_to :review, Crit.Review
    belongs_to :parent, Crit.Comment
    has_many :replies, Crit.Comment, foreign_key: :parent_id, preload_order: [asc: :inserted_at]

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a comment from an imported payload."
  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :id,
      :start_line,
      :end_line,
      :body,
      :author_identity,
      :author_display_name,
      :review_round,
      :file_path,
      :quote,
      :resolved
    ])
    |> validate_required([:start_line, :end_line, :body])
    |> validate_number(:start_line, greater_than: 0)
    |> validate_number(:end_line, greater_than: 0)
    |> validate_length(:body, max: 51_200, message: "must be at most 50 KB")
    |> validate_length(:author_display_name, max: 40)
    |> validate_length(:file_path, max: 500)
  end

  @doc "Changeset for creating a reply (comment with parent_id)."
  def reply_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body, :author_identity, :author_display_name])
    |> validate_required([:body])
    |> validate_length(:body, max: 51_200, message: "must be at most 50 KB")
    |> validate_length(:author_display_name, max: 40)
  end
end
