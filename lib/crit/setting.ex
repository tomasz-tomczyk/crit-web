defmodule Crit.Setting do
  @moduledoc """
  Singleton schema for instance-wide settings. The DB enforces `id = 1` via
  CHECK constraint; readers and writers always target id 1.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  schema "settings" do
    field :max_document_bytes, :integer
    field :max_comments_per_review, :integer
    field :max_comment_body_bytes, :integer

    timestamps(type: :utc_datetime)
  end

  @fields [:max_document_bytes, :max_comments_per_review, :max_comment_body_bytes]

  @doc "Changeset for updating instance settings. Validates non-negative integers."
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:max_document_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:max_comments_per_review, greater_than_or_equal_to: 0)
    |> validate_number(:max_comment_body_bytes, greater_than_or_equal_to: 0)
  end
end
