#!/usr/bin/env bash
# Update ProductOwner: backs up first, then downloads and starts the new version.
#   ./update.sh            the newest version (PRODUCTOWNER_VERSION in .env, usually "latest")
#   ./update.sh 1.4.0      a given version (saved in .env)
#   ./update.sh --image-file productowner-1.4.0.tar   from a file (servers without internet)
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "No .env here: run ./install.sh first."; exit 1; }

FILE=""
if [ "${1:-}" = "--image-file" ]; then FILE="$2"; shift 2; fi
if [ -n "${1:-}" ]; then
  sed -i.bak "s/^PRODUCTOWNER_VERSION=.*/PRODUCTOWNER_VERSION=$1/" .env && rm -f .env.bak
fi

echo "Backing up first…"
./backup.sh
if [ -n "$FILE" ]; then docker load -i "$FILE"; else docker compose pull; fi
docker compose up -d
docker image prune -f >/dev/null
echo "Updated. The database is brought up to date when the app starts (docker compose logs app)."
