defmodule Crit.Articles do
  @moduledoc """
  Static article catalog loaded from `priv/articles/*/index.md`.

  Each file uses YAML frontmatter for metadata and a markdown body rendered
  with MDEx.
  """

  @doc "All articles, newest first."
  def list do
    articles_root()
    |> Path.join("*/index.md")
    |> Path.wildcard()
    |> Enum.map(&build_article/1)
    |> Enum.sort_by(& &1.published_at, {:desc, Date})
  end

  @doc "The three most recent articles — for homepage highlights."
  def recent(limit \\ 3), do: list() |> Enum.take(limit)

  @doc "Lookup a single article by slug."
  def get(slug), do: Enum.find(list(), &(&1.slug == slug))

  @doc "Human-readable date for article cards and headers."
  def format_date(%Date{} = date) do
    Calendar.strftime(date, "%b %-d, %Y")
  end

  def format_date_iso(%Date{} = date), do: Date.to_iso8601(date)

  defp articles_root, do: Path.join(:code.priv_dir(:crit), "articles")

  defp build_article(path) do
    {frontmatter, body} = path |> File.read!() |> parse_frontmatter()
    slug = frontmatter["slug"] || Path.basename(Path.dirname(path))

    body_html =
      case MDEx.to_html(body) do
        {:ok, html} -> postprocess_html(html)
        _ -> "<p>Failed to render article.</p>"
      end

    %{
      slug: slug,
      title: frontmatter["title"],
      excerpt: frontmatter["excerpt"],
      category: frontmatter["category"],
      published_at: parse_date!(frontmatter["published_at"]),
      read_time: frontmatter["read_time"],
      hero_image: frontmatter["hero_image"],
      author: frontmatter["author"],
      body_html: Phoenix.HTML.raw(body_html)
    }
  end

  defp parse_frontmatter(content) do
    case Regex.run(~r/\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z/s, content) do
      [_, yaml, body] -> {parse_yaml(yaml), String.trim_leading(body)}
      _ -> {%{}, content}
    end
  end

  defp parse_yaml(yaml) do
    yaml
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp parse_date!(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> raise "invalid published_at: #{inspect(value)}"
    end
  end

  defp postprocess_html(html) do
    html
    |> mermaid_blocks()
    |> lazy_images()
  end

  defp mermaid_blocks(html) do
    Regex.replace(~r/<pre><code class="language-mermaid">([\s\S]*?)<\/code><\/pre>/, html, fn _,
                                                                                              src ->
      decoded =
        src
        |> String.replace("&amp;", "&")
        |> String.replace("&lt;", "<")
        |> String.replace("&gt;", ">")
        |> String.replace("&#39;", "'")
        |> String.replace("&quot;", "\"")

      ~s(<pre class="mermaid">#{decoded}</pre>)
    end)
  end

  defp lazy_images(html) do
    String.replace(html, "<img ", ~s(<img loading="lazy" decoding="async" ))
  end
end
