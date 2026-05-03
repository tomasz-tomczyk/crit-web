# Share Receiver — Manual QA Script

The share-receiver page (`/share-receiver`) is a single-purpose popup that
relays share / fetch / upsert / unpublish requests from crit's local CLI
through an SSO reverse proxy to crit-web. There is no automated e2e harness
in this repo, so changes that touch the receiver flow MUST be exercised
against this checklist before shipping.

ExUnit covers the controller (route exists, layoutless render, noindex,
correct bundle reference). The handler module has no automated coverage
yet — vitest adoption is a separate decision. Until then, this script is
the gate.

## Prerequisites

- crit-web running locally: `mise run up` (server on `:4000`).
- crit local binary built from the matching branch with `share_flow=popup`
  configured.
- Browser: latest Chromium AND latest Safari (popup-blocker behavior
  diverges).

## 1. Happy path — share

1. Start crit local with a review file loaded.
2. Click **Share**.
3. Popup opens at `http://localhost:4000/share-receiver#nonce=<nonce>`.
4. Status text transitions: `Authenticating…` → `Ready.` → `Processing share…` → `Done.`
5. Popup auto-closes (or the opener closes it via `session.close()`).
6. Local UI shows the hosted URL.

Expected: review row exists in crit-web's DB; `/r/:token` renders it.

## 2. Happy path — fetch (Pull)

After (1), in crit local click **Pull** on the share modal.

Expected: same handshake, then `Processing fetch…`. Comments from crit-web
are merged into the local review file in place — no `location.reload`.

## 3. Happy path — upsert (Re-share)

After (1), make a local edit + add a comment, then click **Re-share**.

Expected: `Processing upsert…`. crit-web bumps `review_round`; the existing
URL still resolves.

## 4. Happy path — unpublish

Click **Unpublish** on a shared review.

Expected: `Processing unpublish…`. Subsequent `GET /r/:token` returns 404
(cleanly, not 500). Re-running unpublish on the same token returns
`{already_deleted: true}` and the local UI accepts that as success.

## 5. Hostile origin (threat model — document, do not test live)

A page on `https://evil.example` could call
`window.open('http://localhost:4000/share-receiver#nonce=guess')`. The
receiver will postMessage `{type:'ready'}` to the *opener*, which is the
hostile page. The hostile page knows the nonce (it picked the URL).

Mitigation: the *crit local* opener validates `event.source` is the popup
it just opened AND that the nonce matches one it generated this session.
A hostile page that doesn't know the local opener's nonce table can't
forge a `ready` event the local opener will accept.

Defence-in-depth: even if the hostile page somehow gets a port, every
receiver op is a same-origin fetch against crit-web, and the user's SSO
session must already be valid for those endpoints to do anything.

This case is not exercised in this script — document only.

## 6. Wrong nonce

In a browser tab, manually `window.open('http://localhost:4000/share-receiver#nonce=garbage')`
from the crit local frontend's devtools. The opener's listener should
ignore the `ready` event (nonce mismatch) and never send `init`. Status
on the popup stays at `Ready.` indefinitely (or `Authenticating…`
depending on whether init ever arrives — it shouldn't).

## 7. Popup closed mid-op

Trigger a share, then immediately close the popup before it returns.

Expected: opener detects popup-closed within 500ms (`session.close()`
polling) and rejects the in-flight promise with `session closed`. UI
shows a usable error toast — no spinner stuck forever.

## 8. COOP severed

Temporarily set `Cross-Origin-Opener-Policy: same-origin` on
`/share-receiver` (e.g. via a local nginx in front of `:4000` for one
session). Open the popup.

Expected: receiver displays `Error: this page must be opened from the
crit app (window.opener is null — possibly blocked by COOP).` Opener
detects the popup never sent `ready` and times out cleanly.

## 9. CSP violations

Open `http://localhost:4000/share-receiver#nonce=test` directly. Open
DevTools → Console.

Expected: zero CSP violation messages. `style-src 'self' 'unsafe-inline'`
covers the inline `<style>` block; `script-src 'self'` covers the bundled
`/assets/js/share_receiver/index.js`.

If a violation appears, do NOT loosen CSP. Either externalise the inline
style or compute and pin a `sha256-...` for the inline content.

## 10. Re-share partial failure

Trigger a re-share where the proxy session has expired between the
initial popup-open and the upsert fetch. The handler reads
`crit-web returned HTML (proxy not authenticated?)` and surfaces that
error. The opener toast must mention re-authentication on retry — not
just a generic 500.
