defmodule Crit.Review do
  use Crit.Schema

  schema "reviews" do
    field :token, :string
    field :delete_token, :string
    field :last_activity_at, :utc_datetime
    field :review_round, :integer, default: 0
    field :cli_args, {:array, :string}, default: []

    belongs_to :user, Crit.User, type: :binary_id

    has_many :comments, Crit.Comment
    has_many :round_snapshots, Crit.ReviewRoundSnapshot

    field :files, {:array, :map}, virtual: true, default: []

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a new review."
  def create_changeset(review, attrs) do
    review
    |> cast(attrs, [:review_round, :cli_args])
    |> put_token()
    |> put_delete_token()
    |> put_last_activity_at()
  end

  defp put_token(changeset) do
    put_change(changeset, :token, Nanoid.generate(21))
  end

  defp put_delete_token(changeset) do
    put_change(changeset, :delete_token, Nanoid.generate(21))
  end

  defp put_last_activity_at(changeset) do
    put_change(changeset, :last_activity_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
