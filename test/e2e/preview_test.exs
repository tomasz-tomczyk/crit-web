defmodule CritWeb.E2E.PreviewTest do
  use CritWeb.E2ECase, async: true

  # E2E coverage for hosted preview mode (CRI-78).
  #
  # The review surface for a `review_type: "preview"` review is rendered by the
  # PreviewMode hook (assets/js/preview-mode.js): an iframe loading the shared
  # static page from /r/:token/raw/<index.html>, a viewport toggle, a
  # navigate/pin mode toggle, and a persistent comment side panel with
  # DOM-anchored cards.
  #
  # Each test creates its own preview review via the API helper, so the suite is
  # self-contained and does not depend on the dev/test seed.
  #
  # Cross-frame note: the vendored agent (priv/static/preview-agent/*) is injected
  # into the iframe HTML by raw_controller and drives selection/pin behaviour from
  # *inside* the frame. The deterministic, host-side behaviours (load, card
  # render, viewport, resolve, reply, reload-persist) are asserted directly. The
  # in-iframe Pin-to-create flow depends on the agent booting + cross-frame
  # postMessage and is covered separately.

  # The spec's afterEach deletes the review the test stored in its module-level
  # `deleteToken`; here each test registers that delete when it creates the review.
  defp create_preview_review_for_test(request, opts \\ []) do
    review = create_preview_review(request, opts)
    on_exit(fn -> delete_review(request, review.delete_token) end)
    review
  end

  describe "Preview mode" do
    test "loads the shared page in an iframe with chrome and panel", %{
      page: page,
      request: request
    } do
      review = create_preview_review_for_test(request)
      token = review.token
      html_file = review.html_file

      frame = load_preview(page, token)

      # Host chrome is present.
      Expect.to_be_visible!(Page.locator(page, "#crit-preview-layout"))
      Expect.to_be_visible!(Page.locator(page, "#critPreviewViewport"))
      Expect.to_be_visible!(Page.locator(page, "#critPreviewMode"))

      Expect.to_have_text!(
        Page.locator(page, ~s(#critPreviewMode button[data-mode="navigate"])),
        "Browse"
      )

      Expect.to_contain_text!(
        Page.locator(page, ~s(#critPreviewMode button[data-mode="pin"])),
        "Comment"
      )

      Expect.to_have_attribute!(
        Page.locator(page, "#critPreviewModeHint"),
        "data-mode",
        "navigate"
      )

      Expect.to_have_text!(Page.locator(page, "#critPreviewModeHintState"), "Browsing")
      Expect.to_contain_text!(Page.locator(page, "#critPreviewModeHintText"), "Press")
      Expect.to_contain_text!(Page.locator(page, "#critPreviewModeHintText"), "Comment")

      # The iframe points at the raw HTML route for this review.
      src = Locator.get_attribute!(Page.locator(page, "#critPreviewIframe"), "src")
      assert src =~ "/r/#{token}/raw/#{html_file}"

      # The shared page's content (and its JS) render inside the frame.
      Expect.to_have_text!(FrameLocator.locator(frame, "#hero"), "Preview Demo Heading")
      Expect.to_have_text!(FrameLocator.locator(frame, "#counter"), "Clicked 0 times")
    end

    test "a nested entry path loads with its assets, title and pin file (#983)", %{
      page: page,
      request: request
    } do
      # A space in a segment proves the iframe URL is encoded per segment.
      entry = "artifacts/my reports/docs-minimize.html"

      review =
        create_preview_review_for_test(request, html_file: entry, cli_args: ["preview", entry])

      token = review.token

      frame = load_preview(page, token)

      # The iframe loads the entry from its original path: slashes intact, each
      # segment encoded.
      src = Locator.get_attribute!(Page.locator(page, "#critPreviewIframe"), "src")
      assert src =~ "/r/#{token}/raw/artifacts/my%20reports/docs-minimize.html"

      # Relative style.css / app.js resolve next to the entry: CSS applies and
      # the script runs.
      Expect.to_have_text!(FrameLocator.locator(frame, "#hero"), "Preview Demo Heading")
      Expect.to_have_css!(FrameLocator.locator(frame, "#counter"), "cursor", "pointer")
      Locator.click!(FrameLocator.locator(frame, "#counter"))
      Expect.to_have_text!(FrameLocator.locator(frame, "#counter"), "Clicked 1 times")

      # The review is titled by the original path, not index.html.
      Expect.to_have_title!(page, Regex.compile!(String.replace(entry, ".", "\\.")))

      # A new pin is stored against the entry path and grouped under it.
      pin_btn = Page.locator(page, ~s(#critPreviewMode button[data-mode="pin"]))
      Expect.to_be_enabled!(pin_btn, timeout: 15_000)
      Locator.click!(pin_btn)
      Locator.click!(FrameLocator.locator(frame, "#hero"))
      composer = Page.locator(page, ".crit-preview-composer-body")
      Expect.to_be_visible!(composer, timeout: 10_000)
      Locator.fill!(composer, "Pin on nested preview")
      Locator.click!(Page.locator(page, ".crit-preview-composer-save"))

      Expect.to_have_text!(
        Page.locator(page, "#critPreviewPanelBody .comments-panel-file-name"),
        "/" <> entry
      )

      Expect.to_pass!(
        fn ->
          res = APIRequestContext.get!(request, "/api/reviews/#{token}/comments")
          assert APIResponse.ok(res)
          comments = APIResponse.json!(res)
          assert length(comments) == 1
          assert hd(comments)["file_path"] == entry
        end,
        timeout: 10_000
      )
    end

    test "custom pin shortcut can be set and used from preview mode", %{
      page: page,
      request: request
    } do
      review = create_preview_review_for_test(request)
      token = review.token

      load_preview(page, token)
      pin = Page.locator(page, ~s(#critPreviewMode button[data-mode="pin"]))
      Expect.to_be_enabled!(pin, timeout: 10_000)
      keyboard = Page.keyboard(page)

      Locator.click!(pin)
      Keyboard.press!(keyboard, "Escape")
      Expect.not_to_have_class!(pin, ~r/crit-toggle-btn--active/)

      Locator.click!(Page.locator(page, "#settingsToggle"))
      Locator.click!(Page.locator(page, ~s(.settings-tab[data-tab="shortcuts"])))
      Locator.click!(Page.locator(page, ~s([data-shortcut-id="toggle_pin_mode"])))
      Keyboard.press!(keyboard, "x")
      Locator.click!(Page.locator(page, "#settingsOverlay"), position: %{x: 10, y: 10})

      Keyboard.press!(keyboard, "p")
      Expect.not_to_have_class!(pin, ~r/crit-toggle-btn--active/)
      Keyboard.press!(keyboard, "x")
      Expect.to_have_class!(pin, ~r/crit-toggle-btn--active/)
      Expect.to_have_text!(pin, "x · Comment")
      Expect.to_have_attribute!(Page.locator(page, "#critPreviewModeHint"), "data-mode", "pin")
      Expect.to_have_text!(Page.locator(page, "#critPreviewModeHintState"), "Commenting")

      frame = Page.frame_locator(page, "#critPreviewIframe")
      Keyboard.press!(keyboard, "x")
      Locator.click!(FrameLocator.locator(frame, "#hero"))
      Keyboard.press!(keyboard, "x")
      Expect.to_have_class!(pin, ~r/crit-toggle-btn--active/)

      Keyboard.press!(keyboard, "?")

      Expect.to_contain_text!(
        Page.locator(page, ~s([data-shortcut-id="toggle_pin_mode"])),
        "x"
      )

      Locator.click!(Page.locator(page, ".shortcut-reset-all"))
      Expect.to_have_text!(pin, "p · Comment")
    end

    test "existing dom-anchored comment shows as a card and matches the badge", %{
      page: page,
      request: request
    } do
      review =
        create_preview_review_for_test(request,
          comments: [
            %{
              body: "Tighten this heading copy",
              css_selector: "#hero",
              tag_chain: ["body", "main", "h1"]
            }
          ]
        )

      token = review.token

      load_preview(page, token)

      card =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Tighten this heading copy"
        )

      Expect.to_be_visible!(card, timeout: 10_000)

      # Badge counts dom-anchored comments.
      Expect.to_have_text!(Page.locator(page, "#commentsPanelCountBadge"), "1")
    end

    test "viewport toggle changes the iframe frame width", %{page: page, request: request} do
      review = create_preview_review_for_test(request)
      token = review.token

      load_preview(page, token)

      # Measure the frame's rendered width via offsetWidth — the hook sets the
      # frame's width as an inline style per viewport preset. (boundingBox() is
      # unreliable here because the desktop preset is wider than the browser
      # viewport.)
      frame_width = fn ->
        Page.evaluate!(page, """
        () =>
          document.querySelector("#critPreviewFrame")
            ?.offsetWidth ?? 0
        """)
      end

      # Default viewport is desktop (1280px wide).
      Expect.poll!(frame_width, &assert(&1 > 1000))

      Locator.click!(Page.locator(page, ~s(#critPreviewViewport button[data-viewport="mobile"])))

      # Mobile preset is 390px wide.
      Expect.poll!(frame_width, &assert(&1 < 500))
    end

    test "an open comment and a resolved comment render with the right state", %{
      page: page,
      request: request
    } do
      # Resolving from the panel is an authenticated action: Reviews can only be
      # resolved by the review owner or the comment author (see
      # Reviews.can_resolve_comment?/3). A comment created via the API is owned by
      # the "imported" identity, not the anonymous browser session, so the session
      # cannot resolve it — that path is exercised by the Pin flow (which creates a
      # session-owned comment) once the in-iframe agent is reachable; see the
      # fixme on "pin mode" below. Here we assert the deterministic half: the
      # panel renders open vs. resolved comments with the correct resolved-card
      # class, and resolve is gated off for this non-author session.
      review =
        create_preview_review_for_test(request,
          comments: [
            %{body: "Open comment here", css_selector: "#hero"},
            %{body: "Already resolved here", css_selector: "#counter", resolved: true}
          ]
        )

      token = review.token

      load_preview(page, token)

      open_card =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Open comment here"
        )

      Expect.to_be_visible!(open_card, timeout: 10_000)
      Expect.not_to_have_class!(open_card, ~r/resolved-card/)
      # These API-created comments are owned by "imported", not the anonymous
      # browser session, so resolve is gated off — assert the button is absent
      # (verifies ownership gating; the authorised path is the Pin flow below).
      Expect.to_have_count!(Locator.locator(open_card, ".resolve-btn"), 0)

      resolved_card =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card.resolved-card"),
          has_text: "Already resolved here"
        )

      Expect.to_be_visible!(resolved_card, timeout: 10_000)
      Expect.to_have_count!(Locator.locator(resolved_card, ".resolve-btn"), 0)
    end

    test "filter pills narrow the panel to open / resolved comments", %{
      page: page,
      request: request
    } do
      review =
        create_preview_review_for_test(request,
          comments: [
            %{body: "An open one", css_selector: "#hero"},
            %{body: "A resolved one", css_selector: "#counter", resolved: true}
          ]
        )

      token = review.token

      load_preview(page, token)

      pills = Page.locator(page, "#commentsFilterPill")
      Expect.to_be_visible!(pills, timeout: 10_000)
      Expect.to_have_text!(Locator.locator(pills, ~s([data-filter="all"] .filter-count)), "2")
      Expect.to_have_text!(Locator.locator(pills, ~s([data-filter="open"] .filter-count)), "1")

      Expect.to_have_text!(
        Locator.locator(pills, ~s([data-filter="resolved"] .filter-count)),
        "1"
      )

      cards = Page.locator(page, "#critPreviewPanelBody .comment-card")

      # Open filter → only the open comment shows.
      Locator.click!(Locator.locator(pills, ~s([data-filter="open"])))
      Expect.to_have_count!(cards, 1)
      Expect.to_be_visible!(Locator.filter(cards, has_text: "An open one"))

      # Resolved filter → only the resolved comment shows.
      Locator.click!(Locator.locator(pills, ~s([data-filter="resolved"])))
      Expect.to_have_count!(cards, 1)
      Expect.to_be_visible!(Locator.filter(cards, has_text: "A resolved one"))
    end

    test "reply from the panel adds a reply under the card", %{page: page, request: request} do
      review =
        create_preview_review_for_test(request,
          comments: [%{body: "Please revisit this section", css_selector: "#hero"}]
        )

      token = review.token

      load_preview(page, token)

      card =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Please revisit this section"
        )

      Expect.to_be_visible!(card, timeout: 10_000)

      # The shared reply composer is a collapsed input that expands to a textarea
      # on focus, then submits via the "Reply" button.
      Locator.click!(Locator.locator(card, ".reply-input"))
      reply_textarea = Locator.locator(card, ".reply-textarea")
      Expect.to_be_visible!(reply_textarea, timeout: 5_000)
      Locator.fill!(reply_textarea, "Agreed, will fix.")
      Locator.click!(Locator.locator(card, ".reply-form-buttons .btn-primary"))

      Expect.to_contain_text!(Locator.locator(card, ".reply-body"), "Agreed, will fix.",
        timeout: 10_000
      )
    end

    test "comment and resolution persist across a reload", %{page: page, request: request} do
      review =
        create_preview_review_for_test(request,
          comments: [%{body: "Persisted comment body", css_selector: "#hero", resolved: true}]
        )

      token = review.token

      load_preview(page, token)

      card =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Persisted comment body"
        )

      Expect.to_be_visible!(card, timeout: 10_000)
      Expect.to_have_class!(card, ~r/resolved-card/)

      Page.reload!(page)
      load_preview(page, token)

      after_reload =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Persisted comment body"
        )

      Expect.to_be_visible!(after_reload, timeout: 10_000)
      Expect.to_have_class!(after_reload, ~r/resolved-card/)
    end

    # End-to-end cross-frame create flow: the vendored agent (served from
    # /preview-agent/* via static_paths) boots inside the same-origin iframe,
    # posts agent-ready (enabling Pin), and on an in-frame click posts a selection
    # that opens the host composer; saving persists a DOM-anchored comment.
    test "pin mode: clicking an element in the iframe creates a comment", %{
      page: page,
      request: request
    } do
      review = create_preview_review_for_test(request)
      token = review.token

      frame = load_preview(page, token)

      # Wait for the agent to boot — Pin is disabled until agent-ready.
      pin_btn = Page.locator(page, ~s(#critPreviewMode button[data-mode="pin"]))
      Expect.to_be_enabled!(pin_btn, timeout: 15_000)
      # The shortcut is forwarded by the preview iframe, so it remains useful
      # after the reviewer has focused the page they are inspecting.
      Locator.press!(FrameLocator.locator(frame, "#hero"), "p")
      Expect.to_have_attribute!(pin_btn, "aria-pressed", "true")

      # Click a known element inside the iframe; the agent posts a selection
      # back to the host, which opens the composer in the panel.
      Locator.click!(FrameLocator.locator(frame, "#hero"))

      composer = Page.locator(page, ".crit-preview-composer-body")
      Expect.to_be_visible!(composer, timeout: 10_000)
      Locator.fill!(composer, "Created via pin mode")
      Locator.click!(Page.locator(page, ".crit-preview-composer-save"))

      card =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Created via pin mode"
        )

      Expect.to_be_visible!(card, timeout: 10_000)
      Expect.to_have_text!(Page.locator(page, "#commentsPanelCountBadge"), "1")
    end

    test "pin composer survives a disconnected submit and retries after reconnect", %{
      page: page,
      request: request
    } do
      test_pid = self()
      Page.on(page, :page_error, fn error -> send(test_pid, {:page_error, error}) end)

      review = create_preview_review_for_test(request)
      token = review.token

      frame = load_preview(page, token)
      pin_btn = Page.locator(page, ~s(#critPreviewMode button[data-mode="pin"]))
      Expect.to_be_enabled!(pin_btn, timeout: 15_000)
      Locator.click!(pin_btn)
      Locator.click!(FrameLocator.locator(frame, "#hero"))

      composer = Page.locator(page, ".crit-preview-composer-body")
      save = Page.locator(page, ".crit-preview-composer-save")
      Expect.to_be_visible!(composer, timeout: 10_000)
      Locator.fill!(composer, "Keep this pinned comment through a disconnect")

      Page.evaluate!(page, "() => window.liveSocket.disconnect()")

      Expect.to_have_attribute!(
        Page.locator(page, "#crit-preview-layout"),
        "data-connection-state",
        "disconnected"
      )

      Locator.click!(save)

      Expect.to_contain_text!(
        Page.locator(page, ".crit-preview-composer-error"),
        "couldn't confirm whether your change was saved",
        timeout: 12_000
      )

      Expect.to_have_value!(composer, "Keep this pinned comment through a disconnect")
      Expect.to_be_enabled!(save)
      refute_received {:page_error, _}

      Page.evaluate!(page, "() => window.liveSocket.connect()")

      Expect.to_have_attribute!(
        Page.locator(page, "#crit-preview-layout"),
        "data-connection-state",
        "connected",
        timeout: 12_000
      )

      Locator.click!(save)

      Expect.to_be_visible!(
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Keep this pinned comment through a disconnect"
        ),
        timeout: 10_000
      )

      refute_received {:page_error, _}
    end

    test "pin composer ignores repeated keyboard submits while acknowledgement is pending", %{
      page: page,
      request: request
    } do
      review = create_preview_review_for_test(request)
      token = review.token

      frame = load_preview(page, token)
      pin_btn = Page.locator(page, ~s(#critPreviewMode button[data-mode="pin"]))
      Expect.to_be_enabled!(pin_btn, timeout: 15_000)
      Locator.click!(pin_btn)
      Locator.click!(FrameLocator.locator(frame, "#hero"))

      composer = Page.locator(page, ".crit-preview-composer-body")
      Expect.to_be_visible!(composer, timeout: 10_000)
      Locator.fill!(composer, "Only create this pinned comment once")
      Page.evaluate!(page, "() => window.liveSocket.enableLatencySim(750)")

      Locator.press!(composer, "Control+Enter")
      Locator.click!(Page.locator(page, ~s(#critPreviewMode button[data-mode="navigate"])))
      Expect.to_have_attribute!(pin_btn, "aria-pressed", "true")
      Expect.to_be_visible!(composer)
      Locator.press!(composer, "Control+Enter")

      cards =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Only create this pinned comment once"
        )

      Expect.to_have_count!(cards, 1, timeout: 10_000)
      Page.evaluate!(page, "() => window.liveSocket.disableLatencySim()")
    end

    # Parity with crit #958 / PR #964: panel card click must ask the agent to
    # scroll the pinned element into view (keep-highlight with scroll: true),
    # not only outline it.
    test "clicking a pin card scrolls to and highlights its target element", %{
      page: page,
      request: request
    } do
      review =
        create_preview_review_for_test(request,
          comments: [
            %{
              body: "Scroll me to the counter button",
              css_selector: "#counter",
              tag_chain: ["BODY", "MAIN", "BUTTON"],
              outer_html: ~s(<button id="counter">Clicked 0 times</button>)
            }
          ]
        )

      token = review.token

      frame = load_preview(page, token)
      pin_btn = Page.locator(page, ~s(#critPreviewMode button[data-mode="pin"]))
      Expect.to_be_enabled!(pin_btn, timeout: 15_000)

      target = FrameLocator.locator(frame, "#counter")
      Expect.to_be_visible!(target)
      # Push the pin target below the fold so card activation must scroll.
      Locator.evaluate!(target, """
      (el) => {
        const spacer = document.createElement("div");
        spacer.id = "__crit_pin_card_scroll_spacer";
        spacer.style.height = "1600px";
        el.parentElement?.insertBefore(spacer, el);
        window.scrollTo(0, 0);
      }
      """)

      Expect.poll!(
        fn ->
          Locator.evaluate!(
            target,
            "(el) => el.getBoundingClientRect().top > window.innerHeight"
          )
        end,
        &assert(&1 == true)
      )

      card =
        Locator.filter(Page.locator(page, "#critPreviewPanelBody .comment-card"),
          has_text: "Scroll me to the counter button"
        )

      Expect.to_be_visible!(card, timeout: 10_000)
      Locator.click!(card)

      Expect.poll!(
        fn ->
          Locator.evaluate!(target, """
          (el) => {
            const rect = el.getBoundingClientRect();
            return (
              rect.top < window.innerHeight &&
              rect.bottom > 0 &&
              el.classList.contains("crit-live-pending-highlight")
            );
          }
          """)
        end,
        &assert(&1 == true)
      )
    end
  end
end
