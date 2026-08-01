defmodule Crit.User.Preferences do
  @moduledoc "Typed, user-controlled product preferences stored in users.preferences."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :keep_reviews, :boolean, default: false
    field :discussion_notifications_enabled, :boolean, default: true
  end

  def changeset(preferences, attrs) do
    cast(preferences, attrs, [:keep_reviews, :discussion_notifications_enabled])
  end
end
