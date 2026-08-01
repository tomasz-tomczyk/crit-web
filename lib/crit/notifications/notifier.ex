defmodule Crit.Notifications.Notifier do
  @moduledoc "Builds bounded, escaped discussion digest emails."

  import Swoosh.Email

  alias Crit.Notifications.NotificationBatch

  @max_items 20
  @excerpt_length 240

  def email(%NotificationBatch{} = batch, items) do
    shown = Enum.take(items, @max_items)
    more = max(length(items) - length(shown), 0)
    review_url = CritWeb.Endpoint.url() <> "/r/" <> batch.review.token
    settings_url = CritWeb.Endpoint.url() <> "/settings"
    subject = "#{length(items)} new updates on your Crit review"

    new()
    |> to(batch.recipient.email)
    |> from(Application.fetch_env!(:crit, :smtp_from))
    |> subject(subject)
    |> text_body(text_body(batch, shown, more, review_url, settings_url))
    |> html_body(html_body(batch, shown, more, review_url, settings_url))
  end

  defp text_body(batch, items, more, review_url, settings_url) do
    entries =
      items
      |> group_by_thread()
      |> Enum.map_join("\n", fn {_thread_id, comments} ->
        comments
        |> Enum.map_join("\n", fn comment ->
          "• #{actor_name(comment)}: #{excerpt(comment.body)}"
        end)
      end)

    """
    #{Crit.Reviews.display_filename(batch.review)}

    #{entries}#{more_text(more)}

    View the review: #{review_url}

    This message combines recent discussion activity after a short quiet period.
    Notification settings: #{settings_url}
    """
  end

  defp html_body(batch, items, more, review_url, settings_url) do
    entries =
      items
      |> group_by_thread()
      |> Enum.map_join(fn {_thread_id, comments} ->
        body =
          Enum.map_join(comments, fn comment ->
            "<li><strong>#{escape(actor_name(comment))}</strong>: #{escape(excerpt(comment.body))}</li>"
          end)

        "<ul>#{body}</ul>"
      end)

    """
    <div style="font-family:system-ui,sans-serif;max-width:640px;margin:auto;color:#202124">
      <h1 style="font-size:20px">#{escape(Crit.Reviews.display_filename(batch.review))}</h1>
      #{entries}
      #{more_html(more, review_url)}
      <p><a href="#{escape(review_url)}" style="display:inline-block;padding:10px 16px;background:#6d5dfc;color:white;text-decoration:none;border-radius:6px">View review</a></p>
      <p style="color:#666;font-size:13px">This message combines recent discussion activity after a short quiet period.</p>
      <p style="color:#666;font-size:13px"><a href="#{escape(settings_url)}">Notification settings</a></p>
    </div>
    """
  end

  defp group_by_thread(items) do
    items
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.group_by(fn item -> item.comment.parent_id || item.comment.id end, & &1.comment)
    |> Enum.sort_by(fn {_id, comments} -> List.first(comments).inserted_at end, DateTime)
  end

  defp actor_name(%{author_display_name: name}) when is_binary(name) and name != "", do: name
  defp actor_name(_comment), do: "Anonymous user"

  defp excerpt(body) do
    body
    |> to_string()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @excerpt_length)
    |> then(fn shortened ->
      if String.length(body || "") > @excerpt_length, do: shortened <> "…", else: shortened
    end)
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  defp more_text(0), do: ""
  defp more_text(count), do: "\n…and #{count} more"
  defp more_html(0, _url), do: ""
  defp more_html(count, url), do: ~s(<p><a href="#{escape(url)}">and #{count} more</a></p>)
end
