#!/usr/bin/env bash
# Build a prod release and smoke-test pages that read runtime priv files.
# Catches bugs where compile-time priv paths work in dev/test but fail in releases.
set -euo pipefail

cd "$(dirname "$0")/.."

export MIX_ENV=prod
smoke_port="${RELEASE_SMOKE_PORT:-4001}"
export PORT="$smoke_port"
export DATABASE_URL="${DATABASE_URL:?DATABASE_URL is required}"
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -base64 64)}"

mix local.hex --force >/dev/null
mix local.rebar --force >/dev/null
mix deps.get --only prod
npm ci --prefix assets
mix compile
mix assets.deploy
mix release --overwrite

_build/prod/rel/crit/bin/migrate

# In Docker/production only the release's lib/crit-*/priv tree exists — not the
# source checkout's priv/. Hide source priv so runtime reads must use
# :code.priv_dir/1, not compile-time Path.expand paths baked into the BEAM.
release_priv=$(
  find _build/prod/rel/crit/lib -maxdepth 3 -type d -path '*/priv/articles' -print -quit
)
if [ -z "$release_priv" ] || [ ! -d "$release_priv" ]; then
  echo "release smoke: expected articles under release priv, found none" >&2
  exit 1
fi
mv priv priv.source-hidden-for-smoke
priv_hidden=1
restore_priv() {
  if [ "${priv_hidden:-0}" = "1" ] && [ -d priv.source-hidden-for-smoke ]; then
    mv priv.source-hidden-for-smoke priv
    priv_hidden=0
  fi
}

PHX_SERVER=true _build/prod/rel/crit/bin/server &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  restore_priv
}
trap cleanup EXIT

for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${smoke_port}/health" >/dev/null; then
    break
  fi
  sleep 1
done

curl -sf "http://127.0.0.1:${smoke_port}/health" >/dev/null
curl -sf "http://127.0.0.1:${smoke_port}/" >/dev/null
curl -sf "http://127.0.0.1:${smoke_port}/articles" >/dev/null

echo "release smoke OK"
