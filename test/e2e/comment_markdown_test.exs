defmodule CritWeb.E2E.CommentMarkdownTest do
  use CritWeb.E2ECase, async: true

  @table_md Enum.join(
              [
                "| Field | Type | Notes |",
                "| --- | --- | --- |",
                "| id | string | primary key |",
                "| name | string | display name |"
              ],
              "\n"
            )

  defp expect_all_table_cell_borders(table) do
    cells = Locator.locator(table, "th, td")
    cells |> Expect.not_() |> Expect.to_have_count!(0)

    for cell <- Locator.all!(cells), side <- ~w(top right bottom left) do
      Expect.to_have_css!(cell, "border-#{side}-style", "solid")
      Expect.to_have_css!(cell, "border-#{side}-width", "1px")
    end
  end

  describe "Comment Markdown Rendering" do
    setup %{request: request} do
      review = create_review(request)
      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "renders bold text as <strong>", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "This is **bold text** here", wait_text: "bold text")

      body = Page.locator(page, ".comment-card .comment-body")
      Expect.to_have_text!(Locator.locator(body, "strong"), "bold text")
    end

    test "renders inline code as <code>", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Use `inline code` here", wait_text: "inline code")

      body = Page.locator(page, ".comment-card .comment-body")
      Expect.to_have_text!(Locator.locator(body, "code"), "inline code")
    end

    test "renders links as <a> tags", %{page: page, token: token} do
      load_review(page, token)

      add_comment_via_ui(page, "See [the docs](https://example.com) for details",
        wait_text: "the docs"
      )

      body = Page.locator(page, ".comment-card .comment-body")
      link = Locator.locator(body, "a")
      Expect.to_have_text!(link, "the docs")
      Expect.to_have_attribute!(link, "href", "https://example.com")
    end

    test "auto-links bare URLs", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Visit https://example.com for more")

      body = Page.locator(page, ".comment-card .comment-body")
      link = Locator.locator(body, "a")
      Expect.to_be_visible!(link)
      Expect.to_have_attribute!(link, "href", "https://example.com")
    end

    test "keeps typographer replacements literal", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Choose (c), (r), or (tm)")

      Expect.to_have_text!(
        Page.locator(page, ".comment-card .comment-body"),
        "Choose (c), (r), or (tm)"
      )
    end

    test "renders safe HTML while stripping unsafe markup from comments", %{
      page: page,
      token: token
    } do
      load_review(page, token)

      add_comment_via_ui(
        page,
        ~s(<details open><summary>More context</summary>Safe content</details><!-- agent metadata --><img src="https://example.com/safe.png" srcset="javascript:alert(1\) 1x, https://example.com/safe.png 2x" onerror="window.__commentXss = true"><a href="javascript:alert(1\)">unsafe</a>),
        wait_text: "Safe content"
      )

      body = Page.locator(page, ".comment-card .comment-body")
      Expect.to_have_text!(Locator.locator(body, "details[open] > summary"), "More context")
      Expect.to_contain_text!(body, "Safe content")
      Expect.to_have_count!(Locator.locator(body, "script, [onerror], [onclick]"), 0)
      Expect.to_have_count!(Locator.locator(body, ~s(a[href^="javascript:"])), 0)
      Expect.to_have_count!(Locator.locator(body, ~s(img[srcset*="javascript:"])), 0)

      assert Locator.evaluate!(body, """
             (el) => {
               const walker = document.createTreeWalker(el, NodeFilter.SHOW_COMMENT);
               return walker.nextNode();
             }
             """) == :null
    end

    test "renders fenced code blocks with syntax highlighting", %{page: page, token: token} do
      load_review(page, token)

      add_comment_via_ui(page, ~s(Check this:\n```javascript\nconsole.log("hello"\)\n```),
        wait_text: "Check this"
      )

      body = Page.locator(page, ".comment-card .comment-body")
      code_block = Locator.locator(body, "pre code")
      Expect.to_be_visible!(code_block)

      # Rendered plain (sanitised), then highlighted in place with Shiki: token
      # spans carry the theme's --diffs-token-* colours (as in crit).
      Expect.to_have_class!(code_block, ~r/crit-code/)

      code_block
      |> Locator.locator(~s(span[style*="--diffs-token-dark"]))
      |> Locator.first()
      |> Expect.to_be_visible!()
    end

    test "draws a border on every cell of a markdown table in a comment", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      add_comment_via_ui(page, @table_md, wait_text: "primary key")

      table = Page.locator(page, ".comment-card .comment-body table")
      Expect.to_be_visible!(table)
      Expect.to_have_css!(table, "border-collapse", "collapse")
      Expect.to_have_count!(Locator.locator(table, "th"), 3)
      Expect.to_have_count!(Locator.locator(table, "tbody tr"), 2)

      expect_all_table_cell_borders(table)
    end

    test "draws a border on every cell of a markdown table in a reply", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      add_comment_via_ui(page, "Which fields does this cover?", wait_text: "Which fields")

      card =
        page
        |> Page.locator(".comment-card")
        |> Locator.filter(has_text: "Which fields does this cover?")

      Locator.click!(Locator.locator(card, ".reply-input"))
      reply_textarea = Locator.locator(card, ".reply-textarea")
      Expect.to_be_visible!(reply_textarea, timeout: 5_000)
      Locator.fill!(reply_textarea, @table_md)
      Locator.click!(Locator.locator(card, ".reply-form-buttons .btn-primary"))

      table = Locator.locator(card, ".reply-body table")
      Expect.to_be_visible!(table)
      Expect.to_have_count!(Locator.locator(table, "th"), 3)
      expect_all_table_cell_borders(table)
    end

    test "styles horizontal rules in comments", %{page: page, token: token} do
      load_review(page, token)
      add_comment_via_ui(page, "Above\n\n---\n\nBelow", wait_text: "Below")

      hr = Page.locator(page, ".comment-card .comment-body hr")
      Expect.to_have_count!(hr, 1)
      Expect.to_have_css!(hr, "height", "1px")
      Expect.to_have_css!(hr, "border-top-width", "0px")
    end
  end
end
