#!/usr/bin/env bash
# Deploy a test build for friends to Railway (a private link, not Rive's public page).
#
#   scripts/deploy-railway.sh      # needs `railway login` and `railway link` once
#
# Signs the game with `--publish=local` (as web-dev.sh does), copies the web harness
# and the .riv into deploy/site/, and uploads only deploy/ (Dockerfile + Caddyfile).
# Never `--publish=web` here: that is Rive's public release (docs/TECH_SPEC.md §8).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIVE="${RIVE:-$HOME/.rive/bin/rive}"
SITE="$ROOT/deploy/site"

"$RIVE" "$ROOT/game" --publish=local

rm -rf "$SITE"
mkdir -p "$SITE/web" "$SITE/game/build"
cp "$ROOT/web/index.html" "$ROOT/web/main.js" "$SITE/web/"
cp "$ROOT/game/build/count-echula.riv" "$SITE/game/build/"
# a clean screen for testers: no corner readout (?hud=1 brings it back)
sed -i -e 's|<title>Count Echula — local</title>|<title>Count Echula — test build</title>|' \
    -e 's|<body>|<body data-hud="0">|' "$SITE/web/index.html"

cd "$ROOT"
# --no-gitignore: site/ is git-ignored, but it is exactly what has to go up
railway up deploy --path-as-root --no-gitignore --ci
