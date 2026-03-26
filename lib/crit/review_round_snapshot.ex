defmodule Crit.ReviewRoundSnapshot do
  use Crit.Schema

  schema "review_round_snapshots" do
    field :round_number, :integer, default: 1
    field :file_path, :string
    field :content, :string
    field :position, :integer, default: 0
    belongs_to :review, Crit.Review
    timestamps(updated_at: false)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:round_number, :file_path, :content, :position])
    |> validate_required([:round_number, :file_path, :content])
    |> validate_length(:file_path, max: 500)
    |> validate_length(:content, max: 2_097_152, message: "must be at most 2 MB")
  end
end
