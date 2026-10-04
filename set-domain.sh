#!/usr/bin/env bash
# Move this install from "this network only" to the internet, at a DNS name pointing at this server:
#   ./set-domain.sh productowner.acme.com it@acme.com
# Real HTTPS certificates come from Let's Encrypt by themselves (ports 80 and 443 must be open to the internet).
# Your data stays. Old local addresses stop working; people open https://<the new name>.
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"
NAME="${1:-}"; EMAIL="${2:-}"
if [ -z "$NAME" ] || [ -z "$EMAIL" ]; then sed -n '2,5p' "$0"; exit 2; fi
[ -f .env ] || { echo "Install first: ./install.sh"; exit 1; }
cp .env ".env.before-$(date +%Y%m%d-%H%M%S)"
sed -i.bak -E "s#^DOMAIN=.*#DOMAIN=$NAME#; s#^ACME_EMAIL=.*#ACME_EMAIL=$EMAIL#; /^(LOCAL|EXTRA_NAMES|HTTP_PORT)=/d" .env && rm -f .env.bak
rm -f caddy/site/local.caddy
sed -i.bak -E "s/^( *)node_ip:.*/\1# node_ip: 192.168.1.20/; s/^( *)use_external_ip:.*/\1use_external_ip: true/" livekit.yaml && rm -f livekit.yaml.bak
docker compose up -d
docker compose restart caddy livekit
echo
echo "Done. Open https://$NAME (it can take a minute for the certificate)."
echo "Check: $NAME points at this server's public address, and ports 80, 443, TCP 7881, UDP 7882 are open."
