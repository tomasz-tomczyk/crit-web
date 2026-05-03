// Op handlers for the share-receiver popup. Each handler maps a port message
// to a same-origin fetch against crit-web's existing /api/reviews surface.
// The proxy session cookie is attached automatically because we're on the
// same origin as crit-web. Handlers are exported individually so they can be
// unit-tested with a mocked global fetch.

export async function share(msg) {
  return await jsonOp('POST', '/api/reviews', msg.payload);
}

export async function fetchComments(msg) {
  if (!msg.token) throw new Error('missing token');
  const resp = await fetch(
    '/api/reviews/' + encodeURIComponent(msg.token) + '/comments',
    {
      method: 'GET',
      credentials: 'same-origin',
    }
  );
  return await readResponse(resp);
}

export async function upsert(msg) {
  if (!msg.token) throw new Error('missing token');
  return await jsonOp(
    'PUT',
    '/api/reviews/' + encodeURIComponent(msg.token),
    msg.payload
  );
}

export async function unpublish(msg) {
  if (!msg.delete_token) throw new Error('missing delete_token');
  const resp = await fetch('/api/reviews', {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify({ delete_token: msg.delete_token }),
  });
  if (resp.status === 404) return { already_deleted: true };
  if (!resp.ok) throw new Error('Server error ' + resp.status);
  return { ok: true };
}

async function jsonOp(method, url, body) {
  const resp = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  });
  return await readResponse(resp);
}

async function readResponse(resp) {
  const text = await resp.text();
  if (text.trimStart().startsWith('<')) {
    throw new Error('crit-web returned HTML (proxy not authenticated?)');
  }
  let body;
  try {
    body = JSON.parse(text);
  } catch (_) {
    throw new Error('invalid JSON response');
  }
  if (!resp.ok) throw new Error(body.error || 'Server error ' + resp.status);
  return body;
}
