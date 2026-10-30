#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 09: n8n, Jarvis's automation engine
#
# Run ON THE VM as ubuntu (no sudo; it asks sudo for the few steps that need it):
#   bash 09-install-n8n.sh
#
# What it does:
#   1. Creates ~/lab/jarvis with a data folder owned by the container user (1000)
#   2. Writes a private .env (random encryption key, your Tailscale name)
#   3. Starts n8n on 127.0.0.1:5678 and waits until it's healthy
#   4. Publishes the editor privately with Tailscale HTTPS on port 8443
#   5. Adds n8n to the nightly backup (paused a few seconds for a clean copy)
#   6. Prints the gateway details you'll paste into n8n's credential
#
# Safe to re-run (also how you update n8n).
# =============================================================================
set -euo pipefail

RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
DIR="$HOME/lab/jarvis"
ENVF="$DIR/.env"
TS_PORT=8443

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_get() { grep -E "^$1=" "$ENVF" 2>/dev/null | head -1 | cut -d= -f2- || true; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
docker ps >/dev/null 2>&1 || die "Docker isn't usable without sudo. Finish Lesson 03 first."
docker network inspect ai_default >/dev/null 2>&1 || die "The AI stack isn't running (Lesson 04): cd ~/lab/ai && docker compose up -d"
[ "$(health litellm)" = "healthy" ] || warn "The gateway (litellm) isn't healthy right now. n8n will install, but AI nodes need it (Lesson 07)."

# ---------- 1. folders ----------
step "1/6  Preparing ~/lab/jarvis"
mkdir -p "$DIR/n8n"
sudo chown -R 1000:1000 "$DIR/n8n"          # the n8n container runs as user 'node' (1000)
curl -fsSL "$RAW/stacks/jarvis/compose.yaml" -o "$DIR/compose.yaml"

# ---------- 2. settings ----------
step "2/6  Private settings (.env)"
command -v tailscale >/dev/null || die "Tailscale isn't installed. Do Lesson 05 first."
TS_NAME=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
[ -n "$TS_NAME" ] || die "Couldn't read your Tailscale name. Is Tailscale connected? (tailscale status)"
umask 077; touch "$ENVF"; chmod 600 "$ENVF"; umask 022
NEW_KEY=""
if [ -z "$(env_get N8N_ENCRYPTION_KEY)" ]; then
  NEW_KEY=$(openssl rand -hex 16)          # 32 characters
  env_set N8N_ENCRYPTION_KEY "$NEW_KEY"
fi
env_set TS_NAME "$TS_NAME"
[ -n "$(env_get WEBHOOK_URL)" ] || env_set WEBHOOK_URL "https://${TS_NAME}:${TS_PORT}/"
echo "Editor address: https://${TS_NAME}:${TS_PORT}"

# ---------- 3. start ----------
step "3/6  Starting n8n (first download is a few hundred MB)"
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" pull -q
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d
waited=0
until [ "$(health n8n)" = "healthy" ]; do
  (( waited >= 240 )) && { docker logs --tail 40 n8n; die "n8n didn't become healthy. See the logs above."; }
  printf "  waiting for n8n (%s, %ss)...\r" "$(health n8n)" "$waited"; sleep 10; waited=$((waited + 10))
done
echo "n8n $(docker exec n8n n8n --version 2>/dev/null || echo '?') is healthy.            "

# ---------- 4. tailscale ----------
step "4/6  Publishing the editor privately over Tailscale HTTPS (port ${TS_PORT})"
sudo tailscale serve --bg --https="$TS_PORT" 5678 >/dev/null
tailscale serve status 2>/dev/null | sed 's/^/  /'

# ---------- 5. backups ----------
step "5/6  Adding n8n to the nightly backup"
BCONF=/etc/free-ai-lab/backup.env
if sudo test -f "$BCONF"; then
  if sudo grep -qE '^BACKUP_STOP=.*\bn8n\b' "$BCONF"; then
    echo "Already included."
  else
    sudo sed -i -E 's/^BACKUP_STOP="([^"]*)"/BACKUP_STOP="\1 n8n"/' "$BCONF"
    echo "Done: ~/lab/jarvis is backed up, and n8n pauses a few seconds at 03:30 for a clean copy."
  fi
else
  warn "Backups aren't installed (Lesson 08). n8n's data will be included once they are."
fi

# ---------- 6. what to paste into n8n ----------
step "6/6  Gateway details for n8n's credential (Lesson 09, Part D)"
echo "  Base URL : http://litellm:4000/v1"
echo "  API key  : show it with   grep LITELLM_MASTER_KEY ~/lab/gateway/.env"
echo "  Models   : smart, fast, private"

if [ -n "$NEW_KEY" ]; then
  echo
  echo -e "${c_warn}=================== SAVE THIS NOW ===================${c_off}"
  echo -e "  n8n encryption key:  ${c_ok}${NEW_KEY}${c_off}"
  echo "  n8n encrypts every saved credential (API keys, tokens) with it."
  echo "  It's in ~/lab/jarvis/.env and in your nightly backups, but keep a"
  echo "  copy in your password manager too. NOT on GitHub."
  echo -e "${c_warn}=====================================================${c_off}"
fi
unset NEW_KEY

step "Done!"
echo -e "  Open (Tailscale on):  ${c_ok}https://${TS_NAME}:${TS_PORT}${c_off}"
echo "  Create the OWNER account right away: the first person to open it becomes the owner."
