defmodule Crit.User.Preferences do
  @moduledoc "Typed, user-controlled product preferences stored in users.preferences."

  use Ecto.Schema
  import Ecto.Changeset

  @max_notification_emails 3
  @email_re ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @primary_key false
  embedded_schema do
    field :keep_reviews, :boolean, default: false
    field :discussion_notifications_enabled, :boolean, default: true
    field :notification_emails, {:array, :string}, default: []
  end

  def max_notification_emails, do: @max_notification_emails

  def changeset(preferences, attrs) do
    preferences
    |> cast(attrs, [:keep_reviews, :discussion_notifications_enabled, :notification_emails])
    |> normalize_notification_emails()
    |> validate_notification_emails()
  end

  defp normalize_notification_emails(changeset) do
    case get_change(changeset, :notification_emails) do
      nil ->
        changeset

      emails ->
        put_change(
          changeset,
          :notification_emails,
          emails |> Enum.map(&(&1 |> String.trim() |> String.downcase())) |> Enum.uniq()
        )
    end
  end

  defp validate_notification_emails(changeset) do
    changeset
    |> validate_length(:notification_emails,
      max: @max_notification_emails,
      message: "you can add up to #{@max_notification_emails} addresses"
    )
    |> validate_change(:notification_emails, fn :notification_emails, emails ->
      if Enum.all?(emails, &(&1 =~ @email_re and String.length(&1) <= 160)) do
        []
      else
        [notification_emails: "must be valid email addresses"]
      end
    end)
  end
end
