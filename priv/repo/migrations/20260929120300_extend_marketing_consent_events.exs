defmodule Crit.Repo.Migrations.ExtendMarketingConsentEvents do
  use Ecto.Migration

  def up do
    alter table(:marketing_consent_events) do
      modify :user_id, :binary_id, null: true, from: {:binary_id, null: false}
      add :email, :string
      add :source, :string
      add :source_path, :string, size: 512
      add :confirmation_nonce, :uuid
    end

    execute("""
    UPDATE marketing_consent_events AS event
    SET email = lower(account.email)
    FROM users AS account
    WHERE event.user_id = account.id AND account.email IS NOT NULL
    """)

    create index(:marketing_consent_events, [:email, :inserted_at])

    create constraint(:marketing_consent_events, :marketing_consent_identity,
             check: "user_id IS NOT NULL OR email IS NOT NULL"
           )
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "Keep this additive schema when rolling back the app; reverting it would discard email-only consent history."
  end
end
