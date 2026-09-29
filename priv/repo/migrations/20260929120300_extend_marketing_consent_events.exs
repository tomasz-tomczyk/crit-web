defmodule Crit.Repo.Migrations.ExtendMarketingConsentEvents do
  use Ecto.Migration

  def change do
    alter table(:marketing_consent_events) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
      add :email, :string
      add :source, :string
      add :source_path, :string, size: 512
      add :confirmation_nonce, :uuid
    end

    create index(:marketing_consent_events, [:email, :inserted_at])

    create constraint(:marketing_consent_events, :marketing_consent_identity,
             check: "user_id IS NOT NULL OR email IS NOT NULL"
           )
  end
end
