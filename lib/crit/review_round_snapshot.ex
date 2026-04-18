defmodule Crit.ReviewRoundSnapshot do
  use Crit.Schema

  schema "review_round_snapshots" do
    field :round_number, :integer, default: 1
    field :file_path, :string
    field :content, :string
    field :position, :integer, default: 0

    field :status, Ecto.Enum,
      values: [:added, :modified, :deleted, :renamed, :removed],
      default: :modified

    belongs_to :review, Crit.Review
    timestamps(updated_at: false)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:round_number, :file_path, :content, :position, :status])
    |> validate_required([:round_number, :file_path])
    |> then(fn cs ->
      if Ecto.Changeset.get_field(cs, :status) == :removed do
        # Removed (orphaned) files may have empty content; default to "" if nil
        cs
        |> Ecto.Changeset.put_change(:content, Ecto.Changeset.get_field(cs, :content) || "")
      else
        cs
        |> validate_required([:content])
      end
    end)
    |> validate_length(:file_path, max: 500)
    |> validate_length(:content, max: 2_097_152, message: "must be at most 2 MB")
  end
end
