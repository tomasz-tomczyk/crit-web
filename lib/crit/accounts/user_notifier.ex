defmodule Crit.Accounts.UserNotifier do
  import Swoosh.Email

  alias Crit.Mailer

  defp from, do: Application.get_env(:crit, :smtp_from, "no-reply@localhost")

  defp deliver(to, subject, body) do
    email =
      new()
      |> to(to)
      |> from({"crit", from()})
      |> subject(subject)
      |> text_body(body)

    case Mailer.deliver(email) do
      {:ok, _meta} -> {:ok, email}
      {:error, reason} -> {:error, reason}
    end
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your password", """
    Hi #{user.email},

    Click the link below to reset your password:

    #{url}

    If you didn't request this, ignore this email.
    """)
  end

  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirm your new email", """
    Hi,

    Click the link below to confirm your new email address:

    #{url}

    If you didn't request this, ignore this email.
    """)
  end
end
