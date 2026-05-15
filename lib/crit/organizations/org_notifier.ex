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
    inviter_first = inviter_name |> String.split(" ") |> List.first()
    ttl = OrganizationInvite.ttl_days()

    h = fn s -> s |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string() end
    safe_org_name = h.(org.name)
    safe_inviter = h.(inviter_name)
    safe_inviter_first = h.(inviter_first)
    safe_url = h.(url)

    expires_on =
      DateTime.utc_now()
      |> DateTime.add(ttl * 24 * 60 * 60, :second)
      |> Calendar.strftime("%B %-d, %Y")

    avatar_html = inviter_avatar_html(invited_by, safe_inviter_first)
    member_since = inviter_since(invited_by)

    email =
      new()
      |> to(invite.email)
      |> from({inviter_name <> " via Crit", Application.fetch_env!(:crit, :smtp_from)})
      |> subject("#{inviter_name} invited you to #{org.name} on Crit")
      |> text_body("""
      #{inviter_first} invited you to #{org.name}!

      With Crit, your team reviews plans, docs, and agent output together — so nothing ships without feedback. Just accept by #{expires_on} to join as a #{role_label}.

      #{url}

      If you don't have an account, you'll be asked to sign in first.

      — #{inviter_name}, on Crit since #{inviter_since(invited_by)}
      """)
      |> html_body("""
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
      </head>
      <body style="margin: 0; padding: 0; background-color: #f9fafb; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
        <div style="display: none; max-height: 0; overflow: hidden;">#{safe_inviter_first} invited you to join #{safe_org_name} on Crit — accept by #{expires_on}</div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color: #f9fafb;">
          <tr>
            <td align="center" style="padding: 40px 20px;">
              <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width: 560px; width: 100%;">
                <!-- Logo -->
                <tr>
                  <td style="padding-bottom: 32px;">
                    <span style="font-size: 20px; font-weight: 700; color: #0f172a; letter-spacing: -0.02em;">crit</span>
                  </td>
                </tr>
                <!-- Headline -->
                <tr>
                  <td style="padding-bottom: 16px;">
                    <h1 style="margin: 0; font-size: 28px; font-weight: 700; color: #0f172a; line-height: 1.2;">
                      #{safe_inviter_first} invited you to join #{safe_org_name}!
                    </h1>
                  </td>
                </tr>
                <!-- Body -->
                <tr>
                  <td style="padding-bottom: 28px;">
                    <p style="margin: 0; font-size: 16px; line-height: 1.6; color: #374151;">
                      With Crit, your team reviews plans, docs, and agent output together — so nothing ships without feedback. Just accept by <strong>#{expires_on}</strong> to join as a #{role_label}.
                    </p>
                  </td>
                </tr>
                <!-- CTA -->
                <tr>
                  <td style="padding-bottom: 36px;">
                    <a href="#{safe_url}" style="display: inline-block; padding: 14px 28px; background-color: #0f172a; color: #ffffff; font-size: 16px; font-weight: 600; text-decoration: none; border-radius: 8px;">
                      Accept invitation
                    </a>
                  </td>
                </tr>
                <!-- Divider -->
                <tr>
                  <td style="padding-bottom: 24px;">
                    <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 0;">
                  </td>
                </tr>
                <!-- Inviter profile -->
                <tr>
                  <td style="padding-bottom: 32px;">
                    <table role="presentation" cellpadding="0" cellspacing="0">
                      <tr>
                        #{avatar_html}
                        <td style="vertical-align: middle;">
                          <p style="margin: 0; font-size: 15px; font-weight: 600; color: #0f172a;">#{safe_inviter}</p>
                          <p style="margin: 2px 0 0; font-size: 13px; color: #6b7280;">On Crit since #{member_since}</p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <!-- Footer -->
                <tr>
                  <td>
                    <p style="margin: 0; font-size: 13px; color: #9ca3af; line-height: 1.5;">
                      If you didn't expect this email, you can safely ignore it.
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
      </html>
      """)

    Mailer.deliver(email)
  end

  defp inviter_since(invited_by) do
    case invited_by.inserted_at do
      %DateTime{} = dt -> Calendar.strftime(dt, "%B %Y")
      _ -> "recently"
    end
  end

  defp inviter_avatar_html(invited_by, safe_first_name) do
    if invited_by.avatar_url do
      h = fn s -> s |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string() end
      safe_avatar = h.(invited_by.avatar_url)

      """
      <td style="padding-right: 12px; vertical-align: middle;">
        <img src="#{safe_avatar}" width="40" height="40" style="border-radius: 50%; display: block;" alt="#{safe_first_name}">
      </td>
      """
    else
      initial = safe_first_name |> String.first() |> String.upcase()

      """
      <td style="padding-right: 12px; vertical-align: middle;">
        <div style="width: 40px; height: 40px; border-radius: 50%; background-color: #0f172a; color: #ffffff; font-size: 16px; font-weight: 600; line-height: 40px; text-align: center;">#{initial}</div>
      </td>
      """
    end
  end
end
