defmodule Crit.ReviewRoundSnapshot do
  use Crit.Schema

  schema "review_round_snapshots" do
    field :round_number, :integer, default: 1
    field :file_path, :string
    field :content, :string
    field :position, :integer, default: 0

    field :status, Ecto.Enum,
      values: [:modified, :removed],
      default: :modified

    field :generated, :boolean, default: false
    field :encoding, :string

    # View hints from crit's `languages` config. `lang` is the highlight
    # grammar; `file_type` overrides the extension-based document/code choice.
    # Both are nil for shares from CLIs that predate the config.
    field :lang, :string
    field :file_type, :string

    belongs_to :review, Crit.Review
    timestamps(updated_at: false)
  end

  @file_types ~w(markdown code)
  @lang_max_length 64

  def file_types, do: @file_types
  def lang_max_length, do: @lang_max_length

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :round_number,
      :file_path,
      :content,
      :position,
      :status,
      :generated,
      :encoding,
      :lang,
      :file_type
    ])
    |> validate_required([:round_number, :file_path])
    |> validate_inclusion(:encoding, ["base64"])
    |> validate_inclusion(:file_type, file_types())
    |> validate_length(:lang, max: @lang_max_length)
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
