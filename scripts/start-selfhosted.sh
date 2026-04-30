#!/usr/bin/env bash
# start-selfhosted.sh — boot crit-web in selfhosted + OAuth-enforced mode
# for integration testing.
#
# Usage:
#   set -a; . .envrc.local; set +a
#   ./scripts/start-selfhosted.sh
#
# Required env (set by .envrc.local):
#   GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET
#
# Sets PORT=4001, DB_NAME=crit_dev_selfhost, DB_PORT=5433,
# SELFHOSTED=true, PHX_SERVER=true, MIX_ENV=dev. Runs migrations,
# then execs `mix phx.server` in the foreground (so a Makefile target
# can background it with `&` and kill it).

set -euo pipefail

if [ -z "${GITHUB_CLIENT_ID:-}" ] || [ -z "${GITHUB_CLIENT_SECRET:-}" ]; then
  echo "ERROR: GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET must be set." >&2
  echo "Source the .envrc.local file first:" >&2
  echo "  set -a; . .envrc.local; set +a" >&2
  exit 1
fi

export PORT=4001
export DB_NAME=crit_dev_selfhost
export DB_PORT=5433
export SELFHOSTED=true
export PHX_SERVER=true
export MIX_ENV=dev

cd "$(dirname "$0")/.."

# NOTE: this repo's mise.toml hardcodes PORT, DB_NAME, etc. in [env], which
# overrides anything we export here. Re-injecting via `env ... mix` AFTER
# `mise exec --` puts the right values on the actual process.
ENV_OVERRIDES=(
  "PORT=$PORT"
  "DB_NAME=$DB_NAME"
  "DB_PORT=$DB_PORT"
  "SELFHOSTED=$SELFHOSTED"
  "PHX_SERVER=$PHX_SERVER"
  "MIX_ENV=$MIX_ENV"
  "GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID"
  "GITHUB_CLIENT_SECRET=$GITHUB_CLIENT_SECRET"
)

mise exec -- env "${ENV_OVERRIDES[@]}" mix ecto.create -r Crit.Repo --quiet || true
mise exec -- env "${ENV_OVERRIDES[@]}" mix ecto.migrate --quiet

exec mise exec -- env "${ENV_OVERRIDES[@]}" mix phx.server
