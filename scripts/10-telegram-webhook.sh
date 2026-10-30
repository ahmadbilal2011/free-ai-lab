#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 10: let Telegram reach n8n, and NOTHING else
#
# Run ON THE VM as ubuntu:
#   bash 10-telegram-webhook.sh          open the webhook door
#   bash 10-telegram-webhook.sh --off    close it again (Telegram bot stops receiving)
#
# Port layout (Telegram only delivers to 443, 80, 88 or 8443; Funnel only allows
# 443, 8443 or 10000 — so the public door must be 443 or 8443):
#   :443   Open WebUI          private (Tailscale only)
#   :8443  n8n /webhook paths  PUBLIC  (only these paths; nothing else on this port)
#   :9443  n8n editor          private (Funnel can't publish 9443 at all)
#
# Safe to re-run. Also cleans up the first version of this lesson
# (editor on :8443, webhook door on :10000).
# =============================================================================
set -euo pipefail

DIR="$HOME/lab/jarvis"
ENVF="$DIR/.env"
DOOR=8443
EDITOR=9443

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
restart_n8n() {
  curl -fsSL "${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}/stacks/jarvis/compose.yaml" -o "$DIR/compose.yaml"
  docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d --force-recreate >/dev/null
  local w=0; until [ "$(health n8n)" = "healthy" ]; do
    (( w >= 180 )) && die "n8n didn't come back healthy: docker logs --tail 40 n8n"; sleep 5; w=$((w+5)); done
  echo "n8n restarted and healthy."
}

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
[ -f "$ENVF" ] || die "n8n isn't installed. Do Lesson 09 first."
TS_NAME=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
EDITOR_URL="https://${TS_NAME}:${EDITOR}/"
PUBLIC_URL="https://${TS_NAME}:${DOOR}/"

# ---------- clean up the first version of this lesson ----------
sudo tailscale funnel --https=10000 --set-path=/webhook off      >/dev/null 2>&1 || true
sudo tailscale funnel --https=10000 --set-path=/webhook-test off >/dev/null 2>&1 || true
sudo tailscale serve  --https=10000 off >/dev/null 2>&1 || true

# ---------- --off ----------
if [ "${1:-}" = "--off" ]; then
  step "Closing the public webhook door"
  sudo tailscale funnel --https=$DOOR off >/dev/null 2>&1 || true
  sudo tailscale serve  --https=$DOOR off >/dev/null 2>&1 || true
  env_set WEBHOOK_URL "$EDITOR_URL"
  restart_n8n
  echo "Done. Nothing on this server is public any more. Telegram messages won't arrive until you open it again."
  exit 0
fi

# ---------- 1. editor stays private, on its own port ----------
step "1/4  n8n editor: private on :${EDITOR}"
sudo tailscale serve --https=$DOOR off >/dev/null 2>&1 || true      # remove the old editor (or anything else) from :8443
sudo tailscale serve --bg --https=$EDITOR 5678 >/dev/null
echo "Editor: ${EDITOR_URL}   (Tailscale only)"

# ---------- 2. the door: only webhook paths on :8443 ----------
step "2/4  Publishing ONLY n8n's webhook paths on ${PUBLIC_URL}"
echo "If a link appears saying Funnel isn't enabled, open it, click Enable, and run this script again."
sudo tailscale funnel --bg --https=$DOOR --set-path=/webhook      http://127.0.0.1:5678/webhook
sudo tailscale funnel --bg --https=$DOOR --set-path=/webhook-test http://127.0.0.1:5678/webhook-test
echo; tailscale funnel status 2>/dev/null | sed 's/^/  /'

# ---------- 3. tell n8n ----------
step "3/4  Telling n8n its public webhook address"
env_set WEBHOOK_URL "$PUBLIC_URL"
restart_n8n

# ---------- 4. check ----------
step "4/4  Checking what is reachable"
code_hook=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${PUBLIC_URL}webhook/free-ai-lab-door-check" || echo 000)
code_root=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${PUBLIC_URL}" || echo 000)
code_edit=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${EDITOR_URL}" || echo 000)
printf "  %-46s HTTP %s  (404 from n8n = the door works; no such workflow)\n" "${PUBLIC_URL}webhook/..." "$code_hook"
printf "  %-46s HTTP %s  (404 = good: the editor is NOT on the public port)\n" "${PUBLIC_URL}" "$code_root"
printf "  %-46s HTTP %s  (200 = editor works privately)\n" "${EDITOR_URL}" "$code_edit"
[ "$code_root" = "200" ] && warn "Something answers at the root of the public port! Run: bash $0 --off  and send the output of: tailscale funnel status"

step "Done!"
echo "  Public  (internet):   ${PUBLIC_URL}webhook/...   ← only Telegram needs this"
echo -e "  Private (Tailscale):  ${c_ok}${EDITOR_URL}${c_off}   ← n8n editor: NEW address, update your bookmark"
echo
echo "Next: build the 'Jarvis chat' workflow in n8n (Lesson 10, Part D)."
echo "Close the door any time with:  bash $0 --off"
