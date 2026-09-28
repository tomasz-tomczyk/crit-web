---
name: develop-newsletter
description: >-
  Draft, review, host, and send crit product newsletters. Use when working on
  newsletter HTML, Postmark Broadcast sends, subscriber sync, R2 assets, or the
  crit.md /newsletter/:slug archive.
---

# Develop a crit newsletter

## Source of truth

Single HTML archive lives in **crit-web** (hosted SaaS only):

```
priv/newsletters/<slug>/
  index.html          # full email HTML
  images/             # local copies; also uploaded to R2
```

Route (HostedOnly — 404 on self-hosted):

- Browser archive: `https://crit.md/newsletter/<slug>`
- Local: `http://localhost:4000/newsletter/<slug>`

Scratch copies under `crit-meta/newsletter/` are not the source of truth.

## Review workflow

Prefer **live mode** against the hosted page (not file preview):

```bash
# from the crit-web worktree, with phx.server running
crit live http://localhost:4000/newsletter/<slug>
```

Live mode reviews the same URLs/images the archive serves. File `crit preview`
is only a fallback when the server is down.

## Images

1. Keep files in `priv/newsletters/<slug>/images/`.
2. Upload to Cloudflare R2 (`crit-assets` bucket):

```bash
CRIT_ASSETS_BUCKET=crit-assets ./scripts/upload-newsletter-assets.sh <slug>
```

Public URLs: `https://assets.crit.md/newsletter/<slug>/<file>`

3. For **sends**, rewrite `src="images/` → the absolute R2 URL.
4. The browser controller rewrites relative `images/` to `/newsletter/<slug>/images/` for local preview. Absolute R2 URLs work in both send and archive.

Include a **View in browser** link in the email header pointing at `https://crit.md/newsletter/<slug>`.

## Postmark

- Transactional (`outbound`): app mail (invites, digests). Not for newsletters.
- Broadcast (`broadcast`): marketing. Already exists; unsubscribe handling type is Postmark (`{{{ pm:unsubscribe }}}` works here only).
- From: `Tomasz from crit <hello@crit.md>`

### NEVER send until a human confirms

Do **not** call Postmark send APIs, SMTP, or any bulk/sample mail unless the human explicitly says to send (and to whom). Drafting HTML, uploading R2 assets, creating streams, and dry-runs are fine. Previous sample sends do not authorize another send.

When a confirmation send is approved, hard-limit recipients in code (`To` exact list, no CC/BCC) and print the recipient list before the API call.

## Subscribers

Opt-in source of truth is Postgres on crit-web: latest row per user in `marketing_consent_events` where action is opt-in.

Postmark does **not** auto-sync consent into its address book. Before a Broadcast send:

1. Export current opt-in emails from prod (latest `marketing_consent_events` row per user).
2. Prefer sending that list via the Postmark API on stream `broadcast`.

**Unsubscribers:** you do **not** need to sync Postmark suppressions into Postgres for delivery safety. On Broadcast with Postmark unsubscribe handling, Postmark refuses suppressed addresses automatically. Optionally sync suppressions back into `marketing_consent_events` later so Settings UI stays accurate — that is product hygiene, not a send blocker.

Longer-term: a mix task that exports consent → Postmark recipients is fine; do not invent continuous sync without a design pass.

## Checklist for a new issue

1. Create `priv/newsletters/<slug>/` with HTML + images in a crit-web worktree.
2. Upload images to R2.
3. Wire View in browser → `/newsletter/<slug>`.
4. `crit live` review rounds until approved.
5. Ship/deploy crit-web so the archive is public.
6. Human confirms send → Broadcast stream only, consent ∩ suppressions, plain-text body too.
