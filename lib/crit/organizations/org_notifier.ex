defmodule Crit.Organizations.OrgNotifier do
  @moduledoc """
  Delivers transactional emails for the Organizations context (currently invites).
  """

  import Swoosh.Email

  alias Crit.Mailer
  alias Crit.Organizations.OrganizationInvite

  def deliver_invitation(invite, org, invited_by, url) do
    role_label = invite.role
    inviter_name = invited_by.name || invited_by.email || "Someone"
    ttl = OrganizationInvite.ttl_days()

    # HTML-escape user-provided values to prevent XSS in email clients
    h = fn s -> s |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string() end
    safe_org_name = h.(org.name)
    safe_inviter = h.(inviter_name)
    safe_url = h.(url)

    email =
      new()
      |> to(invite.email)
      |> from({"Crit", "noreply@crit.md"})
      |> subject("You've been invited to join #{org.name} on Crit")
      |> text_body("""
      #{inviter_name} has invited you to join #{org.name} on Crit as a #{role_label}.

      Click the link below to accept (expires in #{ttl} days):

      #{url}

      If you don't have an account, you'll be asked to sign in first.

      If you didn't expect this email, you can ignore it.
      """)
      |> html_body("""
      <!DOCTYPE html>
      <html>
      <body style="font-family: sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2>You've been invited to join #{safe_org_name} on Crit</h2>
        <p>#{safe_inviter} has invited you to join <strong>#{safe_org_name}</strong> on Crit as a <strong>#{role_label}</strong>.</p>
        <p>
          <a href="#{safe_url}" style="display: inline-block; padding: 10px 20px; background: #0f172a; color: white; text-decoration: none; border-radius: 6px;">
            Accept invitation
          </a>
        </p>
        <p style="color: #64748b; font-size: 14px;">This invitation expires in #{ttl} days. If you don't have an account, you'll be asked to sign in first.</p>
        <p style="color: #64748b; font-size: 14px;">If you didn't expect this email, you can ignore it.</p>
      </body>
      </html>
      """)

    Mailer.deliver(email)
  end
end
