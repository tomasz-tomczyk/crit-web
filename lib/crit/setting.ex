defmodule Crit.Setting do
  @moduledoc """
  Singleton schema for instance-wide settings. The DB enforces `id = 1` via
  CHECK constraint; readers and writers always target id 1.

  The DB stores byte limits as raw integers, but the form takes human-friendly
  MB / KB inputs via virtual fields. The changeset converts virtual MB / KB
  into the persisted byte columns.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kb 1024
  @mb 1_048_576

  @primary_key {:id, :integer, autogenerate: false}
  schema "settings" do
    field :max_document_bytes, :integer
    field :max_comments_per_review, :integer
    field :max_comment_body_bytes, :integer

    # Virtual fields that the form binds to. Converted to bytes by `changeset/2`.
    field :max_document_mb, :float, virtual: true
    field :max_comment_body_kb, :float, virtual: true

    timestamps(type: :utc_datetime)
  end

  @form_fields [:max_document_mb, :max_comments_per_review, :max_comment_body_kb]

  @doc """
  Changeset for updating instance settings via the admin form.

  Accepts `max_document_mb` (in megabytes) and `max_comment_body_kb` (in
  kilobytes); converts them into the persisted `max_document_bytes` and
  `max_comment_body_bytes` columns.
  """
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @form_fields)
    |> validate_required(@form_fields)
    |> validate_number(:max_document_mb, greater_than: 0)
    |> validate_number(:max_comments_per_review, greater_than: 0)
    |> validate_number(:max_comment_body_kb, greater_than: 0)
    |> put_byte_field(:max_document_mb, :max_document_bytes, @mb)
    |> put_byte_field(:max_comment_body_kb, :max_comment_body_bytes, @kb)
  end

  @doc "Helper for prefilling the form: bytes → MB."
  def bytes_to_mb(nil), do: nil
  def bytes_to_mb(bytes) when is_integer(bytes), do: Float.round(bytes / @mb, 2)

  @doc "Helper for prefilling the form: bytes → KB."
  def bytes_to_kb(nil), do: nil
  def bytes_to_kb(bytes) when is_integer(bytes), do: Float.round(bytes / @kb, 2)

  defp put_byte_field(changeset, virtual, real, multiplier) do
    case get_change(changeset, virtual) do
      nil -> changeset
      value -> put_change(changeset, real, round(value * multiplier))
    end
  end
end
