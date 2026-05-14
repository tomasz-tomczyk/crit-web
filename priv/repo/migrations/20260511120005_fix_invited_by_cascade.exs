defmodule Crit.Repo.Migrations.FixInvitedByCascade do
  use Ecto.Migration

  def change do
    drop constraint(:organization_invites, "organization_invites_invited_by_id_fkey")

    alter table(:organization_invites) do
      modify :invited_by_id,
             references(:users, type: :binary_id, on_delete: :delete_all),
             null: false
    end
  end
end
