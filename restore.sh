#!/usr/bin/env bash
# Put a backup back: ./restore.sh backups/20261002-023000
# Replaces the current database and files with the backup's. The .env must be the one from that install
# (PO_SECRET unlocks the saved tokens).
set -euo pipefail
cd "$(dirname "$0")"
DIR="${1:?Which backup? e.g. ./restore.sh backups/20261002-023000}"
[ -f "$DIR/database.dump" ] || { echo "No database.dump in $DIR"; exit 1; }
read -r -p "This replaces everything in ProductOwner with the backup from $DIR. Type RESTORE to go on: " ok </dev/tty
[ "$ok" = RESTORE ] || { echo "Stopped. Nothing changed."; exit 1; }

docker compose stop app
docker compose exec -T postgres pg_restore -U productowner -d productowner --clean --if-exists --no-owner < "$DIR/database.dump"
if [ -f "$DIR/files.tar.gz" ]; then
  docker compose run --rm -T --no-deps --entrypoint sh app -c "rm -rf /data/files && tar -C /data -xzf -" < "$DIR/files.tar.gz"
fi
docker compose start app
echo "Restored from $DIR."
