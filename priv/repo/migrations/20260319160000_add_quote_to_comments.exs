defmodule Crit.Repo.Migrations.AddQuoteToComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :quote, :text
    end
  end
end
