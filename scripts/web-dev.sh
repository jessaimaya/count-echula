#!/usr/bin/env bash
# Local browser testing: signed build to disk + static server on the LAN.
#
#   scripts/web-dev.sh [project-dir] [port]     (default: game 8000)
#
# Uses `--publish=local` ONLY: the scripts are signed by Rive's compile
# service and the .riv is written to <project>/build/. Nothing goes public.
# Do NOT use `--publish=web` until the release step (see docs/TECH_SPEC.md §8).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIVE="${RIVE:-$HOME/.rive/bin/rive}"
PROJECT="${1:-game}"
PORT="${2:-8000}"

NAME="$(sed -n 's/^name:[[:space:]]*//p' "$ROOT/$PROJECT/rive.yaml" | head -1 | tr -d '"')"
"$RIVE" "$ROOT/$PROJECT" --publish=local

IP="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
URL_PATH="/web/?src=/$PROJECT/build/$NAME.riv"
echo
echo "  desktop: http://localhost:$PORT$URL_PATH"
[ -n "$IP" ] && echo "  phone:   http://$IP:$PORT$URL_PATH   (same Wi-Fi)"
echo "  rebuild: rerun '$RIVE $PROJECT --publish=local' and reload the page"
echo

exec python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$ROOT"
