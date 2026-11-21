#!/usr/bin/env sh
# Dumps the PostgreSQL database to backups/ and keeps the last 7 days.
# Run from the repository root on the server, e.g. from cron:
#   0 4 * * * cd /opt/property-aggregator && ./scripts/backup-db.sh >> backups/backup.log 2>&1
set -eu

cd "$(dirname "$0")/.."
. ./.env

mkdir -p backups
file="backups/${POSTGRES_DB}-$(date +%Y%m%d-%H%M%S).dump"

docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom > "$file"
echo "$(date -Iseconds) saved $file ($(du -h "$file" | cut -f1))"

find backups -name "${POSTGRES_DB}-*.dump" -mtime +7 -delete
