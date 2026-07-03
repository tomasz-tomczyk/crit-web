defmodule Crit.ArticlesTest do
  use ExUnit.Case, async: true

  alias Crit.Articles

  test "list/0 returns articles newest first" do
    articles = Articles.list()
    assert length(articles) >= 1

    dates = Enum.map(articles, & &1.published_at)
    assert dates == Enum.sort(dates, {:desc, Date})
  end

  test "recent/1 returns the newest articles" do
    recent = Articles.recent(2)
    assert recent == Enum.take(Articles.list(), 2)
  end

  test "get/1 finds by slug" do
    assert %{slug: "how-to-plan-document-and-review"} =
             Articles.get("how-to-plan-document-and-review")

    refute Articles.get("missing-slug")
  end

  test "article markdown files live under :code.priv_dir/1 (release layout)" do
    root = Path.join(:code.priv_dir(:crit), "articles")
    assert File.dir?(root)

    paths = Path.wildcard(Path.join(root, "*/index.md"))
    assert paths != []
    assert Enum.all?(paths, &File.regular?/1)
  end

  test "renders markdown body as HTML" do
    article = Articles.get("how-to-plan-document-and-review")
    html = Phoenix.HTML.safe_to_string(article.body_html)
    assert html =~ "Superpowers"
    assert html =~ "assets.crit.md/articles/how-to-plan-document-and-review/01_installed.png"
    assert html =~ ~s(<pre class="mermaid">)
  end
end
