defmodule Crit.Output do
  @moduledoc "Generates export formats — port of crit's output.go."

  alias Crit.Comment

  @doc """
  Interleaves comment blockquotes into the original markdown content,
  inserted after each comment's end_line. Matches crit's .review.md format.
  """
  def generate_review_md(content, []), do: content

  def generate_review_md(content, comments) do
    lines = String.split(content, "\n")
    total = length(lines)

    # Sub-threads have no lines: each shows under the message it comments on.
    {threads, sub_threads} = split_sub_threads(comments)

    insert_after =
      threads
      |> Enum.filter(&shown?(&1, sub_threads))
      |> Enum.sort_by(&{&1.end_line, &1.start_line})
      |> Enum.group_by(& &1.end_line)

    lines
    |> Enum.with_index(1)
    |> Enum.map(fn {line, line_num} ->
      suffix = if line_num < total, do: "\n", else: ""

      comment_blocks =
        insert_after
        |> Map.get(line_num, [])
        |> Enum.map_join("", fn c -> "\n" <> format_comment(c, sub_threads) <> "\n" end)

      line <> suffix <> comment_blocks
    end)
    |> Enum.join("")
  end

  @doc """
  Formats a single comment as a markdown blockquote, including author and
  replies, and under each message its sub-threads (indexed by message id).
  """
  def format_comment(%Comment{} = c, sub_threads \\ %{}) do
    line_ref =
      if c.start_line == c.end_line,
        do: "Line #{c.start_line}",
        else: "Lines #{c.start_line}-#{c.end_line}"

    author_part = if c.author_display_name, do: " — #{c.author_display_name}", else: ""
    format_thread(c, "REVIEW COMMENT — #{line_ref}#{author_part}", sub_threads)
  end

  # The threads placed on lines, and the sub-threads by the id of the message
  # they comment on.
  defp split_sub_threads(comments) do
    {sub_threads, threads} = Enum.split_with(comments, & &1.anchor_comment_id)
    {threads, Enum.group_by(sub_threads, & &1.anchor_comment_id)}
  end

  # A resolved thread still shows while a sub-thread under it is open.
  defp shown?(%Comment{resolved: true} = c, sub_threads), do: open_below?(c, sub_threads)
  defp shown?(_c, _sub_threads), do: true

  defp open_below?(%Comment{} = c, sub_threads) do
    [c | loaded_replies(c)]
    |> Enum.flat_map(&Map.get(sub_threads, &1.id, []))
    |> Enum.any?(&(not &1.resolved or open_below?(&1, sub_threads)))
  end

  defp format_thread(%Comment{} = c, label, sub_threads) do
    label = if c.resolved, do: label <> " (resolved)", else: label

    [first | rest] = String.split(c.body, "\n")
    quoted_rest = Enum.map_join(rest, "", fn line -> "\n> " <> line end)

    parent_block =
      "> **[#{label}]**: #{first}#{quoted_rest}" <> format_sub_threads(c, sub_threads)

    replies = loaded_replies(c)

    case replies do
      [] ->
        parent_block

      replies ->
        reply_blocks =
          replies
          |> Enum.reject(& &1.resolved)
          |> Enum.map(&(format_reply(&1) <> format_sub_threads(&1, sub_threads)))

        case reply_blocks do
          [] -> parent_block
          blocks -> parent_block <> "\n> \n" <> Enum.join(blocks, "\n")
        end
    end
  end

  defp format_sub_threads(%Comment{id: id}, sub_threads) do
    sub_threads
    |> Map.get(id, [])
    |> Enum.filter(&shown?(&1, sub_threads))
    |> Enum.map_join(fn s ->
      quote_part = if s.quote in [nil, ""], do: "", else: ~s( on "#{quote_excerpt(s.quote)}")
      author_part = if s.author_display_name, do: " — #{s.author_display_name}", else: ""

      block = format_thread(s, "SUB-THREAD#{quote_part}#{author_part}", sub_threads)
      "\n> \n" <> Enum.map_join(String.split(block, "\n"), "\n", &("> " <> &1))
    end)
  end

  @quote_excerpt_length 80

  defp quote_excerpt(text) do
    text = text |> String.replace(~r/\s+/u, " ") |> String.trim()

    if String.length(text) > @quote_excerpt_length,
      do: String.slice(text, 0, @quote_excerpt_length - 1) <> "…",
      else: text
  end

  defp loaded_replies(%Comment{replies: %Ecto.Association.NotLoaded{}}), do: []
  defp loaded_replies(%Comment{replies: replies}) when is_list(replies), do: replies
  defp loaded_replies(_), do: []

  defp format_reply(%Comment{} = r) do
    author = r.author_display_name || "Anonymous"

    [first | rest] = String.split(r.body, "\n")
    quoted_rest = Enum.map_join(rest, "", fn line -> "\n> " <> line end)

    "> **Reply (#{author})**: #{first}#{quoted_rest}"
  end

  @doc "Generate review markdown for multi-file reviews, with file headers."
  def generate_multi_file_review_md(files, comments) do
    comments_by_file = Enum.group_by(comments, & &1.file_path)

    files
    |> Enum.map(fn file ->
      file_comments = Map.get(comments_by_file, file.path, [])
      header = "## #{file.path}\n\n"
      body = generate_review_md(file.content, file_comments)
      header <> body
    end)
    |> Enum.join("\n\n---\n\n")
  end

  @doc "Serialize review + comments to review file shape for agent consumption."
  def multi_file_comments_json(review, files, comments, base_url) do
    comments_by_file =
      comments
      |> Enum.filter(& &1.file_path)
      |> Enum.group_by(& &1.file_path)

    file_map =
      files
      |> Enum.map(fn file ->
        file_comments = Map.get(comments_by_file, file.path, [])
        {file.path, %{comments: Enum.map(file_comments, &serialize_comment_for_export/1)}}
      end)
      |> Map.new()

    %{
      review_round: review.review_round,
      visibility: review.visibility,
      comment_policy: review.comment_policy,
      share_url: base_url <> "/r/#{review.token}",
      delete_token: review.delete_token,
      updated_at: DateTime.to_iso8601(review.updated_at),
      files: file_map
    }
  end

  defp serialize_comment_for_export(%Comment{} = c) do
    replies =
      case c.replies do
        %Ecto.Association.NotLoaded{} -> []
        list -> list
      end

    %{
      id: c.id,
      start_line: c.start_line,
      end_line: c.end_line,
      body: c.body,
      quote: c.quote,
      quote_offset: c.quote_offset,
      anchor: c.anchor,
      drifted: c.drifted,
      scope: c.scope || "line",
      author: c.author_display_name,
      dom_anchor: c.dom_anchor,
      review_round: c.review_round,
      resolved: c.resolved,
      resolved_round: c.resolved_round,
      external_id: c.external_id,
      created_at: DateTime.to_iso8601(c.inserted_at),
      updated_at: DateTime.to_iso8601(c.updated_at),
      replies:
        Enum.map(replies, fn r ->
          %{
            id: r.id,
            body: r.body,
            author: r.author_display_name,
            created_at: DateTime.to_iso8601(r.inserted_at)
          }
        end)
    }
    |> put_parent_id(c)
  end

  # A sub-thread carries `parent_id`, as in crit's review file.
  defp put_parent_id(map, %Comment{anchor_comment_id: nil}), do: map
  defp put_parent_id(map, %Comment{anchor_comment_id: id}), do: Map.put(map, :parent_id, id)
end
