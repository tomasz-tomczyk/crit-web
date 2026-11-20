defmodule CritWeb.E2E.SyntaxHighlightingTest do
  use CritWeb.E2ECase, async: true

  import Bitwise

  # One highlighter, as in crit: Shiki (crit's vendored @pierre/diffs build) for
  # code files, fenced code in documents and fenced code in comments. Token
  # spans carry --diffs-token-light / --diffs-token-dark; there is no hljs.

  @doc_md Enum.join(
            [
              "# Plan",
              "",
              "```elixir",
              "defmodule Plan do",
              "  def run, do: :ok",
              "end",
              "```",
              "",
              "- Step",
              "  ```js",
              "  const x = 1",
              "  ```",
              "",
              "```not-a-language",
              "plain <text>",
              "```",
              ""
            ],
            "\n"
          )

  describe "Syntax highlighting" do
    setup %{request: request, page: page} do
      review =
        create_review(request,
          files: [
            %{path: "plan.md", content: @doc_md},
            %{path: "page.html.heex", content: ~s(<div class="a">\n  <%= @name %>\n</div>\n)}
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      load_review(page, review.token)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "fenced code in documents is highlighted per line on first paint", %{page: page} do
      fence =
        page
        |> Page.locator(~s(.line-block[data-file-path="plan.md"] code.crit-code))
        |> Locator.filter(has_text: "defmodule Plan do")

      Expect.to_be_visible!(
        Locator.first(Locator.locator(fence, ~s(span[style*="--diffs-token-dark"])))
      )

      # Each fence line is its own commentable block.
      Expect.to_contain_text!(
        Page.locator(
          page,
          ~s(.line-block[data-file-path="plan.md"][data-start-line="5"] code.crit-code)
        ),
        "def run"
      )

      Expect.to_have_count!(Page.locator(page, ".hljs, [class^='hljs-']"), 0)
    end

    test "fences nested in lists are highlighted once mounted", %{page: page} do
      nested =
        Page.locator(page, ~s(.line-block[data-file-path="plan.md"] pre > code.language-js))

      Expect.to_have_class!(nested, ~r/crit-code/)

      Expect.to_be_visible!(
        Locator.first(Locator.locator(nested, ~s(span[style*="--diffs-token"])))
      )
    end

    test "unknown languages render as plain text", %{page: page} do
      plain =
        page
        |> Page.locator(~s(.line-block[data-file-path="plan.md"] code.crit-code))
        |> Locator.filter(has_text: "plain <text>")

      Expect.to_be_visible!(plain)
      Expect.to_have_count!(Locator.locator(plain, "span[style]"), 0)
    end

    test "code files are highlighted by file name, HEEx as HTML", %{page: page} do
      page
      |> code_line("page.html.heex", 1)
      |> Locator.locator(~s(span[style*="--diffs-token"]))
      |> Locator.first()
      |> Expect.to_be_visible!()
    end

    test "the light theme uses the light token colour", %{page: page} do
      span =
        page
        |> Page.locator(~s(.line-block[data-file-path="plan.md"] code.crit-code span[style]))
        |> Locator.first()

      Expect.to_be_visible!(span)

      colours = fn ->
        Locator.evaluate!(span, """
        (el) => ({
          color: getComputedStyle(el).color,
          light: el.style.getPropertyValue("--diffs-token-light"),
          dark: el.style.getPropertyValue("--diffs-token-dark"),
        })
        """)
      end

      to_rgb = fn hex ->
        n = hex |> String.replace("#", "") |> String.slice(0, 6) |> String.to_integer(16)
        "rgb(#{n >>> 16 &&& 255}, #{n >>> 8 &&& 255}, #{n &&& 255})"
      end

      Page.evaluate!(page, ~s|() => document.documentElement.setAttribute("data-theme", "dark")|)
      c = colours.()
      assert c["color"] == to_rgb.(c["dark"])
      Page.evaluate!(page, ~s|() => document.documentElement.setAttribute("data-theme", "light")|)
      c = colours.()
      assert c["color"] == to_rgb.(c["light"])
    end

    test "fenced code in comments is sanitised, then highlighted in place", %{page: page} do
      add_comment_via_ui(page, "See:\n```go\nfunc main() {}\n```", wait_text: "See:")
      code = Page.locator(page, ".comment-card .comment-body pre > code")
      Expect.to_have_attribute!(code, "data-crit-code", "highlighted")

      Expect.to_be_visible!(
        Locator.first(Locator.locator(code, ~s(span[style*="--diffs-token"])))
      )
    end
  end
end
