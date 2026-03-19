defmodule Crit.OutputTest do
  use Crit.DataCase, async: true

  alias Crit.Comment
  alias Crit.Output

  describe "generate_review_md/2" do
    test "returns content unchanged with no comments" do
      assert Output.generate_review_md("hello\nworld", []) == "hello\nworld"
    end

    test "interleaves comments after their end_line" do
      content = "line1\nline2\nline3"

      comments = [
        %Comment{start_line: 2, end_line: 2, body: "fix this"}
      ]

      result = Output.generate_review_md(content, comments)
      assert result =~ "line2"
      assert result =~ "> **[REVIEW COMMENT — Line 2]**: fix this"
    end

    test "excludes resolved comments from output" do
      content = "line1\nline2\nline3"

      comments = [
        %Comment{start_line: 1, end_line: 1, body: "unresolved", resolved: false},
        %Comment{start_line: 2, end_line: 2, body: "resolved", resolved: true}
      ]

      result = Output.generate_review_md(content, comments)
      assert result =~ "unresolved"
      refute result =~ "> **[REVIEW COMMENT — Line 2]**: resolved"
    end

    test "emits nothing when all comments on a line are resolved" do
      content = "line1\nline2"

      comments = [
        %Comment{start_line: 1, end_line: 1, body: "done", resolved: true},
        %Comment{start_line: 1, end_line: 1, body: "also done", resolved: true}
      ]

      result = Output.generate_review_md(content, comments)
      refute result =~ "REVIEW COMMENT"
    end
  end

  describe "format_comment/1" do
    test "includes author display name in header" do
      comment = %Comment{
        start_line: 4,
        end_line: 4,
        body: "Bold choice.",
        author_display_name: "Tomasz"
      }

      result = Output.format_comment(comment)
      assert result == "> **[REVIEW COMMENT — Line 4 — Tomasz]**: Bold choice."
    end

    test "renders without author when author_display_name is nil" do
      comment = %Comment{
        start_line: 4,
        end_line: 4,
        body: "Anonymous feedback.",
        author_display_name: nil
      }

      result = Output.format_comment(comment)
      assert result == "> **[REVIEW COMMENT — Line 4]**: Anonymous feedback."
    end

    test "renders line range for multi-line comments" do
      comment = %Comment{
        start_line: 2,
        end_line: 5,
        body: "Refactor this block.",
        author_display_name: "Alice"
      }

      result = Output.format_comment(comment)
      assert result =~ "Lines 2-5 — Alice"
    end

    test "includes replies under parent comment" do
      comment = %Comment{
        start_line: 4,
        end_line: 4,
        body: "Bold choice.",
        author_display_name: "Tomasz",
        replies: [
          %Comment{
            body: "COBOL has better error messages. Strong +1.",
            author_display_name: "Senior Architect",
            resolved: false
          },
          %Comment{
            body: "What's COBOL?",
            author_display_name: "Intern",
            resolved: false
          }
        ]
      }

      result = Output.format_comment(comment)
      assert result =~ "> **[REVIEW COMMENT — Line 4 — Tomasz]**: Bold choice."
      assert result =~ "> **Reply (Senior Architect)**: COBOL has better error messages."
      assert result =~ "> **Reply (Intern)**: What's COBOL?"
    end

    test "reply with nil author renders as Anonymous" do
      comment = %Comment{
        start_line: 1,
        end_line: 1,
        body: "Parent.",
        author_display_name: nil,
        replies: [
          %Comment{body: "A reply.", author_display_name: nil, resolved: false}
        ]
      }

      result = Output.format_comment(comment)
      assert result =~ "> **Reply (Anonymous)**: A reply."
    end

    test "excludes resolved replies" do
      comment = %Comment{
        start_line: 1,
        end_line: 1,
        body: "Parent.",
        author_display_name: "Author",
        replies: [
          %Comment{body: "Visible reply.", author_display_name: "A", resolved: false},
          %Comment{body: "Resolved reply.", author_display_name: "B", resolved: true}
        ]
      }

      result = Output.format_comment(comment)
      assert result =~ "Visible reply."
      refute result =~ "Resolved reply."
    end

    test "handles multiline comment body" do
      comment = %Comment{
        start_line: 1,
        end_line: 1,
        body: "First line.\nSecond line.",
        author_display_name: "Author"
      }

      result = Output.format_comment(comment)
      assert result == "> **[REVIEW COMMENT — Line 1 — Author]**: First line.\n> Second line."
    end

    test "handles multiline reply body" do
      comment = %Comment{
        start_line: 1,
        end_line: 1,
        body: "Parent.",
        author_display_name: nil,
        replies: [
          %Comment{
            body: "Reply line 1.\nReply line 2.",
            author_display_name: "Replier",
            resolved: false
          }
        ]
      }

      result = Output.format_comment(comment)
      assert result =~ "> **Reply (Replier)**: Reply line 1.\n> Reply line 2."
    end

    test "handles unloaded replies association gracefully" do
      comment = %Comment{
        start_line: 1,
        end_line: 1,
        body: "No replies loaded.",
        author_display_name: "Author"
      }

      # Default struct has NotLoaded for replies - should not crash
      result = Output.format_comment(comment)
      assert result == "> **[REVIEW COMMENT — Line 1 — Author]**: No replies loaded."
    end
  end

  describe "generate_multi_file_review_md/2" do
    test "interleaves comments per file" do
      files = [
        %{path: "a.go", content: "package a\nfunc A() {}"},
        %{path: "b.go", content: "package b\nfunc B() {}"}
      ]

      comments = [
        %Comment{start_line: 1, end_line: 1, body: "rename", file_path: "a.go"},
        %Comment{start_line: 2, end_line: 2, body: "add docs", file_path: "b.go"}
      ]

      result = Output.generate_multi_file_review_md(files, comments)
      assert result =~ "## a.go"
      assert result =~ "package a"
      assert result =~ "> **[REVIEW COMMENT — Line 1]**: rename"
      assert result =~ "## b.go"
      assert result =~ "package b"
      assert result =~ "> **[REVIEW COMMENT — Line 2]**: add docs"
    end

    test "separates files with horizontal rule" do
      files = [
        %{path: "a.go", content: "package a"},
        %{path: "b.go", content: "package b"}
      ]

      result = Output.generate_multi_file_review_md(files, [])
      assert result =~ "---"
    end

    test "handles files with no comments" do
      files = [
        %{path: "a.go", content: "package a"},
        %{path: "b.go", content: "package b"}
      ]

      result = Output.generate_multi_file_review_md(files, [])
      assert result =~ "## a.go"
      assert result =~ "## b.go"
      refute result =~ "REVIEW COMMENT"
    end
  end

  describe "multi_file_comments_json/2" do
    test "groups comments by file path" do
      ts = ~U[2026-01-01 00:00:00Z]

      files = [
        %{path: "a.go"},
        %{path: "b.go"}
      ]

      comments = [
        %Comment{
          id: "1",
          start_line: 1,
          end_line: 1,
          body: "fix",
          file_path: "a.go",
          inserted_at: ts,
          updated_at: ts
        },
        %Comment{
          id: "2",
          start_line: 1,
          end_line: 1,
          body: "ok",
          file_path: "b.go",
          inserted_at: ts,
          updated_at: ts
        }
      ]

      result = Output.multi_file_comments_json(files, comments)
      assert Map.has_key?(result.files, "a.go")
      assert Map.has_key?(result.files, "b.go")
      assert length(result.files["a.go"].comments) == 1
      assert length(result.files["b.go"].comments) == 1
    end

    test "filters out comments with nil file_path" do
      ts = ~U[2026-01-01 00:00:00Z]

      files = [%{path: "a.go"}]

      comments = [
        %Comment{
          id: "1",
          start_line: 1,
          end_line: 1,
          body: "fix",
          file_path: "a.go",
          inserted_at: ts,
          updated_at: ts
        },
        %Comment{
          id: "2",
          start_line: 1,
          end_line: 1,
          body: "orphan",
          file_path: nil,
          inserted_at: ts,
          updated_at: ts
        }
      ]

      result = Output.multi_file_comments_json(files, comments)
      assert length(result.files["a.go"].comments) == 1
    end

    test "includes empty comments list for files without comments" do
      files = [
        %{path: "a.go"},
        %{path: "b.go"}
      ]

      result = Output.multi_file_comments_json(files, [])
      assert result.files["a.go"].comments == []
      assert result.files["b.go"].comments == []
    end
  end
end
