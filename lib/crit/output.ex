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

  @doc "Formats a single comment as a markdown blockquote."
  def format_comment(%Comment{} = c) do
    header =
      if c.start_line == c.end_line,
        do: "Line #{c.start_line}",
        else: "Lines #{c.start_line}-#{c.end_line}"

    [first | rest] = String.split(c.body, "\n")
    quoted_rest = Enum.map_join(rest, "", fn line -> "\n> " <> line end)

    "> **[REVIEW COMMENT — #{header}]**: #{first}#{quoted_rest}"
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

  @doc "Serialize multi-file comments to .crit.json shape."
  def multi_file_comments_json(files, comments) do
    comments_by_file =
      comments
      |> Enum.filter(& &1.file_path)
      |> Enum.group_by(& &1.file_path)

    file_map =
      files
      |> Enum.map(fn file ->
        file_comments = Map.get(comments_by_file, file.path, [])

        {file.path,
         %{
           comments:
             Enum.map(file_comments, fn c ->
               %{
                 id: c.id,
                 start_line: c.start_line,
                 end_line: c.end_line,
                 body: c.body,
                 quote: c.quote,
                 resolved: false,
                 created_at: DateTime.to_iso8601(c.inserted_at),
                 updated_at: DateTime.to_iso8601(c.updated_at)
               }
             end)
         }}
      end)
      |> Map.new()

    %{files: file_map}
  end
end
