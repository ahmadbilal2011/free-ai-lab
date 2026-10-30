#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 10: make sure NOTHING on the server is public
#
# Run ON THE VM as ubuntu:   bash 10-close-public-door.sh
#
# Undoes the earlier (withdrawn) version of Lesson 10 that published n8n's
# webhook paths with Tailscale Funnel. After this:
#   - no Tailscale Funnel at all (nothing reachable from the internet)
#   - n8n editor private on https://<tailscale-name>:9443
#   - n8n restarted with the latest settings
# Jarvis receives Telegram messages by ASKING Telegram (polling), built in the n8n UI.
# Safe to run even if you never ran the old script.
# =============================================================================
set -euo pipefail

DIR="$HOME/lab/jarvis"
ENVF="$DIR/.env"
EDITOR=9443
RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
[ -f "$ENVF" ] || die "n8n isn't installed. Do Lesson 09 first."
TS_NAME=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
EDITOR_URL="https://${TS_NAME}:${EDITOR}/"

step "1/3  Removing every public Funnel door"
for port in 10000 8443; do
  sudo tailscale funnel --https=$port --set-path=/webhook off      >/dev/null 2>&1 || true
  sudo tailscale funnel --https=$port --set-path=/webhook-test off >/dev/null 2>&1 || true
  sudo tailscale funnel --https=$port off >/dev/null 2>&1 || true
  sudo tailscale serve  --https=$port off >/dev/null 2>&1 || true   # old editor/door ports
done
if tailscale funnel status 2>/dev/null | grep -qi "funnel on"; then
  warn "Something is still public:"; tailscale funnel status
else
  echo "No Funnel: nothing on this server is reachable from the internet."
fi

step "2/3  n8n editor: private on :${EDITOR}"
sudo tailscale serve --bg --https=$EDITOR 5678 >/dev/null
env_set WEBHOOK_URL "$EDITOR_URL"
curl -fsSL "$RAW/stacks/jarvis/compose.yaml" -o "$DIR/compose.yaml"
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d --force-recreate >/dev/null
w=0; until [ "$(health n8n)" = "healthy" ]; do
  (( w >= 180 )) && die "n8n didn't come back healthy: docker logs --tail 40 n8n"; sleep 5; w=$((w+5)); done
echo "n8n restarted and healthy."

step "3/3  What is published now (all Tailscale-only)"
tailscale serve status 2>/dev/null | sed 's/^/  /'

step "Done!"
echo -e "  n8n editor (Tailscale only):  ${c_ok}${EDITOR_URL}${c_off}   ← update your bookmark"
echo "  Next: build the 'Jarvis chat' workflow in the n8n UI (Lesson 10)."
