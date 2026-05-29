defmodule Crit.Review do
  use Crit.Schema

  schema "reviews" do
    field :token, :string
    field :delete_token, :string
    field :last_activity_at, :utc_datetime
    field :review_round, :integer, default: 0
    field :cli_args, {:array, :string}, default: []
    field :visibility, Ecto.Enum, values: [:unlisted, :public, :organization], default: :unlisted

    field :comment_policy, Ecto.Enum,
      values: [:open, :logged_in_only, :disallowed],
      default: :open

    field :review_type, Ecto.Enum, values: [:files, :preview], default: :files

    belongs_to :user, Crit.User, type: :binary_id
    belongs_to :organization, Crit.Organizations.Organization, type: :binary_id

    has_many :comments, Crit.Comment
    has_many :round_snapshots, Crit.ReviewRoundSnapshot

    field :files, {:array, :map}, virtual: true, default: []

    timestamps(type: :utc_datetime)
  end

  @max_cli_args 64
  @max_cli_arg_bytes 256

  @doc "Changeset for creating a new review."
  def create_changeset(review, attrs) do
    review
    |> cast(attrs, [:review_round, :cli_args, :review_type])
    |> validate_cli_args()
    |> put_token()
    |> put_delete_token()
    |> put_last_activity_at()
  end

  @doc """
  Changeset for updating an existing review's mutable fields.

  Validates `cli_args` to prevent unbounded writes from the share-update API path
  (`PUT /api/reviews/:token`), mirroring the protection on `create_changeset/2`.
  `review_round` is included because the upsert flow bumps it on content change.
  """
  def update_changeset(review, attrs) do
    review
    |> cast(attrs, [:review_round, :cli_args, :comment_policy])
    |> validate_cli_args()
    |> validate_inclusion(:comment_policy, [:open, :logged_in_only, :disallowed])
  end

  @doc "Changeset for owner-driven visibility updates."
  def visibility_changeset(review, attrs) do
    review
    |> cast(attrs, [:visibility])
    |> validate_required([:visibility])
    |> validate_inclusion(:visibility, [:unlisted, :public])
  end

  @doc "Changeset for setting organization-scoped fields on a review."
  def organization_changeset(review, attrs) do
    review
    |> cast(attrs, [:organization_id, :visibility])
    |> validate_org_visibility()
  end

  defp validate_org_visibility(changeset) do
    visibility = get_field(changeset, :visibility)
    org_id = get_field(changeset, :organization_id)

    if visibility == :organization and is_nil(org_id) do
      add_error(changeset, :organization_id, "is required when visibility is :organization")
    else
      changeset
    end
  end

  defp validate_cli_args(changeset) do
    validate_change(changeset, :cli_args, fn :cli_args, args ->
      cond do
        not is_list(args) ->
          [cli_args: "must be a list of strings"]

        length(args) > @max_cli_args ->
          [cli_args: "may not contain more than #{@max_cli_args} entries"]

        Enum.any?(args, fn a -> not is_binary(a) end) ->
          [cli_args: "must contain only strings"]

        Enum.any?(args, fn a -> byte_size(a) > @max_cli_arg_bytes end) ->
          [cli_args: "each entry may not exceed #{@max_cli_arg_bytes} bytes"]

        true ->
          []
      end
    end)
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
