defmodule Crit.Organizations.Organization do
  use Crit.Schema

  alias Crit.Organizations.{OrganizationMembership, OrganizationInvite}

  schema "organizations" do
    field :name, :string
    field :slug, :string

    has_many :memberships, OrganizationMembership
    has_many :invites, OrganizationInvite
    has_many :users, through: [:memberships, :user]

    field :member_count, :integer, virtual: true, default: 0
    field :review_count, :integer, virtual: true, default: 0
    field :role, Ecto.Enum, values: [:admin, :member], virtual: true
    field :member_initials, {:array, :string}, virtual: true, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_name_chars()
    |> update_change(:slug, fn s -> if is_binary(s), do: String.downcase(s), else: s end)
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  def create_changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_name_chars()
    |> maybe_put_slug_from_name()
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  defp validate_name_chars(changeset) do
    validate_format(changeset, :name, ~r/\A[^\x00-\x1F\x7F]+\z/,
      message: "must not contain control characters"
    )
  end

  defp maybe_put_slug_from_name(changeset) do
    case {get_change(changeset, :slug), get_change(changeset, :name)} do
      {slug, _} when is_binary(slug) and slug != "" -> changeset
      {_, nil} -> changeset
      {_, name} -> put_change(changeset, :slug, generate_slug(name))
    end
  end

  def generate_slug(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s_-]/, "")
      |> String.replace(~r/[\s]+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")
      |> String.slice(0, 60)

    if String.length(base) < 2, do: "org-#{base}", else: base
  end

  @slug_format ~r/^[a-z0-9][a-z0-9_-]*[a-z0-9]$|^[a-z0-9]$/
  @slug_min_length 2
  @slug_max_length 60

  @doc "True if `slug` has the shape `changeset/2` accepts for a slug."
  def valid_slug?(slug) when is_binary(slug) do
    String.length(slug) in @slug_min_length..@slug_max_length and
      Regex.match?(@slug_format, slug)
  end

  def valid_slug?(_slug), do: false

  defp validate_slug(changeset) do
    changeset
    |> validate_format(:slug, @slug_format,
      message: "must be lowercase letters, numbers, hyphens, and underscores only"
    )
    |> validate_length(:slug, min: @slug_min_length, max: @slug_max_length)
  end
end
