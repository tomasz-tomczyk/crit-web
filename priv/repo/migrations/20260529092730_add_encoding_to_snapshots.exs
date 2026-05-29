defmodule Crit.Repo.Migrations.AddEncodingToSnapshots do
  use Ecto.Migration

  def change do
    alter table(:review_round_snapshots) do
      add :encoding, :string
    end
  end
end
