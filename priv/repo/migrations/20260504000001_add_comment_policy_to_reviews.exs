defmodule Crit.Repo.Migrations.AddCommentPolicyToReviews do
  use Ecto.Migration

  def change do
    alter table(:reviews) do
      add :comment_policy, :string, null: false, default: "open"
    end
  end
end
