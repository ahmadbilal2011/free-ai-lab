#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — tidy the server (safe to run any time)
#
# Run ON THE VM as ubuntu (no sudo):
#   bash cleanup-lab.sh
#
# REMOVES:  the Lesson 03 practice stack (~/lab/hello), the web-test container,
#           downloaded copies of lesson scripts in your home folder,
#           Docker images no running container uses (hello-world, busybox, nginx…)
#           and Docker build cache.
# NEVER TOUCHES: Docker volumes (your chats, users, AI models), ~/lab/ai,
#           ~/lab/gateway (your keys), ~/lab/autoheal, Tailscale.
# =============================================================================
set -euo pipefail

c_ok="\033[32m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }

[ "$(id -u)" -ne 0 ] || { echo "Run WITHOUT sudo: bash $0"; exit 1; }

BEFORE=$(df -BM --output=used / | tail -1 | tr -dc '0-9')

step "1/4  Removing the Lesson 03 practice stack"
if [ -f "$HOME/lab/hello/compose.yaml" ]; then
  docker compose -f "$HOME/lab/hello/compose.yaml" down 2>/dev/null || true
  rm -rf "$HOME/lab/hello"
  echo "Removed ~/lab/hello"
else
  echo "Nothing to remove."
fi
docker rm -f web-test >/dev/null 2>&1 && echo "Removed container web-test" || true

step "2/4  Removing downloaded copies of lesson scripts (they're always on GitHub)"
shopt -s nullglob
for f in "$HOME"/0[0-9]-*.sh "$HOME"/create-free-vm.sh; do
  rm -f "$f"; echo "Removed $(basename "$f")"
done
shopt -u nullglob

step "3/4  Removing unused Docker images and build cache (volumes are kept)"
docker image prune -af
docker builder prune -f >/dev/null 2>&1 || true

step "4/4  What's running now"
docker ps --format 'table {{.Names}}\t{{.Status}}'
echo
echo "Volumes kept (your data):"
docker volume ls --format '  {{.Name}}'
AFTER=$(df -BM --output=used / | tail -1 | tr -dc '0-9')
echo
echo "Disk freed: $(( (BEFORE - AFTER) )) MB.  Free now: $(df -h --output=avail / | tail -1 | tr -d ' ')"
echo
echo "Tip: this script deletes itself too. Download it again from GitHub when needed."
rm -f "$0" 2>/dev/null || true
