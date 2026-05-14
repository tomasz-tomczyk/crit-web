defmodule Crit.Repo.Migrations.AddOrganizationIdToReviews do
  use Ecto.Migration

  def change do
    alter table(:reviews) do
      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:reviews, [:organization_id])
  end
end
