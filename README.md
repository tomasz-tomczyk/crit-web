# Crit Web

[![CI](https://github.com/tomasz-tomczyk/crit-web/actions/workflows/ci.yml/badge.svg)](https://github.com/tomasz-tomczyk/crit-web/actions/workflows/ci.yml)
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
  -e ADMIN_PASSWORD=your-secure-password \
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
| `DATABASE_URL` | Yes | — | PostgreSQL connection URL (`ecto://USER:PASS@HOST/DB`) |
| `SECRET_KEY_BASE` | Yes | — | Session signing key. Generate with `openssl rand -base64 64` |
| `SELFHOSTED` | Yes | — | Set to `true` to enable self-hosted mode (dashboard, no marketing pages) |
| `ADMIN_PASSWORD` | No | — | Password for the `/dashboard` admin panel. If unset, the dashboard is accessible without authentication |
| `PHX_HOST` | No | `localhost` | Hostname for URL generation |
| `PORT` | No | `4000` | HTTP listening port |
| `FORCE_SSL` | No | `false` | Set `true` if terminating TLS at the app (not behind a reverse proxy) |
| `PHX_SCHEME` | No | `https` | URL scheme for link generation |
| `PHX_URL_PORT` | No | `443`/`80` | Port for generated URLs |
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

## License

[MIT](LICENSE)
