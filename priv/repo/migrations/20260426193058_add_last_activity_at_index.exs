defmodule Crit.Repo.Migrations.AddLastActivityAtIndex do
  use Ecto.Migration

  def change do
    create index(:reviews, [:last_activity_at])
  end
end
