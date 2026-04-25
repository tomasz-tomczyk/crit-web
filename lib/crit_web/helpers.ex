defmodule CritWeb.Helpers do
  @moduledoc "Shared helper functions for LiveViews and templates."

  @doc "Formats a datetime as a human-readable relative time string."
  def time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> "#{div(diff, 604_800)}w ago"
    end
  end

  @doc """
  Classifies how recently a review has been touched. Drives the leading
  status dot color in the reviews list (green / yellow / muted).
  """
  def activity_status(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 86_400 -> :active
      diff < 604_800 -> :idle
      true -> :stale
    end
  end

  @doc """
  Splits a path into `{directory, filename}` so the directory portion
  can be dimmed and the filename emphasized in the reviews list.
  """
  def split_path(nil), do: {"", "Untitled"}

  def split_path(path) when is_binary(path) do
    case path |> String.split("/", trim: false) |> Enum.reverse() do
      [filename] -> {"", filename}
      [filename | rest] -> {(rest |> Enum.reverse() |> Enum.join("/")) <> "/", filename}
    end
  end

  @snippet_lines 10

  @doc """
  Builds a snippet preview for the reviews list.

  Returns one of:
    * `{:markdown, safe_html}` — for `.md` / `.markdown` files; first ~10 source
      lines rendered to HTML via Earmark, marked safe for direct injection.
    * `{:code, [line_string, ...]}` — line-numbered plain-text preview for any
      other file type (or markdown when rendering fails).
    * `:none` — when there is no file content available.
  """
  def snippet_preview(_path, nil), do: :none
  def snippet_preview(_path, ""), do: :none

  def snippet_preview(path, content) when is_binary(content) do
    lines = content |> String.split("\n") |> Enum.take(@snippet_lines)

    cond do
      markdown?(path) ->
        case Earmark.as_html(Enum.join(lines, "\n"),
               escape: true,
               compact_output: true,
               smartypants: false
             ) do
          {:ok, html, _} -> {:markdown, Phoenix.HTML.raw(html)}
          _ -> {:code, lines}
        end

      true ->
        {:code, lines}
    end
  end

  defp markdown?(nil), do: false

  defp markdown?(path) when is_binary(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in [".md", ".markdown", ".mdown", ".mkd"]
  end

  @doc """
  Maps a file path to a highlight.js language id for syntax highlighting.
  Returns `nil` when the extension is unknown — the snippet should render
  as plain text in that case.
  """
  def language_for_path(nil), do: nil

  def language_for_path(path) when is_binary(path) do
    case path |> Path.extname() |> String.downcase() do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".eex" -> "elixir"
      ".heex" -> "elixir"
      ".js" -> "javascript"
      ".jsx" -> "javascript"
      ".mjs" -> "javascript"
      ".cjs" -> "javascript"
      ".ts" -> "typescript"
      ".tsx" -> "typescript"
      ".py" -> "python"
      ".rb" -> "ruby"
      ".go" -> "go"
      ".rs" -> "rust"
      ".java" -> "java"
      ".kt" -> "kotlin"
      ".swift" -> "swift"
      ".c" -> "c"
      ".h" -> "c"
      ".cpp" -> "cpp"
      ".cc" -> "cpp"
      ".hpp" -> "cpp"
      ".cs" -> "csharp"
      ".php" -> "php"
      ".sh" -> "bash"
      ".bash" -> "bash"
      ".zsh" -> "bash"
      ".fish" -> "bash"
      ".sql" -> "sql"
      ".yaml" -> "yaml"
      ".yml" -> "yaml"
      ".json" -> "json"
      ".toml" -> "ini"
      ".ini" -> "ini"
      ".xml" -> "xml"
      ".html" -> "xml"
      ".css" -> "css"
      ".scss" -> "scss"
      ".dockerfile" -> "dockerfile"
      _ -> nil
    end
  end
end
