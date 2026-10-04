# Count Echula test build for friends: Caddy serves the web harness and the signed .riv;
# a small Python api (deploy/api.py) stores play stats in SQLite on the /data volume.
# scripts/deploy-railway.sh fills site/ and uploads this folder.
FROM caddy:2-alpine
RUN apk add --no-cache python3
COPY Caddyfile /etc/caddy/Caddyfile
COPY api.py stats.html start.sh /app/
COPY site /srv
ENV STATS_DB=/data/stats.db
CMD ["/app/start.sh"]
