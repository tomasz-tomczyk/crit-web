# Crit Web

[![CI](https://github.com/tomasz-tomczyk/crit-web/actions/workflows/ci.yml/badge.svg)](https://github.com/tomasz-tomczyk/crit-web/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/tomasz-tomczyk/crit-web/graph/badge.svg)](https://codecov.io/gh/tomasz-tomczyk/crit-web)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/ghcr.io-crit--web-blue)](https://ghcr.io/tomasz-tomczyk/crit-web)

The hosted share target for [Crit](https://github.com/tomasz-tomczyk/crit) — a local-first CLI for reviewing AI agent output with inline comments.

When you click **Share** in the crit CLI, your review (document + comments) is uploaded here and a public link is generated. Recipients see the full review page with inline comments, keyboard navigation, and theme switching — no install required.

**Hosted version:** [crit.md](https://crit.md)

## How it works

1. You run `crit` locally to review files and add inline comments
2. Click **Share** — the CLI uploads the review to crit-web
3. Share the link — recipients see the full review with comments, no install required
4. **Unpublish** from the CLI when done

Reviews auto-expire after 30 days of inactivity.

## Self-Hosting

Crit Web can be self-hosted with Docker. You need PostgreSQL 17+.

### Option 1: `docker run` (you already have PostgreSQL)

```bash
docker run -d \
  -e DATABASE_URL=ecto://user:pass@your-db-host/crit_prod \
  -e SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n') \
  -e SELFHOSTED=true \
  -e PHX_HOST=localhost \
  -e PHX_SERVER=true \
  -p 4000:4000 \
  ghcr.io/tomasz-tomczyk/crit-web:latest
```

Migrations run automatically on startup.

### Option 2: Docker Compose (includes PostgreSQL)

```bash
cp contrib/docker-compose.example.yml docker-compose.yml
cp .env.example .env
# Edit .env — at minimum, set SECRET_KEY_BASE:
#   openssl rand -base64 64 | tr -d '\n'
docker compose up -d
```

Visit `http://localhost:4000`.

### Connecting the crit CLI

Point the CLI at your instance:

```bash
# Per-command
crit --share-url https://reviews.yourdomain.com path/to/files

# Or set permanently
export CRIT_SHARE_URL=https://reviews.yourdomain.com
```

### Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes* | — | PostgreSQL connection URL (`ecto://USER:PASS@HOST/DB`) |
| `DB_HOST` | Yes* | — | Database host — use instead of `DATABASE_URL` |
| `DB_USER` | Yes* | — | Database user |
| `DB_PASSWORD` | Yes* | — | Database password |
| `DB_NAME` | Yes* | — | Database name |
| `DB_PORT` | No | `5432` | Database port (only used with `DB_HOST`) |
| `DB_SSL` | No | — | Set to `true` to enable SSL. Without `DB_SSL_CA_CERT`, connects encrypted without certificate verification (typical for AWS RDS) |
| `DB_SSL_CA_CERT` | No | — | Path to a CA certificate file. When set alongside `DB_SSL=true`, enables full `verify_peer` verification (requires volume mount in Docker) |
| `SECRET_KEY_BASE` | Yes | — | Session signing key. Generate with `openssl rand -base64 64` |
| `SELFHOSTED` | Yes | — | Set to `true` to enable self-hosted mode (dashboard, no marketing pages) |
| `LOCAL_REGISTRATION_ENABLED` | No | `true` | Set to `false` to close `/users/register` after creating the accounts you trust |
| `SMTP_HOST` | No | — | SMTP relay hostname. When set, password-reset and email-change confirmations are sent via SMTP; when unset, those emails go to the local Swoosh adapter |
| `SMTP_PORT` | No | `587` | SMTP port. `465` uses implicit TLS; other ports use STARTTLS |
| `SMTP_USERNAME` | No | — | SMTP auth username |
| `SMTP_PASSWORD` | No | — | SMTP auth password |
| `SMTP_FROM` | No† | — | From address for outgoing email (e.g. `noreply@yourdomain.com`). Required when `SMTP_HOST` is set |
| `GITHUB_CLIENT_ID` | No | — | GitHub OAuth App client ID. Set with `GITHUB_CLIENT_SECRET` to enable GitHub login. When set, OAuth is required to access the dashboard and view reviews |
| `GITHUB_CLIENT_SECRET` | No | — | GitHub OAuth App client secret |
| `OAUTH_CLIENT_ID` | No | — | Generic OIDC/OAuth2 client ID for Google, GitLab, Okta, etc. Use with `OAUTH_CLIENT_SECRET` and `OAUTH_BASE_URL`. Mutually exclusive with `GITHUB_CLIENT_ID` |
| `OAUTH_CLIENT_SECRET` | No | — | Generic OAuth2 client secret |
| `OAUTH_BASE_URL` | No | — | OIDC discovery base URL, e.g. `https://accounts.google.com` |
| `PHX_HOST` | No | `localhost` | Hostname for URL generation |
| `PORT` | No | `4000` | HTTP listening port |
| `FORCE_SSL` | No | `false` | Set `true` if terminating TLS at the app (not behind a reverse proxy) |
| `PHX_SCHEME` | No | `https` | URL scheme for link generation |
| `PHX_URL_PORT` | No | `443`/`80` | Port for generated URLs |
| `SENTRY_DSN` | No | — | Backend [Sentry](https://sentry.io) DSN. When unset, no Sentry traffic is generated. Self-hosted deployments leave this blank by default |
| `SENTRY_FRONTEND_DSN` | No | — | Browser SDK DSN. The `@sentry/browser` chunk is only fetched when this is set, so unset means zero third-party requests |
| `SENTRY_ENV` | No | `prod` (frontend) / `Mix.env()` (backend) | Sentry environment tag |
| `SENTRY_RELEASE` | No | `mix.exs` version | Release tag for Sentry events. The hosted Fly deploy auto-sets this to the commit SHA |

\* Set either `DATABASE_URL` **or** all four of `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`.
| `POOL_SIZE` | No | `10` | Database connection pool size |

### Behind a reverse proxy

The app listens on HTTP. Your reverse proxy (nginx, Caddy, Traefik) handles TLS.

```env
PHX_HOST=reviews.yourdomain.com
PHX_SCHEME=https
PHX_URL_PORT=443
```

### Updating

```bash
docker compose pull
docker compose up -d
```

## Development

```bash
mix setup       # Install deps, create DB, run migrations, build assets
mix phx.server  # Start dev server on :4000
mix test        # Run tests
mix precommit   # Full CI check before submitting
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

## Privacy

Self-hosted Crit Web collects no analytics or tracking data. The public crit.md deployment uses [Umami](https://umami.is) for cookieless, aggregate website analytics (page views and traffic sources only — not linked to individual users or review content). See the [privacy policy](https://crit.md/privacy) for details.

## License

[MIT](LICENSE)
