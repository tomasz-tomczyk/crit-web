defmodule Crit.Repo.Migrations.AddSharePolicyToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :allowed_comment_policies, {:array, :string},
        null: false,
        default: ["open", "logged_in_only", "disallowed"]

      add :allowed_review_visibilities, {:array, :string},
        null: false,
        default: ["unlisted", "public", "organization"]
    end

    create constraint(:settings, :allowed_comment_policies_must_be_valid,
             check:
               "allowed_comment_policies <@ ARRAY['open','logged_in_only','disallowed']::varchar[] AND cardinality(allowed_comment_policies) >= 1"
           )

    create constraint(:settings, :allowed_review_visibilities_must_be_valid,
             check:
               "allowed_review_visibilities <@ ARRAY['unlisted','public','organization']::varchar[] AND cardinality(allowed_review_visibilities) >= 1"
           )
  end
end
