#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 08: n8n, the automation engine behind every Jarvis skill
#
# Run ON THE SERVER as ubuntu (no sudo in front; it uses sudo itself for 2 small steps):
#   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/08-install-n8n.sh -o 08-install-n8n.sh && bash 08-install-n8n.sh
#
# What it does:
#   1. Checks Docker, the brain (Lesson 06) and Tailscale (Lesson 04)
#   2. Creates ~/lab/jarvis with a private .env (random encryption key, your Tailscale name)
#   3. Starts n8n on 127.0.0.1:5678 and waits until it's healthy
#   4. Publishes the editor privately with Tailscale HTTPS on port 9443 (never public)
#   5. Checks it's in the nightly backup (Lesson 07)
#   6. Shows how to connect n8n to the gateway
#
# Safe to re-run (that's also how you update n8n).
# =============================================================================
set -euo pipefail

RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
DIR="$HOME/lab/jarvis"
ENVF="$DIR/.env"
TS_PORT=9443

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_get() { grep -m1 "^$1=" "$ENVF" 2>/dev/null | cut -d= -f2- || true; }
env_set() { local t="$ENVF.tmp"; grep -v "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; mv "$t" "$ENVF"; chmod 600 "$ENVF"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
dc() { docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" "$@"; }

# ---------- 1. checks ----------
step "1/6  Checking the server"
[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo, as ubuntu:  bash $0"
sudo -n true 2>/dev/null || die "Your user needs passwordless sudo (Oracle's ubuntu user has it)."
docker ps >/dev/null 2>&1 || die "Docker isn't usable without sudo. Finish Lesson 03 (log out and back in)."
docker network inspect jarvis >/dev/null 2>&1 || die "The 'jarvis' network is missing. Do Lesson 06 first (bash 06-install-brain.sh)."
[ "$(health litellm)" = "healthy" ] && echo "Gateway: healthy" || warn "The gateway (litellm) isn't healthy now; n8n installs anyway, but AI nodes need it: cd ~/lab/brain && docker compose up -d"
command -v tailscale >/dev/null || die "Tailscale isn't installed. Do Lesson 04 first."
TS_NAME=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)
[ -n "$TS_NAME" ] || die "Couldn't read your Tailscale name. Is Tailscale connected? (tailscale status)"
echo "Tailscale name: $TS_NAME"

# ---------- 2. folders + settings ----------
step "2/6  Preparing ~/lab/jarvis"
mkdir -p "$DIR/n8n"
sudo -n chown -R 1000:1000 "$DIR/n8n"        # the n8n container runs as user 'node' (uid 1000)
curl -fsSL "$RAW/stacks/jarvis/compose.yaml" -o "$DIR/compose.yaml"
umask 077; touch "$ENVF"; chmod 600 "$ENVF"; umask 022
NEW_KEY=""
if [ -z "$(env_get N8N_ENCRYPTION_KEY)" ]; then
  NEW_KEY=$(openssl rand -hex 16)
  env_set N8N_ENCRYPTION_KEY "$NEW_KEY"
fi
env_set TS_NAME "$TS_NAME"
TZ_NOW=$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)
[ -n "$(env_get TZ_NAME)" ] || env_set TZ_NAME "$([ "$TZ_NOW" = UTC ] || [ -z "$TZ_NOW" ] && echo Asia/Riyadh || echo "$TZ_NOW")"
echo "Time zone for schedules: $(env_get TZ_NAME)   (change TZ_NAME in ~/lab/jarvis/.env if needed)"

# ---------- 3. start ----------
step "3/6  Starting n8n (first download is a few hundred MB)"
dc pull -q
dc up -d
waited=0
until [ "$(health n8n)" = "healthy" ]; do
  (( waited >= 300 )) && { docker logs --tail 40 n8n; die "n8n didn't become healthy. See the logs above."; }
  printf "  waiting for n8n (%s, %ss)...\r" "$(health n8n)" "$waited"; sleep 10; waited=$((waited + 10))
done
echo "n8n $(docker exec n8n n8n --version 2>/dev/null || echo '?') is healthy.                    "
docker exec n8n node -e "fetch('http://litellm:4000/health/liveliness').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" >/dev/null 2>&1 \
  && echo "n8n can reach the gateway at http://litellm:4000" \
  || warn "n8n can't reach http://litellm:4000 yet. Check: docker network inspect jarvis"

# ---------- 4. tailscale ----------
step "4/6  Publishing the editor privately (Tailscale HTTPS, port $TS_PORT)"
sudo -n tailscale serve --bg --https="$TS_PORT" 5678 >/dev/null
if tailscale funnel status 2>/dev/null | grep -qi "funnel on"; then
  warn "Something is PUBLIC through Funnel. Turning it off."; sudo -n tailscale funnel reset || true
fi
tailscale serve status 2>/dev/null | sed 's/^/  /'

# ---------- 5. backups ----------
step "5/6  Nightly backup"
if sudo -n test -f /etc/free-ai-lab/backup.env; then
  sudo -n grep -qE '^BACKUP_STOP=.*\bn8n\b' /etc/free-ai-lab/backup.env \
    && echo "Included: ~/lab/jarvis is backed up, and n8n pauses a few seconds at 03:30 for a clean copy." \
    || warn "Backups don't pause n8n yet: re-run Lesson 07's installer (sudo bash 07-install-backup.sh)."
else
  warn "Backups aren't installed yet (Lesson 07). n8n's data will be included once they are."
fi

# ---------- 6. next ----------
step "6/6  Connect n8n to the gateway (Lesson 08, Part D)"
echo "  Base URL : http://litellm:4000/v1"
echo "  API key  : grep LITELLM_MASTER_KEY ~/lab/brain/.env"
echo "  Models   : smart, fast, private$(grep -q 'model_name: general' "$HOME/lab/brain/config.yaml" 2>/dev/null && echo ', general')"

if [ -n "$NEW_KEY" ]; then
  echo
  echo -e "${c_warn}=================== SAVE THIS NOW ===================${c_off}"
  echo -e "  n8n encryption key:  ${c_ok}${NEW_KEY}${c_off}"
  echo "  n8n encrypts every saved credential (keys, bot tokens) with it."
  echo "  It's in ~/lab/jarvis/.env and in the nightly backup; keep a copy"
  echo "  in your password manager too. NOT on GitHub, not in a chat."
  echo -e "${c_warn}=====================================================${c_off}"
fi
unset NEW_KEY

step "Done!"
echo -e "  Open on your laptop (Tailscale on):  ${c_ok}https://${TS_NAME}:${TS_PORT}${c_off}"
echo "  Create the OWNER account right away: the first person to open a new n8n becomes its owner."
