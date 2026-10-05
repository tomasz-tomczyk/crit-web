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
    # Opt in to digests for the user's own comments and replies too.
    field :notify_own_activity, :boolean, default: false
    # Confirmed extra addresses. Pending ones are not mailed until the inbox owner confirms.
    field :notification_emails, {:array, :string}, default: []
    field :pending_notification_emails, {:array, :string}, default: []
  end

  def max_notification_emails, do: @max_notification_emails

  def changeset(preferences, attrs) do
    preferences
    |> cast(attrs, [
      :keep_reviews,
      :discussion_notifications_enabled,
      :notify_own_activity,
      :notification_emails,
      :pending_notification_emails
    ])
    |> normalize_email_list(:notification_emails)
    |> normalize_email_list(:pending_notification_emails)
    |> validate_notification_emails()
  end

  defp normalize_email_list(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      emails ->
        put_change(
          changeset,
          field,
          emails |> Enum.map(&normalize_address/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
        )
    end
  end

  defp normalize_address(address) when is_binary(address) do
    address |> String.trim() |> String.downcase()
  end

  defp normalize_address(_), do: ""

  defp validate_notification_emails(changeset) do
    changeset
    |> validate_email_list(:notification_emails)
    |> validate_email_list(:pending_notification_emails)
    |> validate_notification_email_total()
  end

  defp validate_email_list(changeset, field) do
    changeset
    |> validate_length(field,
      max: @max_notification_emails,
      message: "you can add up to #{@max_notification_emails} addresses"
    )
    |> validate_change(field, fn ^field, emails ->
      if Enum.all?(emails, &(&1 =~ @email_re and String.length(&1) <= 160)) do
        []
      else
        [{field, "must be valid email addresses"}]
      end
    end)
  end

  defp validate_notification_email_total(changeset) do
    confirmed = get_field(changeset, :notification_emails) || []
    pending = get_field(changeset, :pending_notification_emails) || []

    cond do
      length(confirmed) + length(pending) > @max_notification_emails ->
        add_error(
          changeset,
          :notification_emails,
          "you can add up to #{@max_notification_emails} addresses"
        )

      Enum.any?(confirmed, &(&1 in pending)) ->
        add_error(changeset, :notification_emails, "is already waiting for confirmation")

      true ->
        changeset
    end
  end
end
