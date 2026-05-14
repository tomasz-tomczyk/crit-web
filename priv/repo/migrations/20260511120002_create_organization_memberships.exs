defmodule Crit.Repo.Migrations.CreateOrganizationMemberships do
  use Ecto.Migration

  def change do
    create table(:organization_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:organization_memberships, [:organization_id, :user_id])
    create index(:organization_memberships, [:user_id])
  end
end
