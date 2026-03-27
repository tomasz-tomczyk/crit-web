defmodule Crit.Repo.Migrations.CreateUserApiTokens do
  use Ecto.Migration

  def change do
    create table(:user_api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :string, null: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_api_tokens, [:token_hash])
  end
end
