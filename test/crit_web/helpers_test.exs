defmodule CritWeb.HelpersTest do
  use ExUnit.Case, async: true

  alias CritWeb.Helpers

  describe "time_ago/1" do
    test "renders 'just now' under a minute" do
      now = DateTime.utc_now()
      assert Helpers.time_ago(now) == "just now"
    end

    test "renders minutes" do
      ts = DateTime.add(DateTime.utc_now(), -120, :second)
      assert Helpers.time_ago(ts) == "2m ago"
    end

    test "renders hours" do
      ts = DateTime.add(DateTime.utc_now(), -7200, :second)
      assert Helpers.time_ago(ts) == "2h ago"
    end

    test "renders days" do
      ts = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
      assert Helpers.time_ago(ts) == "3d ago"
    end

    test "renders weeks" do
      ts = DateTime.add(DateTime.utc_now(), -2 * 604_800, :second)
      assert Helpers.time_ago(ts) == "2w ago"
    end
  end

  describe "activity_status/1" do
    test "active when within the last day" do
      ts = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert Helpers.activity_status(ts) == :active
    end

    test "idle between one day and one week" do
      ts = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
      assert Helpers.activity_status(ts) == :idle
    end

    test "stale beyond one week" do
      ts = DateTime.add(DateTime.utc_now(), -8 * 86_400, :second)
      assert Helpers.activity_status(ts) == :stale
    end
  end

  describe "split_path/1" do
    test "nil path returns Untitled" do
      assert Helpers.split_path(nil) == {"", "Untitled"}
    end

    test "bare filename has empty directory" do
      assert Helpers.split_path("README.md") == {"", "README.md"}
    end

    test "splits directory from filename" do
      assert Helpers.split_path("apps/billing/lib/generator.ex") ==
               {"apps/billing/lib/", "generator.ex"}
    end

    test "single-level directory" do
      assert Helpers.split_path("scripts/migrate.sh") == {"scripts/", "migrate.sh"}
    end
  end

  describe "snippet_preview/2" do
    test "returns :none when content is nil" do
      assert Helpers.snippet_preview("foo.ex", nil) == :none
    end

    test "returns :none when content is empty" do
      assert Helpers.snippet_preview("foo.ex", "") == :none
    end

    test "returns {:code, lines} for non-markdown files" do
      content = "defmodule Foo do\n  def bar, do: :ok\nend"
      assert {:code, lines} = Helpers.snippet_preview("foo.ex", content)
      assert lines == ["defmodule Foo do", "  def bar, do: :ok", "end"]
    end

    test "caps the snippet at 10 lines" do
      content = Enum.map_join(1..50, "\n", &"line #{&1}")
      assert {:code, lines} = Helpers.snippet_preview("foo.ex", content)
      assert length(lines) == 10
      assert hd(lines) == "line 1"
    end

    test "renders markdown for .md files" do
      content = "# Title\n\nBody text"
      assert {:markdown, html} = Helpers.snippet_preview("README.md", content)
      rendered = Phoenix.HTML.safe_to_string(html)
      assert rendered =~ "<h1>"
      assert rendered =~ "Title"
      assert rendered =~ "<p>"
    end

    test "recognizes other markdown extensions" do
      assert {:markdown, _} = Helpers.snippet_preview("doc.markdown", "# x")
      assert {:markdown, _} = Helpers.snippet_preview("doc.mdown", "# x")
      assert {:markdown, _} = Helpers.snippet_preview("doc.mkd", "# x")
    end

    test "extension match is case-insensitive" do
      assert {:markdown, _} = Helpers.snippet_preview("README.MD", "# x")
    end
  end

  describe "language_for_path/1" do
    test "returns nil for nil path" do
      assert Helpers.language_for_path(nil) == nil
    end

    test "maps elixir extensions" do
      assert Helpers.language_for_path("foo.ex") == "elixir"
      assert Helpers.language_for_path("foo.exs") == "elixir"
      assert Helpers.language_for_path("foo.heex") == "elixir"
    end

    test "maps javascript family" do
      assert Helpers.language_for_path("foo.js") == "javascript"
      assert Helpers.language_for_path("foo.mjs") == "javascript"
      assert Helpers.language_for_path("foo.ts") == "typescript"
      assert Helpers.language_for_path("foo.tsx") == "typescript"
    end

    test "maps shell scripts" do
      assert Helpers.language_for_path("script.sh") == "bash"
      assert Helpers.language_for_path("script.zsh") == "bash"
    end

    test "maps html and xml to xml" do
      assert Helpers.language_for_path("page.html") == "xml"
      assert Helpers.language_for_path("config.xml") == "xml"
    end

    test "returns nil for unknown extensions" do
      assert Helpers.language_for_path("README") == nil
      assert Helpers.language_for_path("data.unknownext") == nil
    end

    test "extension match is case-insensitive" do
      assert Helpers.language_for_path("Foo.EX") == "elixir"
    end
  end
end
