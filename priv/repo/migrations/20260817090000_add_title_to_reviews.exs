defmodule Crit.Repo.Migrations.AddTitleToReviews do
  use Ecto.Migration

  def up do
    alter table(:reviews) do
      add :title, :text
    end
  end

  def down do
    alter table(:reviews) do
      remove :title
    end
  end
end
