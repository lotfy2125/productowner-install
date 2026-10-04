#!/usr/bin/env bash
# ProductOwner installer: asks a few questions, writes .env with fresh secrets, starts everything.
#   ./install.sh                                     no questions: this network (office/home), meetings on
#   ./install.sh --domain po.acme.com --email it@acme.com   on the internet, at that DNS name
# Switch an existing install to a DNS name later: ./set-domain.sh po.acme.com it@acme.com
# Other options: --no-meetings  --meet-domain NAME  --image NAME  --version TAG  --image-file productowner.tar
set -euo pipefail
# Git Bash on Windows (for trying it out) would turn container paths like /data into Windows paths.
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")"

DOMAIN="" EMAIL="" MEET="" MEETINGS=yes IMAGE="" VERSION="" IMAGE_FILE="" YES=no LOCAL=""
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
    --local) LOCAL=yes ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
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
# This computer's address on the local network (the one with the default route; not Docker's or VPN's virtual ones).
lan_ip() {
  local ip=""
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
      ip=$(powershell.exe -NoProfile -Command "(Get-NetIPConfiguration | Where-Object { \$_.IPv4DefaultGateway -ne \$null -and \$_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1).IPv4Address.IPAddress" 2>/dev/null | tr -d '\r ' | head -1) ;;
    Darwin) ip=$(ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')" 2>/dev/null || true) ;;
    *) ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}' | head -1)
      [ -n "$ip" ] || ip=$(hostname -I 2>/dev/null | awk '{print $1}') ;;
  esac
  echo "$ip"
}
on_windows() { case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) return 0 ;; *) return 1 ;; esac; }

secret() { if command -v openssl >/dev/null; then openssl rand -hex "${1:-32}"; else head -c "${1:-32}" /dev/urandom | od -An -tx1 | tr -d ' \n'; fi; }

say "ProductOwner install"
command -v docker >/dev/null || { echo "Docker isn't installed. On Ubuntu/Debian: curl -fsSL https://get.docker.com | sh   then run this again."; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose (the 'docker compose' plugin) is missing. Install docker-compose-plugin, then run this again."; exit 1; }

if [ -f .env ]; then
  echo "This folder already has settings (.env). Starting ProductOwner with them; edit .env to change anything."
else
  # No DNS name given: this network (office or home). Nothing to answer.
  [ -n "$DOMAIN" ] || LOCAL=yes
  if [ -n "$LOCAL" ]; then
    # Found by itself; asked only when it can't be found.
    IP=$(lan_ip)
    [ -n "$IP" ] || IP=$(ask "Couldn't find this computer's network address. Type the IPv4 Address that ipconfig shows" "")
    # Only numbers like 192.168.1.20 work here; ask again for anything else.
    while ! printf '%s' "$IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; do
      [ "$YES" = no ] || { echo "Couldn't find this computer's address. Run ./install.sh --local and type it (ipconfig shows it)."; exit 1; }
      echo "That isn't an address like 192.168.1.20. Press Enter to use the one shown, or type the IPv4 Address from ipconfig."
      IP=$(ask "This computer's address on the network" "$(lan_ip)")
    done
    DOMAIN=$IP
    EMAIL=${EMAIL:-admin@localhost}
  fi
  [ -n "$DOMAIN" ] || DOMAIN=$(ask "Address people will open (a DNS name pointing at this server)" "productowner.$(hostname -d 2>/dev/null || echo example.com)")
  [ -n "$EMAIL" ] || EMAIL=$(ask "Your email, for HTTPS certificate notices" "admin@${DOMAIN#*.}")
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
    if [ -n "$LOCAL" ]; then
      echo "# This network only: HTTPS with ProductOwner's own certificate (browsers ask once), video server at this address."
      echo "LOCAL=yes"
      # Names it also answers to: productowner.local (announced on Linux), the computer's name, localhost.
      HOST=$(hostname 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
      echo "LOCAL_NAME=productowner.local"
      echo "EXTRA_NAMES=productowner.local localhost${HOST:+ $HOST $HOST.local}"
      # Windows often reserves port 80; it only redirects http:// to https://, so another port is fine here.
      if on_windows; then echo "HTTP_PORT=8080"; fi
    fi
    # On Linux a this-network install announces productowner.local (Docker Desktop on Windows/macOS can't).
    PROFILES=""
    [ "$MEETINGS" = yes ] && PROFILES="meetings"
    if [ -n "$LOCAL" ] && [ "$(uname -s)" = Linux ] && ! grep -qi microsoft /proc/version 2>/dev/null; then PROFILES="${PROFILES:+$PROFILES,}name"; fi
    if [ "$MEETINGS" = yes ]; then
      echo "COMPOSE_PROFILES=$PROFILES"
      # The video server answers on the same address (Caddy sends /rtc to it). Set MEET_DOMAIN only for a separate name.
      echo "MEET_DOMAIN=${MEET:-}"
      if [ -n "$MEET" ]; then echo "LIVEKIT_PUBLIC_URL=wss://$MEET"; else echo "LIVEKIT_PUBLIC_URL=same-address"; fi
      echo "LIVEKIT_API_KEY=PO$(secret 6)"
      echo "LIVEKIT_API_SECRET=$(secret 32)"
    else
      echo "COMPOSE_PROFILES=$PROFILES"
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
mkdir -p caddy/sites caddy/site
if [ "$(val LOCAL)" = yes ]; then
  # No public name, so no Let's Encrypt: Caddy signs its own certificate. The video server announces this address.
  printf '# This network only (install.sh --local).\ntls internal\n' > caddy/site/local.caddy
  sed -i.bak -E "s/^( *)#? *node_ip:.*/\1node_ip: $DOMAIN/; s/^( *)use_external_ip:.*/\1use_external_ip: false/" livekit.yaml && rm -f livekit.yaml.bak
  if on_windows && ! powershell.exe -NoProfile -Command "if (Get-NetFirewallRule -DisplayName 'ProductOwner' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" >/dev/null 2>&1; then
    say "Letting other computers in (Windows asks for permission)"
    powershell.exe -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-Command','New-NetFirewallRule -DisplayName ProductOwner -Direction Inbound -Protocol TCP -LocalPort 443,7881,8080 -Action Allow; New-NetFirewallRule -DisplayName ProductOwner -Direction Inbound -Protocol UDP -LocalPort 443,7882 -Action Allow'" >/dev/null 2>&1 \
      || echo "Couldn't add the firewall rule. Other computers may not reach this one: allow TCP 443, 7881 and UDP 7882 in Windows Firewall."
  fi
else
  rm -f caddy/site/local.caddy
fi
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
if [ "$(val LOCAL)" = yes ]; then
  cat <<MSG
  ProductOwner's address on this network:
$(case ",$(val COMPOSE_PROFILES)," in *,name,*) printf '    https://%s      (or https://%s)' "$(val LOCAL_NAME)" "$DOMAIN" ;; *) printf '    https://%s' "$DOMAIN" ;; esac)
  Everyone on the same network opens it in a browser. Invite links (Settings → Team) already point there, and
  Settings → Team shows the address to share.
  The browser warns once ("not private"): click Advanced, then Proceed. That's because this is ProductOwner's own
  certificate, which is fine on your own network.
  The first person to open it creates the admin account.

  Every night: ./backup.sh
  New version:  ./update.sh
MSG
  exit 0
fi
cat <<MSG
  Open https://$DOMAIN and create the first admin account (the first person to open it does this).

  Check that:
  - $DOMAIN${MEET_DOMAIN:+ and $MEET_DOMAIN} point at this server's public address (DNS A record);
  - the firewall lets in TCP 80 and 443$(case ",$(val COMPOSE_PROFILES)," in *,meetings,*) echo ", TCP 7881 and UDP 7882 (meetings)" ;; esac).

  Every night: ./backup.sh  (e.g. in cron: 30 2 * * * $(pwd)/backup.sh)
  New version:  ./update.sh            (or ./update.sh 1.4.0 for a given version)
MSG
