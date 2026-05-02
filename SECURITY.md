# Security

## Reporting vulnerabilities

If you discover a security vulnerability, please email security@crit.md instead of opening a public issue.

## Design decisions

### No API authentication

The `POST /api/reviews` endpoint is intentionally open (no API key required). This is by design — the crit CLI needs to upload reviews without user accounts or tokens. Protection is provided by:

- **Rate limiting** — write endpoints are limited to 30 requests/minute per IP via [Hammer](https://hex.pm/packages/hammer)
- **Size limits** — 10 MB total per review, 50 KB per comment, 500 comments max, 200 files max
- **Auto-expiry** — reviews are automatically deleted after 30 days of inactivity

### Token-based deletion

Reviews are deleted by presenting a `delete_token` (returned at creation time). The crit CLI stores this in the review file (`~/.crit/reviews/`). There are no user accounts.

### Identity

Visitor identity is session-based (cookie). Display names are stored per-session and used for comment attribution. There is no authentication system.

### CORS

The API only accepts requests from `localhost` and `127.0.0.1` origins, since the only intended API client is the local crit CLI.
