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

    insert_after =
      comments
      |> Enum.reject(& &1.resolved)
      |> Enum.sort_by(&{&1.end_line, &1.start_line})
      |> Enum.group_by(& &1.end_line)

    lines
    |> Enum.with_index(1)
    |> Enum.map(fn {line, line_num} ->
      suffix = if line_num < total, do: "\n", else: ""

      comment_blocks =
        insert_after
        |> Map.get(line_num, [])
        |> Enum.map_join("", fn c -> "\n" <> format_comment(c) <> "\n" end)

      line <> suffix <> comment_blocks
    end)
    |> Enum.join("")
  end

  @doc "Formats a single comment as a markdown blockquote, including author and replies."
  def format_comment(%Comment{} = c) do
    line_ref =
      if c.start_line == c.end_line,
        do: "Line #{c.start_line}",
        else: "Lines #{c.start_line}-#{c.end_line}"

    author_part = if c.author_display_name, do: " — #{c.author_display_name}", else: ""
    header = "#{line_ref}#{author_part}"

    [first | rest] = String.split(c.body, "\n")
    quoted_rest = Enum.map_join(rest, "", fn line -> "\n> " <> line end)

    parent_block = "> **[REVIEW COMMENT — #{header}]**: #{first}#{quoted_rest}"

    replies = loaded_replies(c)

    case replies do
      [] ->
        parent_block

      replies ->
        reply_blocks =
          replies
          |> Enum.reject(& &1.resolved)
          |> Enum.map(&format_reply/1)

        case reply_blocks do
          [] -> parent_block
          blocks -> parent_block <> "\n> \n" <> Enum.join(blocks, "\n")
        end
    end
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
      scope: c.scope || "line",
      author: c.author_display_name,
      review_round: c.review_round,
      resolved: c.resolved,
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
  end
end
