defmodule Crit.Notifications.ExtraAddresses do
  @moduledoc """
  Extra inboxes for discussion digests.

  An address is stored as pending and receives nothing until the inbox owner
  opens the confirmation link. The link is the consent: digests contain review
  URLs and comment text, so an unverified address would leak that content.
  """

  alias Crit.{Accounts, Mailer, Repo}
  alias Crit.User

  @salt "notification-email-confirm"
  @unsubscribe_salt "notification-email-unsubscribe"
  @max_age_seconds 7 * 24 * 60 * 60

  @doc """
  Adds `email` to the user's pending list and sends a confirmation link.

  Does not add the address to the digest recipients. Rolls the pending row
  back if the confirmation email cannot be sent.
  """
  def request(%User{} = user, email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()
    confirmed = addresses(user.preferences.notification_emails)
    pending = addresses(user.preferences.pending_notification_emails)
    account = account_email(user)

    cond do
      email == "" ->
        {:error, :blank}

      email == account or email in confirmed ->
        {:error, :included}

      email in pending ->
        {:error, :pending}

      true ->
        Repo.transact(fn ->
          case Accounts.update_preferences(user, %{
                 pending_notification_emails: pending ++ [email]
               }) do
            {:ok, updated} ->
              case Mailer.deliver(confirmation_message(updated, email)) do
                {:ok, _} -> {:ok, updated}
                {:error, _} -> {:error, :delivery_failed}
              end

            {:error, changeset} ->
              {:error, changeset}
          end
        end)
    end
  end

  @doc "Returns `{:ok, :pending | :confirmed, email}` when the token still matches stored state."
  def preview(token) when is_binary(token) do
    with {:ok, user, email} <- decode(token) do
      cond do
        email in addresses(user.preferences.notification_emails) -> {:ok, :confirmed, email}
        email in addresses(user.preferences.pending_notification_emails) -> {:ok, :pending, email}
        true -> :error
      end
    end
  end

  @doc "Moves a still-pending address onto the confirmed list. Idempotent if already confirmed."
  def confirm(token) when is_binary(token) do
    with {:ok, user, email} <- decode(token) do
      confirmed = addresses(user.preferences.notification_emails)
      pending = addresses(user.preferences.pending_notification_emails)

      cond do
        email in confirmed ->
          {:ok, email}

        email in pending ->
          case Accounts.update_preferences(user, %{
                 notification_emails: confirmed ++ [email],
                 pending_notification_emails: List.delete(pending, email)
               }) do
            {:ok, _} -> {:ok, email}
            {:error, _} -> :error
          end

        true ->
          :error
      end
    end
  end

  @doc "Link that removes this extra address. It does not expire and does not require a Crit login."
  def unsubscribe_url(%User{} = user, email) when is_binary(email) do
    token = Phoenix.Token.sign(CritWeb.Endpoint, @unsubscribe_salt, {user.id, email})
    CritWeb.Endpoint.url() <> "/settings/notification-emails/unsubscribe/" <> token
  end

  @doc "Returns `{:ok, :active | :gone, email}` when the token belongs to this user."
  def unsubscribe_preview(token) when is_binary(token) do
    with {:ok, user, email} <- decode(token, @unsubscribe_salt, :infinity) do
      if subscribed?(user, email), do: {:ok, :active, email}, else: {:ok, :gone, email}
    end
  end

  @doc "Removes the address from confirmed and pending lists. Idempotent if it is already gone."
  def unsubscribe(token) when is_binary(token) do
    with {:ok, user, email} <- decode(token, @unsubscribe_salt, :infinity) do
      confirmed = addresses(user.preferences.notification_emails)
      pending = addresses(user.preferences.pending_notification_emails)

      if email in confirmed or email in pending do
        case Accounts.update_preferences(user, %{
               notification_emails: List.delete(confirmed, email),
               pending_notification_emails: List.delete(pending, email)
             }) do
          {:ok, _} -> {:ok, email}
          {:error, _} -> :error
        end
      else
        {:ok, email}
      end
    end
  end

  defp confirmation_message(user, email) do
    token = Phoenix.Token.sign(CritWeb.Endpoint, @salt, {user.id, email})
    url = CritWeb.Endpoint.url() <> "/settings/notification-emails/confirm/" <> token
    days = div(@max_age_seconds, 86_400)
    who = user.name || "A Crit user"
    account = account_email(user) || "their Crit account"

    Swoosh.Email.new()
    |> Swoosh.Email.to(email)
    |> Swoosh.Email.from({"Crit", Application.fetch_env!(:crit, :smtp_from)})
    |> Swoosh.Email.subject("Confirm this address for Crit notifications")
    |> Swoosh.Email.text_body("""
    #{who} (#{account}) asked Crit to send discussion notifications to this address.

    Confirm (this link expires in #{days} days):
    #{url}

    Crit will not send review comments here until you confirm.
    If you didn't expect this, ignore this email.
    """)
  end

  defp decode(token, salt \\ @salt, max_age \\ @max_age_seconds) do
    with {:ok, {user_id, email}} when is_binary(user_id) and is_binary(email) <-
           Phoenix.Token.verify(CritWeb.Endpoint, salt, token, max_age: max_age),
         {:ok, user} <- Accounts.get_user(user_id) do
      {:ok, user, email}
    else
      _ -> :error
    end
  end

  defp subscribed?(user, email) do
    email in addresses(user.preferences.notification_emails) or
      email in addresses(user.preferences.pending_notification_emails)
  end

  defp addresses(emails) when is_list(emails), do: emails
  defp addresses(_), do: []

  defp account_email(%User{email: email}) when is_binary(email), do: String.downcase(email)
  defp account_email(_), do: nil
end
