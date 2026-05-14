defmodule Crit.Repo.Migrations.CreateOrganizationInvites do
  use Ecto.Migration

  def change do
    create table(:organization_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :email, :string, null: false
      add :token, :binary, null: false

      add :invited_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all),
          null: false

      add :role, :string, null: false, default: "member"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:organization_invites, [:organization_id, "lower(email)"],
             name: :organization_invites_org_email_unique
           )

    create index(:organization_invites, [:token])
  end
end
