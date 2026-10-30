#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 10: let Telegram reach n8n, and NOTHING else
#
# Run ON THE VM as ubuntu:
#   bash 10-telegram-webhook.sh          open the webhook door
#   bash 10-telegram-webhook.sh --off    close it again (Telegram bot stops receiving)
#
# What it does:
#   - Publishes ONLY n8n's webhook paths (/webhook/..., /webhook-test/...) to the
#     internet with Tailscale Funnel on port 10000
#   - The n8n editor (:8443), Open WebUI (:443) and everything else stay PRIVATE
#   - Tells n8n its public webhook address (WEBHOOK_URL) and restarts it
# =============================================================================
set -euo pipefail

DIR="$HOME/lab/jarvis"
ENVF="$DIR/.env"
PORT=10000           # Funnel only allows 443, 8443 or 10000; 443 and 8443 are our private apps

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
restart_n8n() {
  docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d --force-recreate >/dev/null
  local w=0; until [ "$(health n8n)" = "healthy" ]; do
    (( w >= 180 )) && die "n8n didn't come back healthy: docker logs --tail 40 n8n"; sleep 5; w=$((w+5)); done
  echo "n8n restarted and healthy."
}

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
[ -f "$ENVF" ] || die "n8n isn't installed. Do Lesson 09 first."
TS_NAME=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
PRIVATE_URL="https://${TS_NAME}:8443/"
PUBLIC_URL="https://${TS_NAME}:${PORT}/"

# ---------- --off ----------
if [ "${1:-}" = "--off" ]; then
  step "Closing the public webhook door"
  sudo tailscale funnel --https=$PORT --set-path=/webhook off 2>/dev/null || true
  sudo tailscale funnel --https=$PORT --set-path=/webhook-test off 2>/dev/null || true
  env_set WEBHOOK_URL "$PRIVATE_URL"
  restart_n8n
  echo "Done. Nothing on this server is public any more. Telegram messages won't arrive until you open it again."
  exit 0
fi

# ---------- 1. funnel ----------
step "1/3  Publishing ONLY the webhook paths on ${PUBLIC_URL}"
echo "If a link appears saying Funnel isn't enabled, open it, click Enable, and run this script again."
sudo tailscale funnel --bg --https=$PORT --set-path=/webhook      http://127.0.0.1:5678/webhook
sudo tailscale funnel --bg --https=$PORT --set-path=/webhook-test http://127.0.0.1:5678/webhook-test
echo; tailscale funnel status 2>/dev/null | sed 's/^/  /'

# ---------- 2. tell n8n ----------
step "2/3  Telling n8n its public webhook address"
env_set WEBHOOK_URL "$PUBLIC_URL"
restart_n8n

# ---------- 3. check ----------
step "3/3  Checking what is reachable"
code_hook=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${PUBLIC_URL}webhook/free-ai-lab-door-check" || echo 000)
code_root=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${PUBLIC_URL}" || echo 000)
printf "  %-48s HTTP %s  (404 from n8n = the door works; no such workflow)\n" "${PUBLIC_URL}webhook/..." "$code_hook"
printf "  %-48s HTTP %s  (404 = good: the editor is NOT exposed here)\n" "${PUBLIC_URL}" "$code_root"
[ "$code_root" = "200" ] && warn "Something answers at the root of the public port. Run: bash $0 --off and check 'tailscale funnel status'."

step "Done!"
echo "  Public (internet):  ${PUBLIC_URL}webhook/...   ← only Telegram needs this"
echo "  Private (Tailscale): ${PRIVATE_URL}            ← n8n editor, unchanged"
echo
echo "Next: build the 'Jarvis chat' workflow in n8n (Lesson 10, Part D)."
echo "Close the door any time with:  bash $0 --off"
