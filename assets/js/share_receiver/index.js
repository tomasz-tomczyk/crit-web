// Share-receiver entry. Runs in a popup opened by crit's local CLI frontend
// (random localhost:port origin). The handshake works as follows:
//
//   1. We read `nonce` from window.location.hash (#nonce=...).
//   2. We postMessage {type:'ready', nonce} to window.opener with target '*'.
//      Opener origin is dynamic (random local port) so '*' is unavoidable.
//      The message body only contains the nonce, which is also visible in
//      the URL hash — no info leak.
//   3. Opener replies with {type:'init', nonce, port: port2} carrying a
//      MessagePort. From then on both sides talk through the port only;
//      MessagePort has no origin and is the trust anchor.
//
// Port lifecycle: this script owns port2. When the page navigates or the
// popup closes, port2 is GC'd implicitly — no explicit cleanup needed on
// this side. The opener closes its port1 in session.close().
//
// The bundler wraps this whole module in an IIFE (esbuild --format=iife),
// so top-level statements only run once when the script loads.

import * as handlers from './handlers.js';

// Map op type -> handler. The opener picks an op via msg.type; unknown ops
// reject with 'unknown op: …'.
window.__handlers = {
  share: handlers.share,
  fetch: handlers.fetchComments,
  upsert: handlers.upsert,
  unpublish: handlers.unpublish,
};

const status = document.getElementById('status');
function setStatus(text) {
  if (status) status.textContent = text;
}

const hashNonce = (window.location.hash.match(/[#&]nonce=([A-Za-z0-9_-]+)/) ||
  [])[1];

if (!hashNonce) {
  setStatus('Error: missing handshake nonce.');
} else if (!window.opener) {
  setStatus(
    'Error: this page must be opened from the crit app (window.opener is null — possibly blocked by COOP).'
  );
} else {
  startHandshake(hashNonce);
}

function startHandshake(nonce) {
  let port = null;
  let initialized = false;

  function onInit(event) {
    if (initialized) return;
    if (!event.data || event.data.type !== 'init' || event.data.nonce !== nonce) return;
    if (!event.ports || !event.ports[0]) return;
    initialized = true;
    window.removeEventListener('message', onInit);
    port = event.ports[0];
    port.onmessage = (e) => onPortMessage(port, e);
    port.start();
    setStatus('Ready.');
  }

  window.addEventListener('message', onInit);

  // Send 'ready' to opener. The opener attaches its message listener BEFORE
  // window.open() (see openShareReceiver in crit/frontend/app.js), so this
  // is race-free.
  try {
    window.opener.postMessage({ type: 'ready', nonce }, '*');
  } catch (_err) {
    setStatus('Error: cannot reach opener.');
  }
}

async function onPortMessage(port, event) {
  const msg = event.data || {};
  setStatus('Processing ' + (msg.type || 'request') + '…');
  try {
    const handler = window.__handlers && window.__handlers[msg.type];
    if (!handler) throw new Error('unknown op: ' + msg.type);
    const result = await handler(msg);
    port.postMessage({ requestId: msg.requestId, ok: true, data: result });
    setStatus('Done.');
  } catch (err) {
    port.postMessage({
      requestId: msg.requestId,
      ok: false,
      error: String((err && err.message) || err),
    });
    setStatus('Error: ' + ((err && err.message) || err));
  }
}
