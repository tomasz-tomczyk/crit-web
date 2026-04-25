defmodule CritWeb.Components.ReviewSnippetTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CritWeb.Components.ReviewSnippet

  describe "review_snippet/1" do
    test "renders a code block with line numbers for source files" do
      html =
        render_component(&ReviewSnippet.review_snippet/1,
          path: "lib/foo.ex",
          content: "defmodule Foo do\n  def bar, do: :ok\nend"
        )

      assert html =~ "data-snippet-line"
      assert html =~ ~s(data-lang="elixir")
      assert html =~ "defmodule Foo do"
      assert html =~ "def bar, do: :ok"
      # line numbers (rendered inside the gutter span with whitespace)
      assert html =~ ~r{>\s*1\s*<}
      assert html =~ ~r{>\s*2\s*<}
    end

    test "omits data-lang for unknown extensions" do
      html =
        render_component(&ReviewSnippet.review_snippet/1,
          path: "data.unknownext",
          content: "raw text"
        )

      assert html =~ "data-snippet-line"
      refute html =~ "data-lang=\"elixir\""
    end

    test "renders rendered markdown for .md files" do
      html =
        render_component(&ReviewSnippet.review_snippet/1,
          path: "README.md",
          content: "# Hello\n\nWorld"
        )

      assert html =~ "<h1>Hello</h1>"
      assert html =~ "<p>World</p>"
    end

    test "renders the empty state when content is missing" do
      html =
        render_component(&ReviewSnippet.review_snippet/1,
          path: "lib/foo.ex",
          content: nil
        )

      assert html =~ "No preview available"
      refute html =~ "data-snippet-line"
    end

    test "renders the empty state when content is an empty string" do
      html =
        render_component(&ReviewSnippet.review_snippet/1,
          path: "lib/foo.ex",
          content: ""
        )

      assert html =~ "No preview available"
    end

    test "caps code preview at 10 lines" do
      content = Enum.map_join(1..30, "\n", &"line #{&1}")

      html =
        render_component(&ReviewSnippet.review_snippet/1,
          path: "lib/many.ex",
          content: content
        )

      assert html =~ "line 10"
      refute html =~ "line 11"
    end
  end
end
