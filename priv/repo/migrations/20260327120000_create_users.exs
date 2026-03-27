defmodule Crit.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :provider, :string, null: false
      add :provider_uid, :string, null: false
      add :email, :string
      add :name, :string
      add :avatar_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:provider, :provider_uid])
  end
end
