defmodule Crit.Repo.Migrations.CreateMarketingConsentEvents do
  use Ecto.Migration

  def change do
    create table(:marketing_consent_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :action, :string, null: false
      add :method, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:marketing_consent_events, [:user_id, :inserted_at])
  end
end
