defmodule CritWeb.E2E.PierreLifecycleTest do
  use CritWeb.E2ECase, async: true

  alias Playwright.Route

  @files [%{path: "server.go", content: "package main\n\nfunc main() {}\n"}]

  for surface <- ["document", "code file"] do
    @tag surface: surface
    test "worker startup errors preserve #{surface} rendering and commenting", %{
      page: page,
      request: request,
      surface: surface
    } do
      review =
        create_review(request,
          files:
            if(surface == "document",
              do: [
                %{
                  path: "plan.md",
                  content: "# Plan\n\n```go\npackage main\nfunc main() {}\n```\n"
                }
              ],
              else: @files
            )
        )

      test_pid = self()

      Page.on(page, :page_error, fn error ->
        send(test_pid, {:page_error, Exception.message(error)})
      end)

      Page.route!(page, "**/pierre/pierre-worker.js", fn route ->
        Route.fulfill!(route,
          content_type: "application/javascript",
          body: "throw new Error('Simulated highlight worker startup failure')"
        )
      end)

      try do
        load_review(page, review.token)

        line =
          if surface == "document",
            do:
              page
              |> Page.locator(".line-block code.crit-code")
              |> Locator.filter(has_text: "package main"),
            else: code_line(page, "server.go", 1)

        Expect.to_be_visible!(line)

        Expect.poll!(
          fn ->
            Page.evaluate!(
              page,
              "() => window.PierreDiffs.getOrCreateWorkerPoolSingleton({}).getStats().totalWorkers"
            )
          end,
          &assert(&1 == 0)
        )

        add_comment_via_ui(page, "Comment after worker failure")
        wait_for_comment_card(page, "Comment after worker failure")
        refute_received {:page_error, _}
      after
        delete_review(request, review.delete_token)
      end
    end
  end

  test "comment deltas received while Pierre loads survive initialization", %{
    page: page,
    context: context,
    request: request
  } do
    review = create_review(request, files: @files)
    peer = BrowserContext.new_page!(context)
    test_pid = self()
    # JS keeps the handler pending on a promise the test resolves (`release()`);
    # here the handler process waits for a :release message from the test.
    release = fn ->
      receive do
        {:loading, handler} -> send(handler, :release)
      after
        0 -> :ok
      end
    end

    try do
      load_review(peer, review.token)

      # A handler blocked in `receive` stalls the whole connection (the peer page
      # too), unlike JS's `await blocked`: wait in a process of its own instead.
      Page.route!(page, "**/pierre/pierre-diffs.js", fn route ->
        spawn(fn ->
          send(test_pid, {:loading, self()})

          receive do
            :release -> :ok
          end

          Route.continue!(route)
        end)
      end)

      # The intercepted renderer script may delay the load event itself.
      Page.goto!(page, "/r/#{review.token}", wait_until: :domcontentloaded)
      assert_receive {:loading, handler}, 30_000
      add_comment_via_ui(peer, "Arrived during renderer startup")
      Expect.to_have_text!(Page.locator(page, "#commentCountNumber"), "1")
      send(handler, :release)
      Expect.to_be_visible!(code_line(page, "server.go", 1))
      wait_for_comment_card(page, "Arrived during renderer startup")
      Expect.to_have_text!(Page.locator(page, "#commentCountNumber"), "1")
    after
      release.()
      Page.close!(peer)
      delete_review(request, review.delete_token)
    end
  end

  test "another code comment preserves an inline edit draft, caret and focus", %{
    page: page,
    context: context,
    request: request
  } do
    review = create_review(request, files: @files)
    peer = BrowserContext.new_page!(context)

    try do
      load_review(page, review.token)
      add_comment_via_ui(page, "Earlier thread")
      add_comment_via_ui(page, "Original comment", line_index: 2)
      load_review(peer, review.token)

      page
      |> Page.locator(".comment-card")
      |> Locator.filter(has_text: "Original comment")
      |> Locator.locator(~s(button[title="Edit"]))
      |> Locator.click!()

      textarea = Page.locator(page, ".comment-form textarea")
      Locator.fill!(textarea, "Unsaved edit draft")
      Locator.evaluate!(textarea, "(el) => el.setSelectionRange(3, 7)")
      open_code_line_comment(peer, "server.go", 3)
      Locator.fill!(Page.locator(peer, ".comment-form textarea"), "Another thread")
      Locator.press!(Page.locator(peer, ".comment-form textarea"), "Control+Enter")
      wait_for_comment_card(page, "Another thread")
      Expect.to_have_value!(textarea, "Unsaved edit draft")
      Expect.to_be_focused!(textarea)
      assert Locator.evaluate!(textarea, "(el) => [el.selectionStart, el.selectionEnd]") == [3, 7]

      peer
      |> Page.locator(".comment-card")
      |> Locator.filter(has_text: "Earlier thread")
      |> Locator.locator(".delete-btn")
      |> Locator.click!()

      page
      |> Page.locator(".comment-card")
      |> Locator.filter(has_text: "Earlier thread")
      |> Expect.to_have_count!(0)

      Expect.to_have_value!(textarea, "Unsaved edit draft")
      Expect.to_be_focused!(textarea)
      assert Locator.evaluate!(textarea, "(el) => [el.selectionStart, el.selectionEnd]") == [3, 7]
      Locator.press!(textarea, "Control+Enter")
      wait_for_comment_card(peer, "Unsaved edit draft")
    after
      Page.close!(peer)
      delete_review(request, review.delete_token)
    end
  end

  test "cross-tab theme changes update Pierre alongside review chrome", %{
    page: page,
    context: context,
    request: request
  } do
    review = create_review(request, files: @files)
    peer = BrowserContext.new_page!(context)

    try do
      # JS passes a function; a string is run as a script, so pass its body.
      Page.add_init_script!(page, ~s|localStorage.setItem("phx:theme", "dark")|)
      load_review(page, review.token)
      pre = Locator.first(Page.locator(page, ".crit-code-file pre"))
      Expect.to_have_css!(pre, "background-color", "rgb(26, 27, 38)")
      Page.goto!(peer, "/themes")
      Page.evaluate!(peer, ~s|() => localStorage.setItem("phx:theme", "light")|)
      Expect.to_have_attribute!(Page.locator(page, "html"), "data-theme", "light")
      Expect.to_have_css!(pre, "background-color", "rgb(255, 255, 255)")
      Page.evaluate!(peer, ~s|() => localStorage.setItem("phx:theme", "dark")|)
      Expect.to_have_css!(pre, "background-color", "rgb(26, 27, 38)")
    after
      Page.close!(peer)
      delete_review(request, review.delete_token)
    end
  end
end
