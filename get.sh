#!/usr/bin/env bash
# ProductOwner in one line (Linux, macOS, or Git Bash on Windows; Docker must be installed):
#   curl -fsSL https://raw.githubusercontent.com/lotfy2125/productowner-install/main/get.sh | bash
#   … | bash -s -- --domain productowner.acme.com --email it@acme.com    on the internet instead
# Downloads the newest install files into ./productowner and runs ./install.sh. No questions: it sets up this
# network (office/home) by itself and prints the addresses to open.
set -euo pipefail
export MSYS_NO_PATHCONV=1
REPO="${PO_INSTALL_REPO:-lotfy2125/productowner-install}"
DIR="${PO_DIR:-productowner}"

if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
  echo "Docker isn't installed or isn't running."
  echo "  Linux:            curl -fsSL https://get.docker.com | sh"
  echo "  Windows / macOS:  install Docker Desktop (docker.com), start it, then run this again."
  exit 1
fi
mkdir -p "$DIR"
cd "$DIR"
if [ -f .env ]; then
  echo "ProductOwner is already installed in $(pwd). To update it: cd $(pwd) && ./update.sh"
  exit 0
fi
echo "Downloading ProductOwner's install files into $(pwd)…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/productowner-install.tar.gz" | tar xz --strip-components=1
chmod +x ./*.sh
exec ./install.sh "$@" </dev/tty
