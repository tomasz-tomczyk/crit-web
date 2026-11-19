defmodule CritWeb.E2E.CodeFilesTest do
  use CritWeb.E2ECase, async: true

  alias Playwright.Promise

  # Code files render through Pierre's File (Shiki highlighting, line numbers,
  # hover "+", gutter range selection), as crit renders files-mode code files.
  # Comments and open forms are Pierre line annotations; tints and quote
  # highlights live in its shadow root.

  @go Enum.join(
        [
          "package main",
          "",
          ~s(import "net/http"),
          "",
          "// authMiddleware checks the API key.",
          "func authMiddleware(next http.Handler) http.Handler {",
          "\treturn http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {",
          ~s|\t\tif r.Header.Get("X-API-Key") == "" {|,
          ~s|\t\t\thttp.Error(w, "invalid key", http.StatusUnauthorized)|,
          "\t\t\treturn",
          "\t\t}",
          "\t\tnext.ServeHTTP(w, r)",
          "\t})",
          "}",
          ""
        ],
        "\n"
      )

  # expect(received).toBeCloseTo(expected, 1)
  defp assert_close_to(received, expected, digits) do
    assert abs(expected - received) < :math.pow(10, -digits) / 2
  end

  # Rows run in file order across documents and code files; step with j until
  # the keyboard focus reaches line 1 of `path`.
  defp focus_first_line_of(page, path) do
    Locator.click!(Page.locator(page, "body"), position: %{x: 5, y: 300})

    reached =
      Enum.find(1..40, fn _ ->
        Keyboard.press!(Page.keyboard(page), "j")
        selected_code_lines(page, path) == [1]
      end)

    if !reached, do: raise("keyboard focus never reached #{path}")
  end

  describe "Code files" do
    setup %{request: request, page: page} do
      review =
        create_review(request,
          files: [
            %{path: "server.go", content: @go},
            %{path: "notes.md", content: "# Notes\n\nSome prose.\n"},
            %{path: "LICENSE", content: "MIT License\n\nCopyright (c) 2026\n"}
          ],
          comments: [%{start_line: 6, end_line: 7, body: "Existing thread", file: "server.go"}]
        )

      on_exit(fn -> delete_review(request, review.delete_token) end)
      load_review(page, review.token)
      Expect.to_be_visible!(code_line(page, "server.go", 1))
      %{token: review.token, delete_token: review.delete_token}
    end

    test "renders code files with Shiki, line numbers and no line blocks", %{page: page} do
      file = code_file(page, "server.go")
      # 14 lines; Pierre shows the empty line after the trailing newline too.
      Expect.to_be_visible!(Locator.locator(file, ~s([data-column-number="14"])))
      Expect.to_have_count!(Locator.locator(file, ~s([data-column-number="16"])), 0)

      page
      |> code_line("server.go", 6)
      |> Locator.locator(~s(span[style*="--diffs-token-dark"]))
      |> Locator.first()
      |> Expect.to_be_visible!()

      Expect.to_have_count!(Locator.locator(file, ".line-block"), 0)
      # Files without a markdown extension are code, as in crit (LICENSE, .txt, ...).
      Expect.to_contain_text!(code_line(page, "LICENSE", 1), "MIT License")
      # Markdown still renders as a document.
      Expect.to_have_text!(
        Page.locator(page, ~s(.line-block[data-file-path="notes.md"] h1)),
        ~r/Notes/
      )
    end

    test "code files use the same centered reading width as markdown", %{page: page} do
      Page.set_viewport_size!(page, %{width: 1600, height: 1000})

      Expect.to_pass!(fn ->
        layout =
          Locator.evaluate!(Page.locator(page, "#document-renderer"), """
          root => {
            const rect = root.getBoundingClientRect();
            return {
              center: rect.x + rect.width / 2,
              width: rect.width,
              bodies: Array.from(root.querySelectorAll('.file-body')).map(body => {
                const box = body.getBoundingClientRect();
                return { center: box.x + box.width / 2, width: box.width };
              }),
            };
          }
          """)

        bodies = layout["bodies"]
        assert length(bodies) == 3

        for body <- bodies do
          assert_close_to(body["center"], layout["center"], 1)
          assert_close_to(body["width"], hd(bodies)["width"], 1)
          assert body["width"] < layout["width"]
        end
      end)
    end

    test "content width resizes every file and persists after reload", %{page: page, token: token} do
      Page.set_viewport_size!(page, %{width: 1900, height: 1000})
      Locator.click!(Page.locator(page, "#settingsToggle"))
      Expect.to_be_visible!(Page.locator(page, "#settingsOverlay.active"))

      expect_width = fn width ->
        Expect.to_pass!(fn ->
          layout =
            Locator.evaluate!(Page.locator(page, "#document-renderer"), """
            root => {
              const rect = root.getBoundingClientRect();
              return {
                center: rect.x + rect.width / 2,
                bodies: Array.from(root.querySelectorAll('.file-body')).map(body => {
                  const box = body.getBoundingClientRect();
                  return { center: box.x + box.width / 2, width: box.width };
                }),
              };
            }
            """)

          assert length(layout["bodies"]) == 3

          for body <- layout["bodies"] do
            assert_close_to(body["width"], width, 1)
            assert_close_to(body["center"], layout["center"], 1)
          end
        end)
      end

      for {choice, width} <- [{"compact", 840}, {"default", 1040}, {"wide", 1280}] do
        Locator.click!(Page.locator(page, ~s([data-settings-width="#{choice}"])))
        expect_width.(width)
      end

      load_review(page, token)
      Expect.to_be_visible!(code_line(page, "server.go", 1))
      expect_width.(1280)
    end

    test "file and inline cards share reading width across settings and viewports", %{
      page: page,
      request: request
    } do
      fixture =
        create_review(request,
          files: [
            %{path: "sample.go", content: "package main\nfunc main() {}\n"},
            %{path: "sample.md", content: "# Sample\n\nSome prose.\n"}
          ],
          comments: [
            %{scope: "file", file: "sample.go", body: "Code file thread"},
            %{start_line: 1, end_line: 1, file: "sample.go", body: "Code line thread"},
            %{scope: "file", file: "sample.md", body: "Markdown file thread"},
            %{start_line: 1, end_line: 1, file: "sample.md", body: "Markdown line thread"}
          ]
        )

      try do
        load_review(page, fixture.token)
        Expect.to_be_visible!(code_line(page, "sample.go", 1))

        for viewport <- [1900, 1000, 390] do
          Page.set_viewport_size!(page, %{width: viewport, height: 1000})
          Locator.click!(Page.locator(page, "#settingsToggle"))

          for choice <- ["compact", "default", "wide"] do
            Locator.click!(Page.locator(page, ~s([data-settings-width="#{choice}"])))

            Expect.to_pass!(fn ->
              boxes =
                Locator.evaluate_all!(
                  Page.locator(page, ".file-section .comment-card"),
                  """
                  cards =>
                    cards.map(card => ({ width: card.getBoundingClientRect().width, x: card.getBoundingClientRect().x }))
                  """
                )

              assert length(boxes) == 4
              [first | _] = boxes

              for box <- boxes do
                assert abs(box["width"] - first["width"]) < 2
                assert abs(box["x"] - first["x"]) < 2
                assert box["width"] > 200
              end

              assert Page.evaluate!(page, "() => document.documentElement.scrollWidth") <=
                       viewport
            end)
          end

          Keyboard.press!(Page.keyboard(page), "Escape")
        end

        card =
          page |> Page.locator(".comment-card") |> Locator.filter(has_text: "Code line thread")

        Locator.click!(Locator.locator(card, ".comment-collapse-btn"))
        Expect.to_have_class!(card, ~r/collapsed/)
        Locator.click!(Locator.locator(card, ".comment-collapse-btn"))
        Expect.not_to_have_class!(card, ~r/collapsed/)
        Page.set_viewport_size!(page, %{width: 1900, height: 1000})

        Expect.to_have_css!(
          Locator.first(Page.locator(page, ".file-section")),
          "border-top-left-radius",
          "6px"
        )

        Expect.to_have_css!(Page.locator(page, ".files-container"), "padding-left", "32px")

        Expect.to_have_css!(
          Locator.first(Page.locator(page, ".file-section")),
          "margin-bottom",
          "18px"
        )
      after
        delete_review(request, fixture.delete_token)
      end
    end

    test "existing threads sit under their end line with the range tinted", %{page: page} do
      file = code_file(page, "server.go")

      card =
        file |> Locator.locator(".comment-card") |> Locator.filter(has_text: "Existing thread")

      Expect.to_be_visible!(card)
      # The thread is below line 7 and above line 8.
      Expect.to_pass!(fn ->
        [line7, card_box, line8] =
          Promise.all([
            Promise.async(fn -> Locator.bounding_box!(code_line(page, "server.go", 7)) end),
            Promise.async(fn -> Locator.bounding_box!(card) end),
            Promise.async(fn -> Locator.bounding_box!(code_line(page, "server.go", 8)) end)
          ])
          |> Promise.await!()

        refute is_nil(line7)
        refute is_nil(card_box)
        refute is_nil(line8)
        assert card_box.y > line7.y
        assert card_box.y < line8.y
      end)

      # Range tints land with Pierre's post-render mount + adopted stylesheet,
      # which is async after the Shiki worker resolves. Poll so the assertion
      # waits for the tint instead of racing it (flaked in CI with "" vs tint).
      tint = fn n ->
        Promise.async(fn ->
          Locator.evaluate!(
            code_line(page, "server.go", n),
            "(el) => getComputedStyle(el).backgroundColor"
          )
        end)
      end

      Expect.to_pass!(
        fn ->
          [tinted6, plain3, tinted7] = Promise.await!(Promise.all([tint.(6), tint.(3), tint.(7)]))
          refute tinted6 == plain3
          assert tinted7 == tinted6
        end,
        timeout: 15_000
      )
    end

    test "the gutter + opens a form and a new comment appears live", %{page: page} do
      open_code_line_comment(page, "server.go", 9)
      Expect.to_have_text!(Page.locator(page, ".comment-form-header"), "Comment on Line 9")
      Locator.fill!(Page.locator(page, ".comment-form textarea"), "Use a constant for this")
      Locator.press!(Page.locator(page, ".comment-form textarea"), "Control+Enter")
      wait_for_comment_card(page, "Use a constant for this")

      page
      |> code_file("server.go")
      |> Locator.locator(".comment-card")
      |> Locator.filter(has_text: "Use a constant")
      |> Expect.to_be_visible!()

      Expect.to_have_count!(Page.locator(page, ".comment-form"), 0)
    end

    test "dragging across line numbers comments on the range", %{page: page} do
      # Hover + boxes + mouse must be atomic: Pierre re-renders between a
      # standalone hover and the drag null out the utility button (flaked in CI
      # with "element(s) not found" and boundingBox null).
      drag_code_range(
        page,
        "server.go",
        9,
        ~s([data-column-number="11"]),
        "Comment on Lines 9–11"
      )
    end

    test "an open form keeps its text when another form opens elsewhere", %{page: page} do
      open_code_line_comment(page, "server.go", 3)
      Locator.fill!(Page.locator(page, ".comment-form textarea"), "Draft on line 3")

      page
      |> Page.locator(~s(.line-block[data-file-path="notes.md"] .line-gutter))
      |> Locator.first()
      |> Locator.click!()

      Expect.to_have_count!(Page.locator(page, ".comment-form"), 2)

      Expect.to_have_value!(
        Locator.locator(code_file(page, "server.go"), ".comment-form textarea"),
        "Draft on line 3"
      )
    end

    test "j/k move through code lines and c comments on the focused line", %{page: page} do
      focus_first_line_of(page, "server.go")
      Keyboard.press!(Page.keyboard(page), "j")
      Keyboard.press!(Page.keyboard(page), "j")
      Expect.poll!(fn -> selected_code_lines(page, "server.go") end, &assert(&1 == [3]))
      Keyboard.press!(Page.keyboard(page), "k")
      Expect.poll!(fn -> selected_code_lines(page, "server.go") end, &assert(&1 == [2]))
      Keyboard.press!(Page.keyboard(page), "c")
      Expect.to_have_text!(Page.locator(page, ".comment-form-header"), "Comment on Line 2")
    end

    test "visual mode selects a range of code lines for one comment", %{page: page} do
      focus_first_line_of(page, "server.go")
      for _ <- 1..3, do: Keyboard.press!(Page.keyboard(page), "j")
      Keyboard.press!(Page.keyboard(page), "Shift+V")
      Keyboard.press!(Page.keyboard(page), "j")
      Keyboard.press!(Page.keyboard(page), "j")
      Expect.poll!(fn -> selected_code_lines(page, "server.go") end, &assert(&1 == [4, 5, 6]))
      Keyboard.press!(Page.keyboard(page), "c")
      Expect.to_have_text!(Page.locator(page, ".comment-form-header"), "Comment on Lines 4–6")
    end

    test "selecting text in code comments on its lines with a quote", %{page: page} do
      # Select + "c" must be atomic: a Pierre re-render between setting the
      # selection and pressing "c" clears it, losing the quote (flaked in CI).
      Expect.to_pass!(
        fn ->
          Locator.scroll_into_view_if_needed!(code_line(page, "server.go", 9), timeout: 2_000)

          Page.evaluate!(page, """
          () => {
            const host = document.querySelector('.crit-code-file[data-file-path="server.go"] diffs-container');
            const line = host.shadowRoot.querySelector('[data-content] > [data-line="9"]');
            const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
            let node;
            while ((node = walker.nextNode())) {
              const at = node.textContent.indexOf("invalid key");
              if (at < 0) continue;
              const range = document.createRange();
              range.setStart(node, at);
              range.setEnd(node, at + "invalid key".length);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              return;
            }
            throw new Error("text not found");
          }
          """)

          Keyboard.press!(Page.keyboard(page), "c")

          Expect.to_have_text!(Page.locator(page, ".comment-form-header"), "Comment on Line 9",
            timeout: 2_000
          )
        end,
        timeout: 15_000
      )

      Locator.fill!(Page.locator(page, ".comment-form textarea"), "Quoted")
      Locator.press!(Page.locator(page, ".comment-form textarea"), "Control+Enter")
      wait_for_comment_card(page, "Quoted")
      # The quote is highlighted inside Pierre's shadow root (CSS Custom Highlight API).
      Expect.poll!(
        fn ->
          Page.evaluate!(page, """
          () => {
            const ranges = [...(CSS.highlights.get("crit-quote") || [])];
            return ranges.map((r) => r.toString());
          }
          """)
        end,
        &assert("invalid key" in &1)
      )
    end

    test "hide resolved removes resolved threads from code files", %{page: page} do
      # Resolve a thread this visitor wrote (seeded threads belong to nobody here).
      open_code_line_comment(page, "server.go", 10)
      Locator.fill!(Page.locator(page, ".comment-form textarea"), "Mine to resolve")
      Locator.press!(Page.locator(page, ".comment-form textarea"), "Control+Enter")
      wait_for_comment_card(page, "Mine to resolve")

      card =
        page
        |> code_file("server.go")
        |> Locator.locator(".comment-card")
        |> Locator.filter(has_text: "Mine to resolve")

      Locator.click!(Locator.locator(card, ".resolve-btn"))
      Expect.to_be_visible!(Locator.locator(code_file(page, "server.go"), ".resolved-card"))
      Locator.click!(Page.locator(page, "#settingsToggle"))
      Locator.check!(Page.locator(page, "#hideResolvedToggle"))
      Keyboard.press!(Page.keyboard(page), "Escape")

      page
      |> code_file("server.go")
      |> Locator.locator(".comment-card")
      |> Locator.filter(has_text: "Mine to resolve")
      |> Expect.to_have_count!(0)

      page
      |> code_file("server.go")
      |> Locator.locator(".comment-card")
      |> Locator.filter(has_text: "Existing thread")
      |> Expect.to_be_visible!()
    end
  end

  describe "Code files — edge cases" do
    test "a comment past the end of the file is listed as outdated", %{
      page: page,
      request: request
    } do
      review =
        create_review(request,
          files: [%{path: "a.go", content: "package a\n"}, %{path: "b.md", content: "# B\n"}],
          comments: [%{start_line: 40, end_line: 40, body: "Line gone", file: "a.go"}]
        )

      try do
        load_review(page, review.token)
        outdated = Page.locator(page, ".file-section .file-comments .outdated-comment")
        Expect.to_contain_text!(outdated, "Line gone")
        Expect.to_have_text!(Locator.locator(outdated, ".outdated-badge"), "Outdated")
      after
        delete_review(request, review.delete_token)
      end
    end

    test "a single-file code review renders through Pierre", %{page: page, request: request} do
      review =
        create_review(request,
          files: [%{path: "app.ex", content: "defmodule App do\n  def hi, do: :ok\nend\n"}],
          comments: [%{start_line: 2, end_line: 2, body: "Single file thread", file: "app.ex"}]
        )

      try do
        load_review(page, review.token)

        page
        |> code_line("app.ex", 2)
        |> Locator.locator(~s(span[style*="--diffs-token"]))
        |> Locator.first()
        |> Expect.to_be_visible!()

        Expect.to_contain_text!(
          Locator.locator(code_file(page, "app.ex"), ".comment-card"),
          "Single file thread"
        )

        open_code_line_comment(page, "app.ex", 3)
        Expect.to_have_text!(Page.locator(page, ".comment-form-header"), "Comment on Line 3")
      after
        delete_review(request, review.delete_token)
      end
    end

    test "reviews closed to anonymous comments show no gutter + on code", %{
      browser: browser,
      request: request
    } do
      seeded =
        APIRequestContext.post!(request, "#{base_url()}/api/test/seed-user",
          data: %{name: "Code Owner"}
        )

      %{"token" => bearer} = APIResponse.json!(seeded)
      files = [%{path: "a.go", content: "package a\n\nfunc A() {}\n"}]

      created =
        APIRequestContext.post!(request, "#{base_url()}/api/reviews",
          headers: %{"Authorization" => "Bearer #{bearer}"},
          data: %{files: files, comments: []}
        )

      %{"url" => url, "delete_token" => delete_token} = APIResponse.json!(created)
      [_, token] = String.split(url, "/r/")

      updated =
        APIRequestContext.put!(request, "#{base_url()}/api/reviews/#{token}",
          headers: %{"Authorization" => "Bearer #{bearer}"},
          data: %{
            delete_token: delete_token,
            files: files,
            comments: [],
            review_round: 1,
            comment_policy: "logged_in_only"
          }
        )

      assert APIResponse.status(updated) == 200
      ctx = Browser.new_context!(browser)
      page = BrowserContext.new_page!(ctx)

      try do
        load_review(page, token)
        hover_code_line(page, "a.go", 3, commentable: false)
        Expect.to_be_visible!(code_line(page, "a.go", 3))

        Expect.to_have_count!(
          Locator.locator(code_file(page, "a.go"), "[data-utility-button]"),
          0
        )
      after
        BrowserContext.close!(ctx)
        delete_review(request, delete_token)
      end
    end
  end
end
