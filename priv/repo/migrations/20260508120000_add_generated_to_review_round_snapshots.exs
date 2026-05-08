defmodule Crit.Repo.Migrations.AddGeneratedToReviewRoundSnapshots do
  use Ecto.Migration

  def change do
    alter table(:review_round_snapshots) do
      add :generated, :boolean, default: false, null: false
    end
  end
end
