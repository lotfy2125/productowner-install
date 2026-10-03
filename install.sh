#!/usr/bin/env bash
# ProductOwner installer: asks a few questions, writes .env with fresh secrets, starts everything.
#   ./install.sh                         answers the questions here
#   ./install.sh --domain po.acme.com --email it@acme.com --yes   no questions (meetings on, meet.<domain>)
# Other options: --no-meetings  --meet-domain NAME  --image NAME  --version TAG  --image-file productowner.tar
set -euo pipefail
# Git Bash on Windows (for trying it out) would turn container paths like /data into Windows paths.
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"

DOMAIN="" EMAIL="" MEET="" MEETINGS=yes IMAGE="" VERSION="" IMAGE_FILE="" YES=no
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift ;;
    --email) EMAIL="$2"; shift ;;
    --meet-domain) MEET="$2"; shift ;;
    --no-meetings) MEETINGS=no ;;
    --image) IMAGE="$2"; shift ;;
    --version) VERSION="$2"; shift ;;
    --image-file) IMAGE_FILE="$2"; shift ;;
    --yes|-y) YES=yes ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ask() { # ask "Question" default -> answer
  local a
  if [ "$YES" = yes ]; then echo "$2"; return; fi
  read -r -p "$1 [$2]: " a </dev/tty || true
  echo "${a:-$2}"
}
secret() { if command -v openssl >/dev/null; then openssl rand -hex "${1:-32}"; else head -c "${1:-32}" /dev/urandom | od -An -tx1 | tr -d ' \n'; fi; }

say "ProductOwner install"
command -v docker >/dev/null || { echo "Docker isn't installed. On Ubuntu/Debian: curl -fsSL https://get.docker.com | sh   then run this again."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose (the 'docker compose' plugin) is missing. Install docker-compose-plugin, then run this again."; exit 1; }

if [ -f .env ]; then
  echo "This folder already has settings (.env). Starting ProductOwner with them; edit .env to change anything."
else
  [ -n "$DOMAIN" ] || DOMAIN=$(ask "Address people will open (a DNS name pointing at this server)" "productowner.$(hostname -d 2>/dev/null || echo example.com)")
  [ -n "$EMAIL" ] || EMAIL=$(ask "Your email, for HTTPS certificate notices" "admin@${DOMAIN#*.}")
  if [ "$YES" = no ] && [ "$MEETINGS" = yes ]; then
    case "$(ask "Turn on meetings (video, screen share, recording)? Needs a second DNS name and UDP ports" "yes")" in [Nn]*) MEETINGS=no ;; esac
  fi
  if [ "$MEETINGS" = yes ] && [ -z "$MEET" ]; then MEET=$(ask "Address for the video server" "meet.$DOMAIN"); fi
  [ -n "$IMAGE" ] || IMAGE=$(grep -E '^PRODUCTOWNER_IMAGE=' .env.example | cut -d= -f2-)
  [ -n "$VERSION" ] || VERSION=latest

  umask 077
  {
    echo "# Written by install.sh on $(date -u +%Y-%m-%dT%H:%MZ). Keep a copy of this file somewhere safe."
    echo "DOMAIN=$DOMAIN"
    echo "ACME_EMAIL=$EMAIL"
    echo "PRODUCTOWNER_IMAGE=$IMAGE"
    echo "PRODUCTOWNER_VERSION=$VERSION"
    echo "POSTGRES_PASSWORD=$(secret 24)"
    echo "PO_SECRET=$(secret 32)"
    if [ "$MEETINGS" = yes ]; then
      echo "COMPOSE_PROFILES=meetings"
      echo "MEET_DOMAIN=$MEET"
      echo "LIVEKIT_PUBLIC_URL=wss://$MEET"
      echo "LIVEKIT_API_KEY=PO$(secret 6)"
      echo "LIVEKIT_API_SECRET=$(secret 32)"
    else
      echo "COMPOSE_PROFILES="
      echo "MEET_DOMAIN="
      echo "LIVEKIT_PUBLIC_URL="
    fi
    echo
    echo "# Email: without it, emails go to the app log (docker compose logs app)."
    echo "# SMTP_URL=smtps://user:password@smtp.example.com:465"
    echo "# EMAIL_FROM=ProductOwner <noreply@$DOMAIN>"
    echo "# PO agent with Claude:"
    echo "# ANTHROPIC_API_KEY=sk-ant-..."
  } > .env
  umask 022
  echo "Settings saved in .env (secrets made fresh for this install)."
fi

# Read settings without running .env as a script (values may contain spaces or <>).
val() { grep -E "^$1=" .env | tail -1 | cut -d= -f2- || true; }
MEET_DOMAIN=$(val MEET_DOMAIN); DOMAIN=$(val DOMAIN); PRODUCTOWNER_VERSION=$(val PRODUCTOWNER_VERSION)
mkdir -p caddy/sites
if [ -n "${MEET_DOMAIN:-}" ]; then
  printf '%s {\n\treverse_proxy livekit:7880\n}\n' "$MEET_DOMAIN" > caddy/sites/meet.caddy
else
  rm -f caddy/sites/meet.caddy
fi

if [ -n "$IMAGE_FILE" ]; then
  say "Loading the ProductOwner image from $IMAGE_FILE"
  docker load -i "$IMAGE_FILE"
else
  say "Downloading ProductOwner $PRODUCTOWNER_VERSION"
  docker compose pull
fi

say "Starting"
docker compose up -d

printf 'Waiting for ProductOwner to be ready'
for _ in $(seq 1 60); do
  if [ "$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q app)" 2>/dev/null)" = healthy ]; then ok=1; break; fi
  printf '.'; sleep 3
done
echo
if [ "${ok:-0}" != 1 ]; then echo "It's taking long. See what it says: docker compose logs app"; exit 1; fi

say "ProductOwner is running."
cat <<MSG
  Open https://$DOMAIN and create the first admin account (the first person to open it does this).

  Check that:
  - $DOMAIN${MEET_DOMAIN:+ and $MEET_DOMAIN} point at this server's public address (DNS A record);
  - the firewall lets in TCP 80 and 443${MEET_DOMAIN:+, TCP 7881 and UDP 7882 (meetings)}.

  Every night: ./backup.sh  (e.g. in cron: 30 2 * * * $(pwd)/backup.sh)
  New version:  ./update.sh            (or ./update.sh 1.4.0 for a given version)
MSG
