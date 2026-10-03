#!/usr/bin/env bash
# Back up ProductOwner: the database and the files (meeting recordings, transcripts, recaps).
#   ./backup.sh                  into ./backups/<date>, keeps the newest 14
#   KEEP=30 BACKUP_DIR=/mnt/nas ./backup.sh
# .env is NOT in the backup (it holds the secrets): keep a copy of it somewhere safe, apart from the backups.
set -euo pipefail
# Git Bash on Windows (for trying it out) would turn container paths like /data into Windows paths.
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"
DIR="${BACKUP_DIR:-./backups}/$(date +%Y%m%d-%H%M%S)"
KEEP="${KEEP:-14}"
mkdir -p "$DIR"

docker compose exec -T postgres pg_dump -U productowner -Fc productowner > "$DIR/database.dump"
docker compose exec -T app tar -C /data -czf - files > "$DIR/files.tar.gz"
docker compose exec -T app node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>r.json()).then(h=>console.log(h.version))" > "$DIR/version.txt" 2>/dev/null || true

echo "Backup: $DIR ($(du -sh "$DIR" | cut -f1))"
# Keep the newest $KEEP.
# shellcheck disable=SC2012 # backup folder names are dates
ls -1dt "${BACKUP_DIR:-./backups}"/*/ 2>/dev/null | tail -n +"$((KEEP + 1))" | xargs -r rm -rf
