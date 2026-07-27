#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:?usage: backup-postgres.sh APP_DIR [COMPOSE_FILE]}"
COMPOSE_FILE="${2:-compose.production.yml}"
DB_SERVICE="${DB_SERVICE:-db}"
DB_USER="${POSTGRES_USER:-app}"
DB_NAME="${POSTGRES_DB:-app}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
BACKUP_DIR="${BACKUP_DIR:-$APP_DIR/backups}"

mkdir -p "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
cd "$APP_DIR/current"
docker compose -f "$COMPOSE_FILE" --env-file .env exec -T "$DB_SERVICE" \
  pg_dump -U "$DB_USER" -d "$DB_NAME" | gzip -9 > "$BACKUP_DIR/${DB_NAME}-${timestamp}.sql.gz"
find "$BACKUP_DIR" -type f -name '*.sql.gz' -mtime "+$RETENTION_DAYS" -delete
echo "$BACKUP_DIR/${DB_NAME}-${timestamp}.sql.gz"
