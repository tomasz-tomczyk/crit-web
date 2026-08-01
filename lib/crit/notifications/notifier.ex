defmodule Crit.Notifications.Notifier do
  @moduledoc "Builds bounded, escaped discussion digest emails."

  import Swoosh.Email

  alias Crit.Notifications.NotificationBatch

  @max_items 20
  @excerpt_length 240
  @filename_max 28
  @avatar_size 32

  def email(%NotificationBatch{items: items} = batch) when is_list(items) do
    shown = Enum.take(items, @max_items)
    more = max(length(items) - length(shown), 0)
    review_url = CritWeb.Endpoint.url() <> "/r/" <> batch.review.token
    settings_url = CritWeb.Endpoint.url() <> "/settings"
    filename = Crit.Reviews.display_filename(batch.review)
    actors = actors(shown)
    subject_line = subject_line(actors, filename)
    headline_text = headline_text(actors, filename)
    preheader_text = preheader_text(actors, shown, filename)

    new()
    |> to(batch.recipient.email)
    |> from(from_address(actors))
    |> subject(subject_line)
    |> text_body(text_body(headline_text, shown, more, review_url, settings_url))
    |> html_body(html_body(headline_text, preheader_text, shown, more, review_url, settings_url))
  end

  defp from_address(actors) do
    smtp = Application.fetch_env!(:crit, :smtp_from)

    case Enum.find(actors, & &1.known?) do
      %{name: name} -> {"#{name} via Crit", smtp}
      nil -> smtp
    end
  end

  defp subject_line(actors, filename) do
    file = short_filename(filename)

    case actors do
      [a] -> "#{a.first_name} commented on #{file}"
      [a, b] -> "#{a.first_name} and #{b.first_name} on #{file}"
      [a | rest] -> "#{a.first_name} and #{length(rest)} others on #{file}"
      [] -> "New comments on #{file}"
    end
  end

  defp headline_text(actors, filename) do
    file = short_filename(filename)

    case actors do
      [a] -> "#{a.first_name} left a comment on #{file}"
      [a, b] -> "#{a.first_name} and #{b.first_name} commented on #{file}"
      [a | rest] -> "#{a.first_name} and #{length(rest)} others commented on #{file}"
      [] -> "New comments on #{file}"
    end
  end

  defp preheader_text(actors, items, filename) do
    file = short_filename(filename)

    case {actors, items} do
      {[a | _], [item | _]} ->
        "#{a.first_name}: #{excerpt(item.comment.body)}"

      {_, _} ->
        "New comments on #{file}"
    end
    |> String.slice(0, 100)
  end

  defp text_body(headline, items, more, review_url, settings_url) do
    entries =
      items
      |> group_by_thread()
      |> Enum.map_join("\n\n", fn {_thread_id, comments} ->
        Enum.map_join(comments, "\n\n", fn comment ->
          "#{actor_name(comment)}\n#{excerpt(comment.body)}"
        end)
      end)

    more_line = if more > 0, do: "\n\n…and #{more} more", else: ""

    """
    #{headline}

    #{entries}#{more_line}

    Open review: #{review_url}

    Notification settings: #{settings_url}
    """
  end

  defp html_body(headline, preheader, items, more, review_url, settings_url) do
    entries =
      items
      |> group_by_thread()
      |> Enum.map_join(fn {_thread_id, comments} ->
        Enum.map_join(comments, &comment_row_html/1)
      end)

    cta_label = if more > 0, do: "Open review — and #{more} more", else: "Open review"

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
      <meta name="color-scheme" content="light dark">
      <meta name="supported-color-schemes" content="light dark">
      <style>
        :root { color-scheme: light dark; }
        @media (prefers-color-scheme: dark) {
          body, .email-bg { background-color: #1a1b26 !important; }
          .email-headline, .email-author { color: #c0caf5 !important; }
          .email-body, .email-excerpt { color: #9aa5ce !important; }
          .email-cta { background-color: #7aa2f7 !important; color: #1a1b26 !important; }
          .email-footer { color: #565f89 !important; }
          .email-avatar-fallback { background-color: #292e42 !important; color: #7aa2f7 !important; }
        }
      </style>
    </head>
    <body style="margin:0;padding:0;background-color:#f9fafb;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;" class="email-bg">
      <div style="display:none;max-height:0;overflow:hidden;">#{escape(preheader)}</div>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f9fafb;" class="email-bg">
        <tr>
          <td align="center" style="padding:40px 20px;">
            <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">
              <tr>
                <td style="padding-bottom:32px;">
                  <span style="font-size:20px;font-weight:700;color:#0f172a;letter-spacing:-0.02em;">crit</span>
                </td>
              </tr>
              <tr>
                <td style="padding-bottom:20px;">
                  <h1 class="email-headline" style="margin:0;font-size:24px;font-weight:700;color:#0f172a;line-height:1.25;">
                    #{escape(headline)}
                  </h1>
                </td>
              </tr>
              <tr>
                <td class="email-body" style="padding-bottom:28px;">
                  <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                    #{entries}
                  </table>
                </td>
              </tr>
              <tr>
                <td style="padding-bottom:36px;">
                  <a href="#{escape(review_url)}" class="email-cta" style="display:inline-block;padding:14px 28px;background-color:#0f172a;color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;border-radius:8px;">
                    #{escape(cta_label)}
                  </a>
                </td>
              </tr>
              <tr>
                <td>
                  <p class="email-footer" style="margin:0;font-size:13px;color:#9ca3af;line-height:1.5;">
                    <a href="#{escape(settings_url)}" style="color:#9ca3af;">Notification settings</a>
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp comment_row_html(comment) do
    name = actor_name(comment)
    first = first_name(name)

    """
    <tr>
      #{avatar_cell_html(comment, first)}
      <td style="vertical-align:top;padding-bottom:16px;">
        <p class="email-author" style="margin:0 0 2px;font-size:15px;font-weight:600;color:#0f172a;line-height:1.3;">#{escape(name)}</p>
        <p class="email-excerpt" style="margin:0;font-size:15px;line-height:1.5;color:#374151;">#{escape(excerpt(comment.body))}</p>
      </td>
    </tr>
    """
  end

  defp avatar_cell_html(comment, first) do
    size = @avatar_size

    case loaded_user(comment) do
      %{avatar_url: url} when is_binary(url) and url != "" ->
        """
        <td style="width:#{size + 12}px;padding-right:12px;vertical-align:top;padding-bottom:16px;">
          <img src="#{escape(url)}" width="#{size}" height="#{size}" style="border-radius:50%;display:block;" alt="#{escape(first)}">
        </td>
        """

      _ ->
        initial =
          first
          |> String.first()
          |> case do
            nil -> "?"
            char -> String.upcase(char)
          end
          |> escape()

        """
        <td style="width:#{size + 12}px;padding-right:12px;vertical-align:top;padding-bottom:16px;">
          <div class="email-avatar-fallback" style="width:#{size}px;height:#{size}px;border-radius:50%;background-color:#0f172a;color:#ffffff;font-size:13px;font-weight:600;line-height:#{size}px;text-align:center;">#{initial}</div>
        </td>
        """
    end
  end

  defp actors(items) do
    items
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.map(& &1.comment)
    |> Enum.reduce([], fn comment, acc ->
      actor = actor_from(comment)

      if Enum.any?(acc, &(&1.key == actor.key)) do
        acc
      else
        acc ++ [actor]
      end
    end)
  end

  defp actor_from(comment) do
    name = actor_name(comment)
    user = loaded_user(comment)

    %{
      key: actor_key(comment),
      name: name,
      first_name: first_name(name),
      known?: match?(%{id: _}, user)
    }
  end

  defp actor_key(%{user_id: id}) when not is_nil(id), do: {:user, id}

  defp actor_key(%{author_display_name: name, author_identity: identity}) do
    cond do
      is_binary(identity) and identity != "" -> {:identity, identity}
      is_binary(name) and name != "" -> {:name, name}
      true -> {:anon, :unknown}
    end
  end

  defp loaded_user(%{user: %Crit.User{} = user}), do: user
  defp loaded_user(_comment), do: nil

  defp first_name(name) when is_binary(name) do
    name |> String.split(" ", parts: 2) |> List.first()
  end

  defp first_name(_), do: "Someone"

  defp short_filename(filename) when is_binary(filename) do
    base = Path.basename(filename)

    if String.length(base) > @filename_max do
      String.slice(base, 0, @filename_max - 1) <> "…"
    else
      base
    end
  end

  defp short_filename(_), do: "review"

  defp group_by_thread(items) do
    items
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.group_by(fn item -> item.comment.parent_id || item.comment.id end, & &1.comment)
    |> Enum.sort_by(fn {_id, comments} -> List.first(comments).inserted_at end, DateTime)
  end

  defp actor_name(%{author_display_name: name}) when is_binary(name) and name != "", do: name
  defp actor_name(_comment), do: "Anonymous"

  defp excerpt(body) do
    normalized =
      body
      |> to_string()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    shortened = String.slice(normalized, 0, @excerpt_length)

    if String.length(normalized) > @excerpt_length, do: shortened <> "…", else: shortened
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
