#!/usr/bin/env bash
# Vendor crit's injected preview-agent scripts into crit-web, byte-identical.
#
# The files copied here are the EXACT set + order that crit injects into
# live/preview iframes (see `agentScriptFiles` in crit/server.go), plus
# agent-marker.css (served at /agent-marker.css locally). crit-web must serve
# the same scripts so DOM anchoring stays compatible across both renderers.
#
# When any agent-*.js / crit-agent.js / agent-marker.css changes in crit/,
# re-run this script and commit the result in both repos.
#
# Usage: scripts/sync-preview-agent.sh [SRC_DIR]
#   SRC_DIR defaults to <repo>/../crit/frontend
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$SCRIPT_DIR/../../crit/frontend}"
DST="$SCRIPT_DIR/../priv/static/preview-agent"

# Keep in sync with `agentScriptFiles` in crit/server.go (order matters:
# protocol first, helpers next, main agent entry point last) + agent-marker.css.
FILES=(
  agent-protocol.js
  agent-anchor-utils.js
  agent-marker-overlay.js
  agent-mutation-batcher.js
  agent-resolution.js
  agent-reanchor-state.js
  crit-agent.js
  agent-marker.css
)

if [[ ! -d "$SRC" ]]; then
  echo "error: source dir not found: $SRC" >&2
  exit 1
fi

mkdir -p "$DST"
for f in "${FILES[@]}"; do
  if [[ ! -f "$SRC/$f" ]]; then
    echo "error: missing source file: $SRC/$f" >&2
    exit 1
  fi
  cp "$SRC/$f" "$DST/$f"
done

echo "synced ${#FILES[@]} preview-agent files from $SRC -> $DST"
