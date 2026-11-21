defmodule CritWeb.E2E.Helpers do
  @moduledoc "Helpers of the browser suite (test/e2e)."

  import Playwright.Test.Assertions

  alias Playwright.{APIRequestContext, APIResponse, Expect, Locator, Mouse, Page}

  # 127.0.0.1, not "localhost": macOS resolves localhost to IPv6 ::1 first, but
  # the Phoenix/Bandit test server binds IPv4 only, so API calls to localhost get
  # ECONNREFUSED. 127.0.0.1 works on macOS and CI (Linux) alike.
  def base_url, do: "http://127.0.0.1:#{System.get_env("PORT", "4003")}"

  @axe_path Path.expand("../../../assets/node_modules/axe-core/axe.min.js", __DIR__)

  @doc """
  Evaluates axe-core in the page (the part of @axe-core/playwright's AxeBuilder
  the suite needs). `axe-core` is a devDependency of `assets/`. The review
  page's CSP forbids `Page.add_script_tag!/2`'s inline script, so the source is
  evaluated instead.
  """
  def inject_axe(page), do: Page.evaluate!(page, File.read!(@axe_path))

  @doc "Create a review via the API and return %{token, url, delete_token}."
  def create_review(request, opts \\ []) do
    files =
      opts[:files] ||
        [
          %{
            path: "example.md",
            content: "# Hello World\n\nThis is line 1\nThis is line 2\nThis is line 3\n"
          }
        ]

    body = %{files: files, review_round: opts[:review_round] || 0}
    body = if opts[:comments], do: Map.put(body, :comments, opts[:comments]), else: body

    res = APIRequestContext.post!(request, "#{base_url()}/api/reviews", data: body)
    assert APIResponse.status(res) == 201
    data = APIResponse.json!(res)
    [_, token] = String.split(data["url"], "/r/")
    %{token: token, url: data["url"], delete_token: data["delete_token"]}
  end

  # A small, self-contained preview page (HTML + CSS + JS) used by the preview
  # E2E spec. The HTML links style.css + app.js and exposes stable, easy-to-target
  # elements (a hero heading and a counter button) so the in-iframe Pin flow has
  # deterministic things to click. JS runs a trivial counter to prove scripts
  # execute inside the iframe.
  @preview_html """
  <!doctype html>
  <html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Preview Demo</title>
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <main class="card">
      <h1 id="hero">Preview Demo Heading</h1>
      <p class="tagline">A shared static preview.</p>
      <button id="counter" type="button">Clicked 0 times</button>
    </main>
    <script src="app.js"></script>
  </body>
  </html>
  """
  def preview_html, do: @preview_html

  @preview_css """
  body { font-family: system-ui, sans-serif; margin: 0; }
  .card { max-width: 480px; margin: 3rem auto; padding: 2rem; }
  h1 { font-size: 1.75rem; }
  button { padding: 0.5rem 1rem; cursor: pointer; }
  """
  def preview_css, do: @preview_css

  @preview_js """
  (function () {
    var n = 0;
    var btn = document.getElementById("counter");
    if (btn) {
      btn.addEventListener("click", function () {
        n += 1;
        btn.textContent = "Clicked " + n + " times";
      });
    }
  })();
  """
  def preview_js, do: @preview_js

  @doc """
  Create a *preview* review (review_type: "preview") via the API and return
  %{token, url, delete_token, html_file}.

  Comments are maps with `:body`, `:css_selector` and optional `:tag_chain`,
  `:outer_html`, `:resolved`, `:author_identity`.
  """
  def create_preview_review(request, opts \\ []) do
    html_file = opts[:html_file] || "index.html"
    # Assets live next to the entry HTML (crit keys them under its directory),
    # so the page's relative refs resolve for a nested entry path too.
    asset_dir =
      case :binary.matches(html_file, "/") do
        [] -> ""
        matches -> binary_part(html_file, 0, elem(List.last(matches), 0) + 1)
      end

    files = [
      %{path: html_file, content: opts[:html] || @preview_html, status: "modified"},
      %{path: asset_dir <> "style.css", content: opts[:css] || @preview_css, status: "modified"},
      %{path: asset_dir <> "app.js", content: opts[:js] || @preview_js, status: "modified"}
    ]

    comments =
      for c <- opts[:comments] || [] do
        %{
          start_line: 0,
          end_line: 0,
          body: c[:body],
          scope: "file",
          file_path: html_file,
          resolved: Map.get(c, :resolved, false),
          author_identity: c[:author_identity],
          dom_anchor: %{
            pathname: "/" <> html_file,
            css_selector: c[:css_selector],
            tag_chain: c[:tag_chain] || [],
            outer_html: c[:outer_html] || ""
          }
        }
      end

    body = %{review_type: "preview", review_round: 0, files: files}
    body = if comments != [], do: Map.put(body, :comments, comments), else: body
    body = if opts[:cli_args], do: Map.put(body, :cli_args, opts[:cli_args]), else: body

    res = APIRequestContext.post!(request, "#{base_url()}/api/reviews", data: body)
    assert APIResponse.status(res) == 201
    data = APIResponse.json!(res)
    [_, token] = String.split(data["url"], "/r/")
    %{token: token, url: data["url"], delete_token: data["delete_token"], html_file: html_file}
  end

  @doc """
  Navigate to a preview review and wait for the PreviewMode chrome + iframe.
  Returns a FrameLocator scoped to the preview iframe.
  """
  def load_preview(page, token) do
    Page.goto!(page, "/r/#{token}")
    Page.wait_for_selector!(page, "#crit-preview-layout #critPreviewIframe", timeout: 15_000)
    # Wait for the hook's init to point the iframe at the raw HTML route.
    Page.wait_for_function!(
      page,
      """
      () => {
        const f = document.querySelector("#critPreviewIframe");
        return !!f && /\\/raw\\//.test(f.src || "");
      }
      """,
      nil,
      timeout: 15_000
    )

    Page.frame_locator(page, "#critPreviewIframe")
  end

  @doc "Create a standard multi-file review used by multi-file and viewed specs."
  def create_multi_file_review(request) do
    paragraphs = fn label ->
      Enum.map_join(1..20, "\n\n", &"#{label} paragraph #{&1}.")
    end

    create_review(request,
      files: [
        %{path: "src/main.ts", content: paragraphs.("Main")},
        %{path: "src/utils.ts", content: paragraphs.("Utils")},
        %{path: "README.md", content: "# My Project\n\n#{paragraphs.("README")}"}
      ]
    )
  end

  @doc "Delete a review via the API."
  def delete_review(request, delete_token) do
    res =
      APIRequestContext.delete!(request, "#{base_url()}/api/reviews",
        data: %{delete_token: delete_token}
      )

    assert APIResponse.status(res) == 204
  end

  @doc "Add a comment to a review via the seed-comment test endpoint."
  def seed_comment(request, token, opts \\ []) do
    data = %{
      body: opts[:body] || "Test comment",
      start_line: opts[:start_line] || 1,
      end_line: opts[:end_line] || opts[:start_line] || 1,
      scope: opts[:scope] || "line"
    }

    data = if opts[:file], do: Map.put(data, :file, opts[:file]), else: data

    res =
      APIRequestContext.post!(request, "#{base_url()}/api/reviews/#{token}/seed-comment",
        data: data
      )

    assert APIResponse.status(res) == 200
    APIResponse.json!(res)
  end

  @doc """
  Navigate to a review page and wait for the document to render.

  For code files this also waits for Pierre to mount (diffs-container gets
  data-crit-path in onPostRender, which is when the range-tint stylesheet is
  adopted) and for Shiki tokens to land (async worker pool).
  """
  def load_review(page, token) do
    Page.goto!(page, "/r/#{token}")
    # Wait for the LiveView to connect and the document renderer to initialize:
    # a rendered markdown block, or a line of a code file (Pierre, shadow DOM —
    # Playwright's CSS engine pierces open shadow roots).
    Page.wait_for_selector!(
      page,
      "#document-renderer .line-block, #document-renderer .crit-code-file [data-line]",
      timeout: 15_000
    )

    # When code files are present, wait for Pierre's post-render mount + Shiki
    # highlighting so later assertions see a stable DOM.
    if Locator.count!(Page.locator(page, ".crit-code-file")) > 0 do
      Expect.poll!(
        fn -> Locator.count!(Page.locator(page, "diffs-container[data-crit-path]")) end,
        &assert(&1 > 0),
        timeout: 15_000
      )

      Expect.poll!(
        fn ->
          page
          |> Page.locator(~s(.crit-code-file [data-line] span[style*="--diffs-token"]))
          |> Locator.count!()
        end,
        &assert(&1 > 0),
        timeout: 15_000
      )
    end

    :ok
  end

  @doc "A code file's rendered view (Pierre File). Its lines live in a shadow root; locators pierce it."
  def code_file(page, path), do: Page.locator(page, ~s(.crit-code-file[data-file-path="#{path}"]))

  @doc "The content cell of line `n` of a code file."
  def code_line(page, path, n),
    do: Locator.locator(code_file(page, path), ~s([data-content] > [data-line="#{n}"]))

  @doc """
  Hover a code line so Pierre shows its gutter "+" (crit: hoverLine).

  Pierre replaces its line elements when highlighting lands or annotations
  change, which drops a hover that landed on the old element. Retry until the
  hover lands on the current element and the utility button is visible.
  """
  def hover_code_line(page, path, n, opts \\ []) do
    Expect.to_pass!(
      fn ->
        Locator.scroll_into_view_if_needed!(code_line(page, path, n), timeout: 2_000)
        Locator.hover!(code_line(page, path, n), timeout: 2_000)

        if Keyword.get(opts, :commentable) != false do
          Expect.to_be_visible!(Locator.locator(code_file(page, path), "[data-utility-button]"),
            timeout: 1_000
          )
        end
      end,
      timeout: 15_000
    )
  end

  @doc """
  Open a comment form on a code line through the gutter "+" (crit: openLineComment).

  Retries hover + click + form-visible as one unit.
  """
  def open_code_line_comment(page, path, n) do
    Expect.to_pass!(
      fn ->
        Locator.scroll_into_view_if_needed!(code_line(page, path, n), timeout: 2_000)
        Locator.hover!(code_line(page, path, n), timeout: 2_000)

        Expect.to_be_visible!(Locator.locator(code_file(page, path), "[data-utility-button]"),
          timeout: 2_000
        )

        Locator.click!(Locator.locator(code_file(page, path), "[data-utility-button]"),
          timeout: 2_000
        )

        Expect.to_be_visible!(Locator.last(Page.locator(page, ".comment-form textarea")),
          timeout: 2_000
        )
      end,
      timeout: 20_000
    )
  end

  @doc """
  Drag from the gutter "+" of `from_line` to the line-number cell `to_selector`
  to comment on a range (e.g. "Comment on Lines 9–11").

  The whole hover + boundingBox + mouse sequence runs inside one toPass retry.
  Early-exits when the expected form header is already visible so a retry after
  a successful drag does not open a second form.
  """
  def drag_code_range(page, path, from_line, to_selector, expected_header) do
    Expect.to_pass!(
      fn ->
        if Locator.count!(Page.locator(page, ".comment-form-header", has_text: expected_header)) >
             0 do
          Expect.to_have_text!(Page.locator(page, ".comment-form-header"), expected_header,
            timeout: 2_000
          )
        else
          Locator.scroll_into_view_if_needed!(code_line(page, path, from_line), timeout: 2_000)
          Locator.hover!(code_line(page, path, from_line), timeout: 2_000)
          utility = Locator.locator(code_file(page, path), "[data-utility-button]")
          Expect.to_be_visible!(utility, timeout: 2_000)
          to = Locator.locator(code_file(page, path), to_selector)
          Expect.to_be_visible!(to, timeout: 2_000)
          start = Locator.bounding_box!(utility)
          finish = Locator.bounding_box!(to)
          refute is_nil(start)
          refute is_nil(finish)
          mouse = Page.mouse(page)
          Mouse.move!(mouse, start.x + start.width / 2, start.y + start.height / 2)
          Mouse.down!(mouse)

          Mouse.move!(mouse, start.x + start.width / 2, finish.y + finish.height / 2, steps: 6)

          Mouse.up!(mouse)

          Expect.to_have_text!(Page.locator(page, ".comment-form-header"), expected_header,
            timeout: 5_000
          )
        end
      end,
      timeout: 20_000
    )
  end

  @doc "Line numbers of a code file that carry Pierre's line selection (keyboard focus)."
  def selected_code_lines(page, path) do
    Locator.evaluate!(code_file(page, path), """
    (el) => {
      const root = el.querySelector("diffs-container")?.shadowRoot;
      if (!root) return [];
      return Array.from(root.querySelectorAll("[data-content] > [data-line][data-selected-line]"))
        .map((line) => Number(line.dataset.line));
    }
    """)
  end

  @doc """
  Drag from one markdown gutter to another to comment on a range.

  Reads both bounding boxes inside a single toPass retry. Early-exits when a
  comment form is already open (retry after a successful drag).
  """
  def drag_gutter_range(page, from, to) do
    Expect.to_pass!(
      fn ->
        if Locator.count!(Page.locator(page, ".comment-form")) == 0 do
          Expect.to_be_visible!(from, timeout: 2_000)
          Expect.to_be_visible!(to, timeout: 2_000)
          Locator.scroll_into_view_if_needed!(from, timeout: 2_000)
          Locator.scroll_into_view_if_needed!(to, timeout: 2_000)
          start = Locator.bounding_box!(from)
          finish = Locator.bounding_box!(to)
          refute is_nil(start)
          refute is_nil(finish)
          mouse = Page.mouse(page)
          Mouse.move!(mouse, start.x + start.width / 2, start.y + start.height / 2)
          Mouse.down!(mouse)

          Mouse.move!(mouse, finish.x + finish.width / 2, finish.y + finish.height / 2, steps: 5)

          Mouse.up!(mouse)
          Expect.to_be_visible!(Page.locator(page, ".comment-form"), timeout: 5_000)
        end
      end,
      timeout: 15_000
    )
  end

  @doc "Wait for a comment card to appear in the document."
  def wait_for_comment_card(page, body_text \\ nil) do
    if body_text do
      Expect.to_be_visible!(
        Locator.filter(Page.locator(page, ".comment-card"), has_text: body_text),
        timeout: 10_000
      )
    else
      Expect.to_be_visible!(Locator.first(Page.locator(page, ".comment-card")), timeout: 10_000)
    end
  end

  @doc "Open the settings overlay via the header toggle and switch to a tab."
  def open_settings_pane(page, tab \\ "settings") do
    Locator.click!(Page.locator(page, "#settingsToggle"))
    Expect.to_be_visible!(Page.locator(page, "#settingsOverlay.active"), timeout: 5_000)
    Locator.click!(Page.locator(page, ~s(.settings-tab[data-tab="#{tab}"])))
  end

  @doc """
  Add a comment via the UI (click gutter, type, submit with Ctrl+Enter).

  `:wait_text` - text to wait for in the comment card, for bodies whose
  markdown transforms (e.g. `**bold**` renders as `<strong>`).
  """
  def add_comment_via_ui(page, body, opts \\ []) do
    # Markdown documents comment from the line gutter; a review of code files
    # only comments through Pierre's gutter "+" on line line_index + 1.
    gutters = Page.locator(page, ".line-gutter")

    if Locator.count!(gutters) > 0 do
      Locator.click!(Locator.nth(gutters, opts[:line_index] || 0))
    else
      path =
        Locator.get_attribute!(
          Locator.first(Page.locator(page, ".crit-code-file")),
          "data-file-path"
        )

      open_code_line_comment(page, path, (opts[:line_index] || 0) + 1)
    end

    textarea = Page.locator(page, ".comment-form textarea")
    Expect.to_be_visible!(textarea, timeout: 5_000)
    Locator.fill!(textarea, body)
    Locator.press!(textarea, "Control+Enter")

    wait_for_comment_card(page, opts[:wait_text] || body)
  end
end
