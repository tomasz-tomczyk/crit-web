defmodule Crit.Repo.Migrations.AddAnchorAndDriftedToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :anchor, :text
      add :drifted, :boolean, null: false, default: false
    end
  end
end
