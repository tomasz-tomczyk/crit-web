# Self-Hosted Proxy Auth Rules

<important if="you are adding a new LiveView page, modifying an existing LiveView mount, or adding WebSocket-dependent features">

## Self-hosted deployments must survive hostile proxies

1. **No WebSocket assumption**: All LiveView features must work under long-poll transport (`CRIT_LIVEVIEW_TRANSPORT=longpoll`). Test by setting the env var and verifying the feature still works.

2. **No HTTP redirects for auth gates**: When no auth backend is configured (selfhosted without OAuth), render inline gates instead of `redirect/2`. HTTP redirects through a proxy that silently follows them cause URL/view mismatch → reload loops → 429.

3. **Always emit `Cache-Control: no-transform`**: The `@before_compile` hook on the Endpoint handles this. Do not remove it. Proxies that re-encode already-compressed responses produce gibberish.

4. **`Cross-Origin-Opener-Policy` must NOT be set on `/share-receiver`**: This header breaks `window.opener.postMessage`, which the popup relay depends on. If you add COOP to the endpoint or a plug, exempt the share-receiver route.

5. **Trusted-proxy-header auth requires CIDR allowlist**: `CRIT_TRUSTED_PROXY_USER_HEADER` only takes effect when `CRIT_TRUSTED_PROXY_CIDRS` is also set. Boot must fail if the header is set without CIDRs.

</important>

<important if="you are adding a new API endpoint under /api/ that the crit CLI or browser UI will call">

## Popup relay handler required

Any new `/api/` endpoint that the crit CLI calls must also be callable through the popup relay. Add a handler function in `assets/js/share_receiver/handlers.js` that makes a same-origin fetch to the new endpoint. The handler receives a message via MessagePort and returns the response. See existing handlers (`share`, `fetchComments`, `upsert`, `unpublish`) as examples.

</important>
