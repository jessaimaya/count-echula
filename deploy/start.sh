#!/bin/sh
# Railway container: the stats api (restarted if it ever exits) next to Caddy.
(while true; do python3 /app/api.py; echo "stats api exited; restarting" >&2; sleep 2; done) &
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
