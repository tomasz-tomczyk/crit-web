defmodule Crit.Repo.Migrations.AddResolvedRoundToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :resolved_round, :integer
    end
  end
end
