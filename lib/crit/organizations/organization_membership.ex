defmodule Crit.Organizations.OrganizationMembership do
  use Crit.Schema

  alias Crit.Organizations.Organization
  alias Crit.User

  schema "organization_memberships" do
    belongs_to :organization, Organization
    belongs_to :user, User
    field :role, Ecto.Enum, values: [:admin, :member], default: :member

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:organization_id, :user_id, :role])
    |> validate_required([:organization_id, :user_id, :role])
    |> unique_constraint([:organization_id, :user_id])
  end
end
