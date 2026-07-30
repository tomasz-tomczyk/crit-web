/**
 * Adversarial payload library for the security/isolation E2E suite.
 *
 * Each export is a function that returns HTML/text to be uploaded as a preview
 * review (or back-injected into another sink — e.g. a comment body) and a
 * matching listener predicate that decodes the postMessage probe the payload
 * emits from inside the iframe. Add a new payload here when a new attack
 * surface or sink emerges; the spec file (`e2e/security.spec.ts`) just imports
 * payloads and runs them through the same harness.
 *
 * Convention: every payload posts a `CRIT_SEC_PROBE` message to `parent`. The
 * spec uses `page.addInitScript` to capture these probes before the iframe
 * navigates. None of these payloads rely on layering-specific implementation
 * details — they assert the *security property* ("authenticated canonical
 * content is not readable from user-authored JS inside a preview iframe"),
 * independent of how the fix achieves it (host-gate, redirect, sandbox, CSP,
 * …). A regression that re-introduces the vuln by any path should fail.
 */

export interface SecProbe {
  type: "CRIT_SEC_PROBE";
  variant: string;
  status?: number | string;
  hasAuth?: boolean;
  msg?: string;
  [k: string]: unknown;
}

/**
 * Deterministic marker present in /dashboard's HTML for an authenticated user
 * (`lib/crit_web/live/dashboard_live.html.heex` line 18:
 * "Hi <name>, where to today?"). The unauth path redirects via LiveView and
 * does NOT render this string in the initial HTTP response body. So presence
 * of this marker unambiguously means: cookies were sent AND server treated the
 * request as authenticated.
 */
export const AUTHED_DASHBOARD_MARKER = "where to today?";

/**
 * Payload: attempt to "ride" the viewer's session cookies against /dashboard
 * from inside the preview iframe. Uses a *relative* URL (`/dashboard`), which
 * resolves against the iframe's document origin:
 *   - Without origin isolation: iframe document = canonical host → fetch hits
 *     /dashboard same-origin with cookies → 200 + authed HTML → hasAuth:true.
 *     THIS IS THE VULN. Probe exposes it.
 *   - With origin isolation: iframe document = preview host → fetch hits
 *     /dashboard on the preview host → HostGate 404 → no leak.
 *
 * `redirect: "manual"` makes the LV on_mount redirect (unauth path) return as a
 * redirect response we can inspect, instead of Playwright following it
 * automatically.
 */
export function previewSessionRidePayload(): string {
  const marker = AUTHED_DASHBOARD_MARKER;
  return `<script>
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
    probe(res.status, text.includes(${JSON.stringify(marker)}), text.slice(0, 160));
  } catch (e) {
    probe("BLOCKED", false, String(e));
  }
})();
</script>`;
}

/**
 * Sanity payload: a probe that reports its own `location.origin` back to the
 * parent. With isolated sandboxing (no allow-same-origin), this is "null"
 * (opaque origin) even though the iframe URL is on PREVIEW_HOST.
 */
export function previewOriginBeaconPayload(): string {
  return `<script>
parent.postMessage({
  type: "CRIT_SEC_PROBE",
  variant: "iframe-origin-beacon",
  msg: location.origin,
}, "*");
</script>`;
}

/**
 * Type guard for the probe messages.
 */
export function isSecProbe(d: unknown): d is SecProbe {
  return (
    typeof d === "object" &&
    d !== null &&
    (d as { type?: unknown }).type === "CRIT_SEC_PROBE"
  );
}
