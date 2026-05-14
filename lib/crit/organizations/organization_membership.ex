defmodule Crit.Organizations.OrganizationMembership do
  use Crit.Schema

  alias Crit.Organizations.Organization
  alias Crit.User

  schema "organization_memberships" do
    belongs_to :organization, Organization
    belongs_to :user, User
    field :role, :string, default: "member"

    timestamps(type: :utc_datetime)
  end

  @valid_roles ~w(admin member)

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:organization_id, :user_id, :role])
    |> validate_required([:organization_id, :user_id, :role])
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint([:organization_id, :user_id])
  end
end
