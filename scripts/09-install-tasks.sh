#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 09: Vikunja task manager
#
# Run ON THE VM as ubuntu (no sudo; it asks sudo for the few steps that need it):
#   bash 09-install-tasks.sh          install / update, sign-up OPEN for your first account
#   bash 09-install-tasks.sh --lock   after creating your account: close sign-up
#
# What it does:
#   1. Creates ~/lab/tasks with data folders owned by the container user (1000)
#   2. Writes a private .env (random secret, your Tailscale https address)
#   3. Starts Vikunja on 127.0.0.1:3456
#   4. Publishes it privately with Tailscale HTTPS on port 8443
#   5. Adds Vikunja to the nightly backup (paused a few seconds for a clean copy)
# =============================================================================
set -euo pipefail

RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
DIR="$HOME/lab/tasks"
ENVF="$DIR/.env"
TS_PORT=8443

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_get() { grep -E "^$1=" "$ENVF" 2>/dev/null | head -1 | cut -d= -f2- || true; }
env_set() { local t; t=$(mktemp); grep -vE "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$ENVF"; rm -f "$t"; }
up() { docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d --force-recreate; }

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
docker ps >/dev/null 2>&1 || die "Docker isn't usable without sudo. Finish Lesson 03 first."

# ---------- --lock: close sign-up ----------
if [ "${1:-}" = "--lock" ]; then
  [ -f "$ENVF" ] || die "Vikunja isn't installed yet."
  env_set ALLOW_SIGNUP false
  up >/dev/null
  echo -e "${c_ok}Sign-up is now CLOSED.${c_off} Only existing accounts can log in."
  echo "Re-open it later (e.g. for a family member) with:  bash $0"
  exit 0
fi

# ---------- 1. folders ----------
step "1/5  Preparing ~/lab/tasks"
mkdir -p "$DIR/files" "$DIR/db"
sudo chown -R 1000:1000 "$DIR/files" "$DIR/db"     # the Vikunja container runs as user 1000
curl -fsSL "$RAW/stacks/tasks/compose.yaml" -o "$DIR/compose.yaml"

# ---------- 2. settings ----------
step "2/5  Private settings (.env)"
command -v tailscale >/dev/null || die "Tailscale isn't installed. Do Lesson 05 first."
TS_NAME=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
[ -n "$TS_NAME" ] || die "Couldn't read your Tailscale name. Is Tailscale connected? (tailscale status)"
umask 077; touch "$ENVF"; chmod 600 "$ENVF"; umask 022
[ -n "$(env_get VIKUNJA_SECRET)" ] || env_set VIKUNJA_SECRET "$(openssl rand -hex 32)"
env_set PUBLIC_URL "https://${TS_NAME}:${TS_PORT}/"
env_set ALLOW_SIGNUP true
echo "Address: https://${TS_NAME}:${TS_PORT}"

# ---------- 3. start ----------
step "3/5  Starting Vikunja"
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" pull -q
up
waited=0
until curl -fsS -o /dev/null http://127.0.0.1:3456/api/v1/info; do
  (( waited >= 120 )) && { docker logs --tail 30 vikunja; die "Vikunja didn't start. See the logs above."; }
  sleep 5; waited=$((waited + 5))
done
VERSION=$(curl -fsS http://127.0.0.1:3456/api/v1/info | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version","?"))')
echo "Vikunja $VERSION is running."

# ---------- 4. tailscale ----------
step "4/5  Publishing privately over Tailscale HTTPS (port ${TS_PORT})"
sudo tailscale serve --bg --https="$TS_PORT" 3456 >/dev/null
tailscale serve status 2>/dev/null | sed 's/^/  /'

# ---------- 5. backups ----------
step "5/5  Adding Vikunja to the nightly backup"
BCONF=/etc/free-ai-lab/backup.env
if sudo test -f "$BCONF"; then
  if sudo grep -qE '^BACKUP_STOP=.*vikunja' "$BCONF"; then
    echo "Already included."
  else
    sudo sed -i -E 's/^BACKUP_STOP="([^"]*)"/BACKUP_STOP="\1 vikunja"/' "$BCONF"
    echo "Done: ~/lab/tasks is backed up, and Vikunja pauses a few seconds at 03:30 for a clean copy."
  fi
else
  warn "Backups aren't installed yet (Lesson 08). Vikunja's data will be included once they are."
fi

step "Done!"
echo -e "  Open on your laptop or phone (Tailscale on):  ${c_ok}https://${TS_NAME}:${TS_PORT}${c_off}"
echo "  1) Click 'Register' and create YOUR account now."
echo "  2) Then close sign-up so nobody else can register:"
echo -e "       ${c_warn}bash $0 --lock${c_off}"
