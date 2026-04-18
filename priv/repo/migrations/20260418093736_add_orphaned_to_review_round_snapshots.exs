defmodule Crit.Repo.Migrations.AddOrphanedToReviewRoundSnapshots do
  use Ecto.Migration

  def change do
    alter table(:review_round_snapshots) do
      add :status, :string, size: 50, default: "modified"
      add :orphaned, :boolean, default: false, null: false
    end
  end
end
