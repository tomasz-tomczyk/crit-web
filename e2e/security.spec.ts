/**
 * Security/isolation E2E suite.
 *
 * Drives a *second* Playwright webServer (playwright.config.ts webServer #2)
 * that boots Phoenix on port 4004 with `PREVIEW_HOST=preview.127.0.0.1.nip.io`
 * and `PHX_HOST=127.0.0.1.nip.io`. nip.io resolves both names to 127.0.0.1, so
 * they share the loopback but the browser treats them as separate origins →
 * the app's canonical vs. preview split surfaces the same way it does in prod.
 *
 * Property asserted:
 *   Logged-in victim's session cookies on the canonical host must not be
 *   readable — not even addressable — by JS the victim did not author,
 *   running inside a preview iframe the victim opens.
 *
 * The suite tests the *property*, not the fix's implementation. A regression
 * that re-introduces the #291 vuln (e.g. iframe served same-origin again, or a
 * fresh sink that bypasses HostGate) should fail this spec without anyone
 * having to extend it.
 *
 * Run locally:
 *   npx playwright test security.spec.ts
 * The full `mise run e2e` also runs this spec. It uses port 4004 + the second
 * webServer in playwright.config.ts.
 */

import { test, expect, type Page } from "@playwright/test";
import {
  AUTHED_DASHBOARD_MARKER,
  previewOriginBeaconPayload,
  previewSessionRidePayload,
  type SecProbe,
} from "./security/payloads";

// nip.io wildcards to 127.0.0.1 — same loopback as Bandit, but the browser
// treats the two hostnames as distinct origins and gates cookies per origin
// (matching the canonical/preview split the app uses in prod). Both env
// vars below must match playwright.config.ts's second webServer so the app
// side and the spec side agree on what "isolated" means.
const PORT = "4004";
const CANONICAL_HOST = "127.0.0.1.nip.io";
const PREVIEW_HOST = "preview.127.0.0.1.nip.io";
const CANONICAL_ORIGIN = `http://${CANONICAL_HOST}:${PORT}`;
const PREVIEW_ORIGIN = `http://${PREVIEW_HOST}:${PORT}`;

/**
 * Install a window.postMessage listener that buffers CRIT_SEC_PROBE messages
 * from any child iframe. MUST be called before any iframe that emits a probe
 * navigates — i.e. before page.goto to the review route.
 */
async function installProbeListener(page: Page): Promise<void> {
  await page.addInitScript(() => {
    (window as unknown as { __critSecProbes?: SecProbe[] }).__critSecProbes =
      [];
    window.addEventListener("message", (event) => {
      if (
        typeof event.data === "object" &&
        event.data !== null &&
        (event.data as { type?: unknown }).type === "CRIT_SEC_PROBE"
      ) {
        (
          window as unknown as { __critSecProbes: SecProbe[] }
        ).__critSecProbes.push(event.data);
      }
    });
  });
}

async function waitForProbe(
  page: Page,
  variant: string,
  timeoutMs = 10_000,
): Promise<SecProbe> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const found = await page.evaluate((variant) => {
      const probes = (window as unknown as { __critSecProbes?: SecProbe[] })
        .__critSecProbes;
      return (probes ?? []).find((p) => p.variant === variant) ?? null;
    }, variant);
    if (found) return found as SecProbe;
    await page.waitForTimeout(150);
  }
  throw new Error(
    `no CRIT_SEC_PROBE with variant "${variant}" within ${timeoutMs}ms`,
  );
}

test.describe("Preview isolation: preview iframe cannot exfiltrate victim session", () => {
  test("isolated preview agent enables pin mode and sends selections", async ({
    page,
    request,
  }) => {
    const files = [
      {
        path: "index.html",
        content:
          '<!doctype html><html><body><p id="existing">Existing marker target</p><h1 id="hero">Pin me</h1></body></html>',
        status: "modified",
      },
    ];

    const res = await request.post(`${CANONICAL_ORIGIN}/api/reviews`, {
      data: {
        review_type: "preview",
        review_round: 0,
        files,
      },
    });
    expect(res.status(), "preview review creation").toBe(201);
    const body = await res.json();
    const token = (body.url as string).split("/r/")[1];
    const deleteToken = body.delete_token as string;

    // The stored anchor pathname is the iframe's actual raw route, which is
    // only known after the API allocates the review token.
    const updateRes = await request.put(
      `${CANONICAL_ORIGIN}/api/reviews/${token}`,
      {
        data: {
          delete_token: deleteToken,
          review_round: 0,
          files,
          comments: [
            {
              start_line: 0,
              end_line: 0,
              body: "Existing pin",
              scope: "file",
              file_path: "index.html",
              dom_anchor: {
                pathname: `/r/${token}/raw/index.html`,
                css_selector: "#existing",
                tag_chain: ["body", "p"],
                outer_html: '<p id="existing">Existing marker target</p>',
              },
            },
          ],
        },
      },
    );
    expect(updateRes.status(), "preview review marker seed").toBe(200);

    try {
      await page.goto(`${CANONICAL_ORIGIN}/r/${token}`);
      await page.waitForSelector("#critPreviewIframe", { timeout: 15_000 });

      const iframeSrc = await page
        .locator("#critPreviewIframe")
        .getAttribute("src");
      expect(iframeSrc).toBe(`${PREVIEW_ORIGIN}/r/${token}/raw/index.html`);

      // agent-ready crosses preview → canonical and enables Pin. Switching
      // mode crosses canonical → preview; the click selection then crosses
      // back and opens the host-side composer.
      const pinButton = page.locator(
        '#critPreviewMode button[data-mode="pin"]',
      );
      await expect(pinButton).toBeEnabled({ timeout: 15_000 });

      // The agent fetches marker CSS from the canonical host. Confirm the
      // isolated preview origin receives that stylesheet through narrow CORS.
      const marker = page
        .frameLocator("#critPreviewIframe")
        .locator(".crit-live-marker");
      await expect(marker).toBeVisible({ timeout: 10_000 });
      await expect(marker).toHaveCSS("width", "22px");
      await expect(marker).toHaveCSS("background-color", "rgb(37, 99, 235)");

      await pinButton.click();
      await expect(pinButton).toHaveAttribute("aria-pressed", "true");

      await page.frameLocator("#critPreviewIframe").locator("#hero").click();
      await expect(page.locator(".crit-preview-composer-body")).toBeVisible({
        timeout: 10_000,
      });
    } finally {
      await request.delete(`${CANONICAL_ORIGIN}/api/reviews`, {
        data: { delete_token: deleteToken },
      });
    }
  });

  test("raw preview route 308-redirects from canonical to preview host", async ({
    request,
  }) => {
    // Smoke check that isolation is actually configured for this spec. If
    // this fails, the second webServer in playwright.config.ts is missing or
    // env vars drifted — fix the harness, not the spec.
    const res = await request.post(`${CANONICAL_ORIGIN}/api/reviews`, {
      data: {
        review_type: "preview",
        review_round: 0,
        files: [
          {
            path: "index.html",
            content: "<!doctype html><title>innocent</title>",
            status: "modified",
          },
        ],
      },
    });
    expect(res.status(), "preview review creation").toBe(201);
    const body = await res.json();
    const token = (body.url as string).split("/r/")[1];
    const deleteToken = body.delete_token as string;

    try {
      // Hit the raw route on the canonical host. With isolation enabled the
      // server issues a 308 redirect to the preview host. Without isolation
      // it just serves the file (status 200) — exactly the #291 vuln.
      // Manual redirect handling avoids Playwright following it.
      const rawRes = await request.get(
        `${CANONICAL_ORIGIN}/r/${token}/raw/index.html`,
        { maxRedirects: 0 },
      );
      expect(rawRes.status(), "canonical-host raw status").toBe(308);
      const location = rawRes.headers()["location"] ?? "";
      expect(
        location.startsWith(`${PREVIEW_ORIGIN}/r/${token}/raw/index.html`),
        `redirect location: ${location}`,
      ).toBe(true);
    } finally {
      await request.delete(`${CANONICAL_ORIGIN}/api/reviews`, {
        data: { delete_token: deleteToken },
      });
    }
  });

  test("preview-host /dashboard is 404 (HostGate)", async ({ request }) => {
    // HostGate confines the preview host to a narrow route surface. The
    // dashboard (and any authed-only LiveView) must not be reachable there.
    const res = await request.get(`${PREVIEW_ORIGIN}/dashboard`, {
      maxRedirects: 0,
    });
    expect(res.status()).toBe(404);
  });

  test("logged-in victim's session is not exfiltrated by preview review JS", async ({
    page,
    request,
  }) => {
    // --- Setup: seed a victim user and login them on the canonical host. ---
    const email = `victim-${Date.now()}-${Math.random()
      .toString(36)
      .slice(2, 8)}@crit-security-test.example`;
    const name = `Victim-${Math.random().toString(36).slice(2, 8)}`;
    const seedRes = await request.post(
      `${CANONICAL_ORIGIN}/api/test/seed-user`,
      {
        data: { name, email },
      },
    );
    expect(seedRes.status(), "seed-user").toBe(200);
    const seed = await seedRes.json();
    const userId = seed.user_id as string;

    // Log in the victim on the canonical host via the test-only GET endpoint.
    // Sets the _crit_web_session cookie scoped to 127.0.0.1.nip.io.
    await page.goto(`${CANONICAL_ORIGIN}/test/login-as/${userId}`);
    await expect
      .poll(async () => (await page.textContent("body")) ?? "")
      .toContain(`"ok":true`);

    // Sanity: confirm the victim is authenticated against /dashboard before
    // we load the attacker payload. If this fails, login-as is broken — not
    // the security boundary.
    await page.goto(`${CANONICAL_ORIGIN}/dashboard`);
    await expect(page.locator("body")).toContainText(AUTHED_DASHBOARD_MARKER, {
      timeout: 10_000,
    });

    // --- Build the attacker preview review. ---
    const attackerHtml =
      "<!doctype html><html><body>" +
      "<h1>innocent-looking preview</h1>" +
      previewOriginBeaconPayload() +
      previewSessionRidePayload() +
      "</body></html>";

    const reviewRes = await request.post(`${CANONICAL_ORIGIN}/api/reviews`, {
      data: {
        review_type: "preview",
        review_round: 0,
        files: [
          { path: "index.html", content: attackerHtml, status: "modified" },
        ],
      },
    });
    expect(reviewRes.status(), "attacker review creation").toBe(201);
    const reviewJson = await reviewRes.json();
    const token = (reviewJson.url as string).split("/r/")[1];
    const deleteToken = reviewJson.delete_token as string;

    try {
      // Install the probe listener BEFORE we navigate so we don't miss the
      // first postMessage the iframe emits.
      await installProbeListener(page);

      // Victim loads the shared preview review on the canonical host.
      await page.goto(`${CANONICAL_ORIGIN}/r/${token}`);
      await page.waitForSelector("#critPreviewIframe", { timeout: 15_000 });

      // The iframe must point at the preview origin — that's the whole
      // isolation property. If it points at the canonical host, isolation is
      // off and the security boundary is gone.
      const iframeSrc = await page
        .locator("#critPreviewIframe")
        .getAttribute("src");
      expect(
        iframeSrc?.startsWith(`${PREVIEW_ORIGIN}/r/${token}/raw/index.html`),
        `iframe src = ${iframeSrc}`,
      ).toBe(true);

      // Receive the origin beacon from inside the iframe. This confirms the
      // preview executes on PREVIEW_ORIGIN (not the canonical app host).
      const beacon = await waitForProbe(page, "iframe-origin-beacon");
      expect(beacon.msg, "iframe origin beacon").toBe(PREVIEW_ORIGIN);

      // Receive the session-ride probe. Assert the attack did NOT reach
      // authenticated canonical content.
      const probe = await waitForProbe(page, "session-ride-via-dash-route");

      if (probe.status === 200 || probe.hasAuth === true) {
        throw new Error(
          `SECURITY LEAK: attacker preview iframe reached authenticated canonical content.\n` +
            `probe = ${JSON.stringify(probe)}\n` +
            `victim = ${email}\n` +
            `preview iframe origin = ${beacon.msg}\n`,
        );
      }

      // Belt-and-suspenders: regardless of how the request is blocked, the
      // authenticated dashboard markup must not have made it into the iframe.
      expect(
        probe.hasAuth,
        "authed marker must NOT appear in iframe response",
      ).toBe(false);
    } finally {
      await request.delete(`${CANONICAL_ORIGIN}/api/reviews`, {
        data: { delete_token: deleteToken },
      });
    }
  });
});
