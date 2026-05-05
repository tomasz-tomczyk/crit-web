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

    field :scope, :string, default: "line"
    field :resolved, :boolean, default: false
    field :resolved_round, :integer
    field :external_id, :string
    belongs_to :review, Crit.Review
    belongs_to :parent, Crit.Comment
    belongs_to :user, Crit.User
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
      :resolved,
      :resolved_round,
      :scope,
      :external_id
    ])
    |> validate_required([:body])
    |> validate_inclusion(:scope, ["line", "file", "review"])
    |> validate_line_numbers()
    |> validate_length(:body, max: 51_200, message: "must be at most 50 KB")
    |> validate_length(:author_display_name, max: 40)
    |> validate_length(:file_path, max: 500)
  end

  defp validate_line_numbers(changeset) do
    scope = get_field(changeset, :scope) || "line"

    if scope == "line" do
      changeset
      |> validate_number(:start_line, greater_than: 0)
      |> validate_number(:end_line, greater_than: 0)
    else
      changeset
    end
  end

  @doc """
  Changeset for editing only the body of an existing comment. Mirrors the
  `:body` validations in `create_changeset/2` but does not re-validate
  immutable fields (start_line/end_line/scope) which the caller would
  otherwise need to re-pass.
  """
  def body_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, max: 51_200, message: "must be at most 50 KB")
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
