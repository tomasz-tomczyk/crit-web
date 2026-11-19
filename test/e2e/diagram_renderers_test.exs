defmodule CritWeb.E2E.DiagramRenderersTest do
  use CritWeb.E2ECase, async: true

  alias Playwright.{Request, Route}

  # crit's pluggable renderers (vendored): ```mermaid fences and .mmd /
  # .mermaid files render as diagrams. Files get a Diagram / Source toggle and a
  # click on a node comments on the line that defines it.

  @mmd "flow.mmd"
  @flow Enum.join(
          [
            "flowchart TD",
            "  Start[Receive request] --> Auth{Authorized?}",
            "  Auth -->|yes| Handle[Handle request]",
            "  Auth -->|no| Reject[Reject]",
            ""
          ],
          "\n"
        )

  defp comments_of(request, token) do
    res = APIRequestContext.get!(request, "#{base_url()}/api/reviews/#{token}/comments")
    assert APIResponse.ok(res) == true
    APIResponse.json!(res)
  end

  # A file's <details> section in a multi-file review.
  defp section(page, path) do
    page
    |> Page.locator(".file-section")
    |> Locator.filter(has: Page.locator(page, ".file-header .filename", has_text: path))
  end

  # `page.on("request", ...)` pushing into an array: the listener sends each
  # matching URL to the test, which collects them here.
  defp record_requests(page, filter) do
    owner = self()
    ref = make_ref()

    Page.on(page, :request, fn req ->
      url = Request.url(req)
      if filter.(url), do: send(owner, {ref, url})
    end)

    ref
  end

  defp requested(ref) do
    receive do
      {^ref, url} -> [url | requested(ref)]
    after
      0 -> []
    end
  end

  defp mermaid_path?(url), do: URI.parse(url).path =~ ~r/mermaid/

  describe "Diagram renderers — .mmd files" do
    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{path: @mmd, content: @flow},
            %{path: "main.go", content: "package main\n\nfunc main() {}\n"}
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "opens as a diagram with a Diagram / Source toggle", %{page: page, token: token} do
      load_review(page, token)
      file = section(page, @mmd)

      target =
        Locator.locator(
          file,
          ~s(.crit-render[data-crit-renderer="mermaid"][data-crit-kind="file"])
        )

      Expect.to_have_attribute!(target, "data-crit-state", "rendered", timeout: 10_000)
      Expect.to_be_visible!(Locator.locator(target, ".crit-render-output svg"))
      Expect.to_be_hidden!(Locator.locator(target, ".crit-render-source"))

      toggle = Locator.locator(file, ".file-header .file-header-toggle")
      Expect.to_have_text!(Locator.get_by_role(toggle, :button), ["Diagram", "Source"])

      Expect.to_have_attribute!(
        Locator.locator(toggle, ~s([data-mode="rendered"])),
        "aria-pressed",
        "true"
      )
    end

    test "Source shows the file as code and Diagram switches back", %{page: page, token: token} do
      load_review(page, token)
      file = section(page, @mmd)
      toggle = Locator.locator(file, ".file-header-toggle")
      Locator.click!(Locator.locator(toggle, ~s([data-mode="source"])))
      Expect.to_contain_text!(code_line(page, @mmd, 1), "flowchart TD")
      Expect.to_have_count!(Locator.locator(file, ".crit-render"), 0)
      # The click switched views; it did not collapse the file.
      Expect.to_have_attribute!(file, "open", "")

      Locator.click!(Locator.locator(toggle, ~s([data-mode="rendered"])))
      Expect.to_be_visible!(Locator.locator(file, ".crit-render .crit-render-output svg"))
    end

    test "clicking a node opens a comment on the line that defines it", %{
      page: page,
      request: request,
      token: token
    } do
      load_review(page, token)
      file = section(page, @mmd)
      node = Locator.locator(file, ".crit-render-output g.node", has_text: "Authorized?")
      Expect.to_be_visible!(node, timeout: 10_000)
      Locator.click!(node)

      form = Locator.locator(file, ".comment-form")
      Expect.to_be_visible!(form)
      Locator.fill!(Locator.locator(form, "textarea"), "Which roles count as authorized?")
      Locator.press!(Locator.locator(form, "textarea"), "Control+Enter")

      Expect.to_contain_text!(
        Locator.locator(file, ".comment-card"),
        "Which roles count as authorized?"
      )

      Expect.poll!(
        fn ->
          Enum.map(comments_of(request, token), &"#{&1["start_line"]}-#{&1["end_line"]}")
        end,
        &assert(&1 == ["2-2"])
      )
    end

    test "a theme change re-renders the diagram in the new theme", %{page: page, token: token} do
      load_review(page, token)
      open_settings_pane(page)
      target = Locator.locator(section(page, @mmd), ".crit-render")
      Locator.click!(Page.locator(page, ~s([data-settings-theme="light"])))
      Expect.to_have_attribute!(target, "data-crit-theme", ~r/^light/, timeout: 10_000)
      Expect.to_have_attribute!(target, "data-crit-state", "rendered")

      target
      |> Locator.locator(".crit-render-output svg")
      |> Locator.evaluate!(~s[svg => svg.setAttribute("data-e2e-old", "")])

      Locator.click!(Page.locator(page, ~s([data-settings-theme="dark"])))
      Expect.to_have_attribute!(target, "data-crit-theme", ~r/^dark/)
      Expect.to_have_attribute!(target, "data-crit-state", "rendered")
      Expect.to_be_visible!(Locator.locator(target, ".crit-render-output svg"))
      Expect.to_have_count!(Locator.locator(target, ".crit-render-output svg[data-e2e-old]"), 0)
    end

    test "line comments show below the diagram", %{page: page, request: request, token: token} do
      seed_comment(request, token, file: @mmd, start_line: 4, body: "Return 403 here")
      load_review(page, token)
      file = section(page, @mmd)
      svg = Locator.locator(file, ".crit-render-output svg")
      card = Locator.locator(file, ".comment-card", has_text: "Return 403 here")
      Expect.to_be_visible!(svg, timeout: 10_000)
      Expect.to_be_visible!(card)

      Expect.poll!(
        fn ->
          s = Locator.bounding_box!(svg)
          c = Locator.bounding_box!(card)
          !!s and !!c and c.y >= s.y + s.height - 1
        end,
        &assert(&1 == true),
        message: "comment card sits below the diagram"
      )
    end
  end

  describe "Diagram renderers — quoted comments" do
    @seq "seq.mmd"
    # Sequence diagram labels are SVG <text>, not HTML in a foreignObject.
    @sequence Enum.join(
                [
                  "sequenceDiagram",
                  "  Client->>Server: Send request",
                  "  Server-->>Client: Reply",
                  ""
                ],
                "\n"
              )

    setup %{request: request} do
      review =
        create_review(request,
          files: [
            %{path: @mmd, content: @flow},
            %{path: @seq, content: @sequence}
          ],
          comments: [
            %{
              file: @mmd,
              start_line: 1,
              end_line: 4,
              body: "Name this step",
              quote: "Handle request"
            },
            %{file: @mmd, start_line: 1, end_line: 4, body: "Say why", quote: "no"},
            %{
              file: @seq,
              start_line: 1,
              end_line: 3,
              body: "Which request?",
              quote: "Send request"
            }
          ]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      %{token: review.token, delete_token: review.delete_token}
    end

    test "a quote of diagram text is highlighted in the drawn diagram, not the source", %{
      page: page,
      token: token
    } do
      load_review(page, token)
      file = section(page, @mmd)
      output = Locator.locator(file, ".crit-render-output")

      Expect.to_be_visible!(
        Locator.locator(output, "mark.quote-highlight", has_text: "Handle request"),
        timeout: 10_000
      )

      Expect.to_have_count!(Locator.locator(file, ".crit-render-source .quote-highlight"), 0)
      # "no" is also in the diagram's CSS; the highlight lands on the edge label.
      Expect.to_be_visible!(Locator.locator(output, "mark.quote-highlight", has_text: ~r/^no$/))
      Expect.to_have_count!(Locator.locator(output, "style .quote-highlight"), 0)

      # Back from Source, the diagram comes from the render cache: no doubled marks.
      toggle = Locator.locator(file, ".file-header-toggle")
      Locator.click!(Locator.locator(toggle, ~s([data-mode="source"])))
      Expect.to_have_count!(Locator.locator(file, ".crit-render"), 0)
      Locator.click!(Locator.locator(toggle, ~s([data-mode="rendered"])))

      Expect.to_be_visible!(
        Locator.locator(output, "mark.quote-highlight", has_text: "Handle request")
      )

      Expect.to_have_count!(Locator.locator(output, ".quote-highlight"), 2)
    end

    test "a quote of an SVG text label keeps the label drawn", %{page: page, token: token} do
      load_review(page, token)

      mark =
        page
        |> section(@seq)
        |> Locator.locator(".crit-render-output svg text tspan.quote-highlight",
          has_text: "Send request"
        )

      Expect.to_have_count!(mark, 1, timeout: 10_000)
      # An HTML <mark> in SVG <text> is not drawn: the label would have no width.
      width = Locator.evaluate!(mark, "el => el.getComputedTextLength()")
      assert width > 0
    end
  end

  describe "Diagram renderers — single file" do
    test "a single .mermaid file renders with the toggle above it", %{
      page: page,
      request: request
    } do
      %{token: token, delete_token: delete_token} =
        create_review(request, files: [%{path: "flow.mermaid", content: @flow}])

      try do
        load_review(page, token)
        toggle = Page.locator(page, ".crit-file-view-bar .file-header-toggle")

        Expect.to_have_attribute!(
          Locator.locator(toggle, ~s([data-mode="rendered"])),
          "aria-pressed",
          "true"
        )

        Expect.to_be_visible!(Page.locator(page, ".crit-render .crit-render-output svg"),
          timeout: 10_000
        )

        Locator.click!(Locator.locator(toggle, ~s([data-mode="source"])))
        Expect.to_contain_text!(code_line(page, "flow.mermaid", 2), "Authorized?")
        Expect.to_have_count!(Page.locator(page, ".crit-render"), 0)
      after
        delete_review(request, delete_token)
      end
    end
  end

  describe "Diagram renderers — fences" do
    test "an invalid diagram shows its source and the error", %{page: page, request: request} do
      %{token: token, delete_token: delete_token} =
        create_review(request,
          files: [
            %{
              path: "plan.md",
              content:
                "# Plan\n\n```mermaid\nflowchart TD\n  A --> \n  this is not mermaid ((\n```\n\nAfter the diagram\n"
            }
          ]
        )

      try do
        load_review(page, token)
        target = Page.locator(page, ".crit-render")
        Expect.to_have_attribute!(target, "data-crit-state", "error", timeout: 10_000)

        Expect.to_contain_text!(
          Locator.locator(target, ".crit-render-error"),
          "Could not render mermaid:"
        )

        Expect.to_contain_text!(
          Locator.locator(target, ".crit-render-source"),
          "this is not mermaid"
        )

        Expect.to_have_count!(Locator.locator(target, ".crit-render-expand"), 0)
        # mermaid draws nothing of its own: no error graphic or scratch node.
        Expect.to_have_count!(Page.locator(page, ~s(body > [id^="dcrit-mermaid-"])), 0)
        Expect.to_have_count!(Page.get_by_text(page, "Syntax error in text"), 0)
        # The rest of the document still renders.
        Expect.to_be_visible!(Page.locator(page, ".line-content", has_text: "After the diagram"))
      after
        delete_review(request, delete_token)
      end
    end

    test "the fence language is case-insensitive", %{page: page, request: request} do
      %{token: token, delete_token: delete_token} =
        create_review(request,
          files: [%{path: "plan.md", content: "# Plan\n\n```Mermaid\ngraph TD; A-->B;\n```\n"}]
        )

      ref = record_requests(page, &mermaid_path?/1)

      try do
        load_review(page, token)

        Expect.to_be_visible!(
          Page.locator(
            page,
            ~s(.crit-render[data-crit-renderer="mermaid"] .crit-render-output svg)
          ),
          timeout: 10_000
        )

        requested = requested(ref)
        # crit-web's own chunk, never crit's mermaid.min.js.
        assert Enum.any?(requested, &(&1 =~ ~r/\/mermaid\.core-[^\/]*\.js$/))
        assert Enum.filter(requested, &String.contains?(&1, "mermaid.min.js")) == []
      after
        delete_review(request, delete_token)
      end
    end

    test "a mermaid fence in a comment renders as a diagram", %{page: page, request: request} do
      %{token: token, delete_token: delete_token} =
        create_review(request, files: [%{path: "plan.md", content: "# Plan\n\nSome text\n"}])

      try do
        seed_comment(request, token,
          start_line: 3,
          body: "Like this:\n\n```mermaid\ngraph TD; X-->Y;\n```\n"
        )

        load_review(page, token)
        card = Locator.first(Page.locator(page, ".comment-card .comment-body"))

        Expect.to_be_visible!(
          Locator.locator(card, ~s(.crit-render[data-crit-kind="fence"] .crit-render-output svg)),
          timeout: 10_000
        )

        Expect.to_be_hidden!(Locator.locator(card, ".crit-render-source"))
      after
        delete_review(request, delete_token)
      end
    end

    test "a mermaid fence in a comment on a code file renders as a diagram", %{
      page: page,
      request: request
    } do
      %{token: token, delete_token: delete_token} =
        create_review(request,
          files: [%{path: "main.go", content: "package main\n\nfunc main() {}\n"}]
        )

      try do
        seed_comment(request, token,
          file: "main.go",
          start_line: 3,
          body: "Flow:\n\n```mermaid\ngraph TD; X-->Y;\n```\n"
        )

        load_review(page, token)
        card = Locator.first(Page.locator(page, ".crit-code-file .comment-card .comment-body"))

        Expect.to_be_visible!(
          Locator.locator(card, ~s(.crit-render[data-crit-kind="fence"] .crit-render-output svg)),
          timeout: 10_000
        )
      after
        delete_review(request, delete_token)
      end
    end
  end

  describe "Diagram renderers — loading" do
    test "a review without diagrams never requests mermaid", %{page: page, request: request} do
      %{token: token, delete_token: delete_token} =
        create_review(request,
          files: [
            %{path: "plan.md", content: "# Plan\n\n```go\nfunc main() {}\n```\n"},
            %{path: "main.go", content: "package main\n\nfunc main() {}\n"}
          ]
        )

      ref = record_requests(page, &mermaid_path?/1)

      try do
        seed_comment(request, token,
          file: "plan.md",
          start_line: 1,
          body: "Plain `code` and\n\n```js\nlet x = 1\n```\n"
        )

        load_review(page, token)
        Expect.to_be_visible!(Locator.first(Page.locator(page, ".comment-card")))
        Page.wait_for_load_state!(page, :networkidle)
        assert requested(ref) == []
      after
        delete_review(request, delete_token)
      end
    end

    test "a failed mermaid chunk shows the error, without requesting mermaid.min.js", %{
      page: page,
      request: request
    } do
      %{token: token, delete_token: delete_token} =
        create_review(request,
          files: [%{path: "plan.md", content: "# Plan\n\n```mermaid\ngraph TD; A-->B;\n```\n"}]
        )

      ref = record_requests(page, &String.contains?(&1, "mermaid.min.js"))
      Page.route!(page, ~r/\/mermaid\.core-[^\/]*\.js$/, &Route.abort!/1)

      try do
        load_review(page, token)
        target = Page.locator(page, ".crit-render")
        Expect.to_have_attribute!(target, "data-crit-state", "error", timeout: 10_000)

        Expect.to_contain_text!(
          Locator.locator(target, ".crit-render-error"),
          "Could not load mermaid"
        )

        Expect.to_contain_text!(Locator.locator(target, ".crit-render-source"), "graph TD")
        assert requested(ref) == []
      after
        delete_review(request, delete_token)
      end
    end
  end
end
