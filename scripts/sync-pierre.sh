#!/usr/bin/env bash
# Vendor crit's code renderer into crit-web, byte-identical.
#
# crit renders code with @pierre/diffs (Shiki in a worker pool) and themes the
# review UI from the selected Shiki theme. crit-web uses the same build and the
# same modules so both review pages highlight and theme code identically. The
# build is never re-run here: grammar set, themes and palettes come from crit.
#
# Copies:
#   crit/web/pierre/*.js.gz      -> priv/static/pierre/   (served gzip, see
#                                   CritWeb.Plugs.Precompressed)
#   crit/web/<modules> + crit-palette.css -> assets/vendor/crit/ (bundled)
#
# When crit changes any of these, re-run this script and commit the result.
# test/crit_web/pierre_sync_test.exs fails on drift.
#
# Usage: scripts/sync-pierre.sh [SRC_DIR]
#   SRC_DIR defaults to <repo>/../crit/web
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
SRC="${1:-$ROOT/../crit/web}"

# Keep in sync with @bundled_modules in test/crit_web/pierre_sync_test.exs.
# crit-theme-palette.js is not vendored: crit-web renders the palette on the
# server (CritWeb.ThemePalette) from the same palettes.js.
BUNDLED=(
  crit-code-highlight.js
  crit-pierre-adapter.js
  crit-pierre-dom.js
  crit-pierre-runtime.js
  crit-theme-boost.js
  crit-palette.css
)

if [[ ! -d "$SRC/pierre" ]]; then
  echo "error: source dir not found: $SRC/pierre" >&2
  exit 1
fi

PIERRE_DST="$ROOT/priv/static/pierre"
rm -rf "$PIERRE_DST"
mkdir -p "$PIERRE_DST"
cp "$SRC"/pierre/*.js.gz "$PIERRE_DST/"

mkdir -p "$ROOT/assets/vendor/crit"
for f in "${BUNDLED[@]}"; do
  cp "$SRC/$f" "$ROOT/assets/vendor/crit/$f"
done

count=$(find "$PIERRE_DST" -name '*.js.gz' | wc -l | tr -d ' ')
echo "synced $count pierre files and ${#BUNDLED[@]} modules from $SRC"
