defmodule Crit.Repo.Migrations.AddDomAnchorToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :dom_anchor, :map
    end
  end
end
