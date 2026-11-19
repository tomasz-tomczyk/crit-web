defmodule CritWeb.E2E.SecurityPayloads do
  @moduledoc """
  Adversarial payload library for the security/isolation E2E suite (port of
  e2e/security/payloads.ts).

  Every payload posts a `CRIT_SEC_PROBE` message to `parent`. The spec uses
  `Page.add_init_script!/2` to capture these probes before the iframe navigates.
  They assert the *security property* ("authenticated canonical content is not
  readable from user-authored JS inside a preview iframe"), independent of how
  the fix achieves it.
  """

  # Deterministic marker present in /dashboard's HTML for an authenticated user
  # ("Hi <name>, where to today?"). The unauth path redirects via LiveView and
  # does NOT render this string in the initial HTTP response body.
  @authed_dashboard_marker "where to today?"
  def authed_dashboard_marker, do: @authed_dashboard_marker

  @doc """
  Attempt to "ride" the viewer's session cookies against /dashboard from inside
  the preview iframe, with a *relative* URL that resolves against the iframe's
  document origin. With origin isolation, it hits HostGate's 404 on the preview
  host.
  """
  def preview_session_ride_payload do
    marker = @authed_dashboard_marker

    """
    <script>
    (async () => {
      const probe = (status, hasAuth, msg) =>
        parent.postMessage({
          type: "CRIT_SEC_PROBE",
          variant: "session-ride-via-dash-route",
          status,
          hasAuth,
          msg,
        }, "*");
      try {
        const res = await fetch("/dashboard", {
          credentials: "include",
          redirect: "manual",
        });
        const text = await res.text();
        probe(res.status, text.includes(#{Jason.encode!(marker)}), text.slice(0, 160));
      } catch (e) {
        probe("BLOCKED", false, String(e));
      }
    })();
    </script>\
    """
  end

  @doc """
  Sanity payload: reports both of the iframe's notions of "origin" back to the
  parent: `msg` is `location.origin` (from the URL), `documentOrigin` is
  `window.origin` ("null" exactly when the sandbox withholds allow-same-origin).
  """
  def preview_origin_beacon_payload do
    """
    <script>
    parent.postMessage({
      type: "CRIT_SEC_PROBE",
      variant: "iframe-origin-beacon",
      msg: location.origin,
      documentOrigin: String(window.origin),
    }, "*");
    </script>\
    """
  end
end

defmodule CritWeb.E2E.SecurityTest do
  @moduledoc """
  Security/isolation E2E suite (port of e2e/security.spec.ts).

  Runs against a VM whose endpoint boots with origin isolation, as
  playwright.config.ts's second webServer: `E2E=true PHX_SERVER=true PORT=4004
  PHX_HOST=127.0.0.1.nip.io PREVIEW_HOST=preview.127.0.0.1.nip.io mix test
  test/e2e/security_test.exs`. nip.io resolves both names to 127.0.0.1, so they
  share the loopback but the browser treats them as separate origins.

  Property asserted: logged-in victim's session cookies on the canonical host
  must not be readable, not even addressable, by JS the victim did not author,
  running inside a preview iframe the victim opens.
  """
  use CritWeb.E2ECase, async: true, tag: :security

  alias CritWeb.E2E.SecurityPayloads

  # nip.io wildcards to 127.0.0.1. Both values must match the server's
  # PHX_HOST/PREVIEW_HOST/PORT so the app side and the spec side agree on what
  # "isolated" means.
  @port "4004"
  @canonical_host "127.0.0.1.nip.io"
  @preview_host "preview.127.0.0.1.nip.io"
  @canonical_origin "http://#{@canonical_host}:#{@port}"
  @preview_origin "http://#{@preview_host}:#{@port}"

  # Install a window.postMessage listener that buffers CRIT_SEC_PROBE messages
  # from any child iframe. MUST be called before any iframe that emits a probe
  # navigates, i.e. before Page.goto to the review route.
  defp install_probe_listener(page) do
    Page.add_init_script!(page, """
    (() => {
      window.__critSecProbes = [];
      window.addEventListener("message", (event) => {
        if (
          typeof event.data === "object" &&
          event.data !== null &&
          event.data.type === "CRIT_SEC_PROBE"
        ) {
          window.__critSecProbes.push(event.data);
        }
      });
    })()
    """)
  end

  defp wait_for_probe(page, variant, timeout_ms \\ 10_000) do
    Page.wait_for_function!(
      page,
      """
      (wanted) => {
        const probes = window.__critSecProbes;
        return (probes ?? []).some((p) => p.variant === wanted);
      }
      """,
      variant,
      timeout: timeout_ms,
      polling: 100
    )

    found =
      Page.evaluate!(
        page,
        """
        (wanted) => {
          const probes = window.__critSecProbes;
          return (probes ?? []).find((p) => p.variant === wanted) ?? null;
        }
        """,
        variant
      )

    if found == :null do
      raise "no CRIT_SEC_PROBE with variant \"#{variant}\" within #{timeout_ms}ms"
    end

    found
  end

  describe "Preview isolation: preview iframe cannot exfiltrate victim session" do
    test "isolated preview agent enables pin mode and sends selections", %{
      page: page,
      request: request
    } do
      files = [
        %{
          path: "index.html",
          content:
            ~s(<!doctype html><html><body><p id="existing">Existing marker target</p><h1 id="hero">Pin me</h1></body></html>),
          status: "modified"
        }
      ]

      res =
        APIRequestContext.post!(request, "#{@canonical_origin}/api/reviews",
          data: %{review_type: "preview", review_round: 0, files: files}
        )

      assert APIResponse.status(res) == 201, "preview review creation"
      body = APIResponse.json!(res)
      [_, token] = String.split(body["url"], "/r/")
      delete_token = body["delete_token"]

      # The stored anchor pathname is the iframe's actual raw route, which is
      # only known after the API allocates the review token.
      update_res =
        APIRequestContext.put!(request, "#{@canonical_origin}/api/reviews/#{token}",
          data: %{
            delete_token: delete_token,
            review_round: 0,
            files: files,
            comments: [
              %{
                start_line: 0,
                end_line: 0,
                body: "Existing pin",
                scope: "file",
                file_path: "index.html",
                dom_anchor: %{
                  pathname: "/r/#{token}/raw/index.html",
                  css_selector: "#existing",
                  tag_chain: ["body", "p"],
                  outer_html: ~s(<p id="existing">Existing marker target</p>)
                }
              }
            ]
          }
        )

      assert APIResponse.status(update_res) == 200, "preview review marker seed"

      try do
        Page.goto!(page, "#{@canonical_origin}/r/#{token}")
        Page.wait_for_selector!(page, "#critPreviewIframe", timeout: 15_000)

        iframe_src = Locator.get_attribute!(Page.locator(page, "#critPreviewIframe"), "src")
        assert iframe_src == "#{@preview_origin}/r/#{token}/raw/index.html"

        # agent-ready crosses preview → canonical and enables Pin. Switching
        # mode crosses canonical → preview; the click selection then crosses
        # back and opens the host-side composer.
        pin_button = Page.locator(page, ~s(#critPreviewMode button[data-mode="pin"]))
        Expect.to_be_enabled!(pin_button, timeout: 15_000)

        # The agent prefers marker CSS on the iframe document host (preview),
        # with API-origin fallback. Confirm styled markers via preview-host CORS.
        marker =
          page
          |> Page.frame_locator("#critPreviewIframe")
          |> FrameLocator.locator(".crit-live-marker")

        Expect.to_be_visible!(marker, timeout: 10_000)
        Expect.to_have_css!(marker, "width", "22px")
        Expect.to_have_css!(marker, "background-color", "rgb(37, 99, 235)")

        Locator.click!(Page.locator(page, "#settingsToggle"))
        Locator.click!(Page.locator(page, ~s(.settings-tab[data-tab="shortcuts"])))
        Locator.click!(Page.locator(page, ~s([data-shortcut-id="toggle_pin_mode"])))
        Keyboard.press!(Page.keyboard(page), "x")
        Locator.click!(Page.locator(page, "#settingsOverlay"), position: %{x: 10, y: 10})

        preview_frame = Page.frame_locator(page, "#critPreviewIframe")
        Locator.click!(FrameLocator.locator(preview_frame, "#hero"))
        Keyboard.press!(Page.keyboard(page), "x")
        Expect.to_have_attribute!(pin_button, "aria-pressed", "true")

        Locator.click!(FrameLocator.locator(preview_frame, "#hero"))

        Expect.to_be_visible!(Page.locator(page, ".crit-preview-composer-body"),
          timeout: 10_000
        )
      after
        APIRequestContext.delete!(request, "#{@canonical_origin}/api/reviews",
          data: %{delete_token: delete_token}
        )
      end
    end

    test "raw preview route 308-redirects from canonical to preview host", %{request: request} do
      # Smoke check that isolation is actually configured for this spec. If
      # this fails, the server's PHX_HOST/PREVIEW_HOST are missing or env vars
      # drifted: fix the harness, not the spec.
      res =
        APIRequestContext.post!(request, "#{@canonical_origin}/api/reviews",
          data: %{
            review_type: "preview",
            review_round: 0,
            files: [
              %{
                path: "index.html",
                content: "<!doctype html><title>innocent</title>",
                status: "modified"
              }
            ]
          }
        )

      assert APIResponse.status(res) == 201, "preview review creation"
      body = APIResponse.json!(res)
      [_, token] = String.split(body["url"], "/r/")
      delete_token = body["delete_token"]

      try do
        # Hit the raw route on the canonical host. With isolation enabled the
        # server issues a 308 redirect to the preview host. Without isolation
        # it just serves the file (status 200), exactly the #291 vuln.
        # Manual redirect handling avoids Playwright following it.
        raw_res =
          APIRequestContext.get!(request, "#{@canonical_origin}/r/#{token}/raw/index.html",
            max_redirects: 0
          )

        assert APIResponse.status(raw_res) == 308, "canonical-host raw status"
        location = APIResponse.headers(raw_res)["location"] || ""

        assert String.starts_with?(location, "#{@preview_origin}/r/#{token}/raw/index.html"),
               "redirect location: #{location}"
      after
        APIRequestContext.delete!(request, "#{@canonical_origin}/api/reviews",
          data: %{delete_token: delete_token}
        )
      end
    end

    test "preview-host /dashboard is 404 (HostGate)", %{request: request} do
      # HostGate confines the preview host to a narrow route surface. The
      # dashboard (and any authed-only LiveView) must not be reachable there.
      res = APIRequestContext.get!(request, "#{@preview_origin}/dashboard", max_redirects: 0)
      assert APIResponse.status(res) == 404
    end

    test "logged-in victim's session is not exfiltrated by preview review JS", %{
      page: page,
      request: request
    } do
      # --- Setup: seed a victim user and login them on the canonical host. ---
      rand = fn ->
        6 |> :crypto.strong_rand_bytes() |> Base.encode32(case: :lower) |> binary_part(0, 6)
      end

      email = "victim-#{System.system_time(:millisecond)}-#{rand.()}@crit-security-test.example"
      name = "Victim-#{rand.()}"

      seed_res =
        APIRequestContext.post!(request, "#{@canonical_origin}/api/test/seed-user",
          data: %{name: name, email: email}
        )

      assert APIResponse.status(seed_res) == 200, "seed-user"
      seed = APIResponse.json!(seed_res)
      user_id = seed["user_id"]

      # Log in the victim on the canonical host via the test-only GET endpoint.
      # Sets the _crit_web_session cookie scoped to 127.0.0.1.nip.io.
      Page.goto!(page, "#{@canonical_origin}/test/login-as/#{user_id}")

      Expect.poll!(
        fn -> Page.text_content!(page, "body") || "" end,
        &assert(&1 =~ ~s("ok":true))
      )

      # Sanity: confirm the victim is authenticated against /dashboard before
      # we load the attacker payload. If this fails, login-as is broken, not
      # the security boundary.
      Page.goto!(page, "#{@canonical_origin}/dashboard")

      Expect.to_contain_text!(
        Page.locator(page, "body"),
        SecurityPayloads.authed_dashboard_marker(),
        timeout: 10_000
      )

      # --- Build the attacker preview review. ---
      attacker_html =
        "<!doctype html><html><body>" <>
          "<h1>innocent-looking preview</h1>" <>
          SecurityPayloads.preview_origin_beacon_payload() <>
          SecurityPayloads.preview_session_ride_payload() <>
          "</body></html>"

      review_res =
        APIRequestContext.post!(request, "#{@canonical_origin}/api/reviews",
          data: %{
            review_type: "preview",
            review_round: 0,
            files: [%{path: "index.html", content: attacker_html, status: "modified"}]
          }
        )

      assert APIResponse.status(review_res) == 201, "attacker review creation"
      review_json = APIResponse.json!(review_res)
      [_, token] = String.split(review_json["url"], "/r/")
      delete_token = review_json["delete_token"]

      try do
        # Install the probe listener BEFORE we navigate so we don't miss the
        # first postMessage the iframe emits.
        install_probe_listener(page)

        # Victim loads the shared preview review on the canonical host.
        Page.goto!(page, "#{@canonical_origin}/r/#{token}")
        Page.wait_for_selector!(page, "#critPreviewIframe", timeout: 15_000)

        # The iframe must point at the preview origin: that's the whole
        # isolation property. If it points at the canonical host, isolation is
        # off and the security boundary is gone.
        iframe_src = Locator.get_attribute!(Page.locator(page, "#critPreviewIframe"), "src")

        assert is_binary(iframe_src) and
                 String.starts_with?(iframe_src, "#{@preview_origin}/r/#{token}/raw/index.html"),
               "iframe src = #{inspect(iframe_src)}"

        # Receive the origin beacon from inside the iframe. This confirms the
        # preview executes on PREVIEW_ORIGIN (not the canonical app host).
        beacon = wait_for_probe(page, "iframe-origin-beacon")
        assert beacon["msg"] == @preview_origin, "iframe origin beacon"

        # Isolation also rests on the frame having an *opaque* origin, which the
        # beacon above cannot show (location.origin comes from the URL and reads
        # PREVIEW_ORIGIN either way). Assert both halves.
        sandbox = Locator.get_attribute!(Page.locator(page, "#critPreviewIframe"), "sandbox")
        assert (sandbox || "") =~ "allow-scripts", "iframe sandbox"
        refute (sandbox || "") =~ "allow-same-origin", "iframe sandbox"
        assert beacon["documentOrigin"] == "null", "iframe document origin"

        # Receive the session-ride probe. Assert the attack did NOT reach
        # authenticated canonical content.
        probe = wait_for_probe(page, "session-ride-via-dash-route")

        if probe["status"] == 200 or probe["hasAuth"] == true do
          raise "SECURITY LEAK: attacker preview iframe reached authenticated canonical content.\n" <>
                  "probe = #{Jason.encode!(probe)}\n" <>
                  "victim = #{email}\n" <>
                  "preview iframe origin = #{beacon["msg"]}\n"
        end

        # Belt-and-suspenders: regardless of how the request is blocked, the
        # authenticated dashboard markup must not have made it into the iframe.
        assert probe["hasAuth"] == false, "authed marker must NOT appear in iframe response"
      after
        APIRequestContext.delete!(request, "#{@canonical_origin}/api/reviews",
          data: %{delete_token: delete_token}
        )
      end
    end
  end
end
