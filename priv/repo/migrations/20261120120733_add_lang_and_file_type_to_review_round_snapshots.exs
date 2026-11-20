defmodule Crit.Repo.Migrations.AddLangAndFileTypeToReviewRoundSnapshots do
  use Ecto.Migration

  # Set by crit's `languages` config: `lang` is the highlight grammar, and
  # `file_type` ("markdown" | "code") overrides extension-based view choice.
  # Older CLIs omit both, so the columns stay nullable.
  def change do
    alter table(:review_round_snapshots) do
      add :lang, :string
      add :file_type, :string
    end
  end
end
