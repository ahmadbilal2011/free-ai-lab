#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 09: Jarvis on Telegram (polling, nothing public)
#
# Run ON THE SERVER as ubuntu (no sudo):
#   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/09-install-telegram.sh -o 09-install-telegram.sh && bash 09-install-telegram.sh
#
# What it does:
#   1. Checks n8n and the 'Jarvis brain' credential (Lesson 08)
#   2. Asks for your bot token (hidden) and checks it with Telegram
#   3. Makes sure the bot uses polling (removes any old webhook)
#   4. Finds YOUR Telegram user ID: you send /start to the bot
#   5. Imports the "Jarvis — Telegram chat" workflow into n8n, publishes it, restarts n8n
#
# The token is never printed and never saved in a file: it goes only into the
# n8n workflow (inside n8n's database, backed up encrypted). Safe to re-run,
# e.g. after you revoke the token: it replaces the workflow.
# =============================================================================
set -uo pipefail

RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
DIR="$HOME/lab/jarvis"
ENVF="$DIR/.env"
WF_ID="JarvisTelegram01"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
env_get() { grep -m1 "^$1=" "$ENVF" 2>/dev/null | cut -d= -f2- || true; }
env_set() { local t="$ENVF.tmp"; grep -v "^$1=" "$ENVF" > "$t" 2>/dev/null || true
            printf '%s=%s\n' "$1" "$2" >> "$t"; mv "$t" "$ENVF"; chmod 600 "$ENVF"; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
tg() {  # tg METHOD [query]   — calls the Bot API; the token goes via a curl config on stdin, never on the command line
  printf 'url = "https://api.telegram.org/bot%s/%s%s"\n' "$TOKEN" "$1" "${2:+?$2}" | curl -sS --max-time 70 -K - 2>/dev/null
}
jget() { python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
$1"; }

# ---------- 1. checks ----------
step "1/5  Checking n8n and the 'Jarvis brain' credential"
[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo, as ubuntu:  bash $0"
[ "$(health n8n)" = "healthy" ] || die "n8n isn't healthy. Do Lesson 08 first (bash 08-install-n8n.sh)."
docker exec n8n n8n export:credentials --all --output=/tmp/creds.json >/dev/null 2>&1
CRED_ID=$(docker exec n8n cat /tmp/creds.json 2>/dev/null | jget '
creds = d if isinstance(d, list) else [d] if d else []
ids = [c.get("id","") for c in creds if c.get("name") == "Jarvis brain" and c.get("type") == "openAiApi"]
print(ids[0] if ids else "")')
docker exec n8n rm -f /tmp/creds.json >/dev/null 2>&1
[ -n "$CRED_ID" ] || die "No OpenAI-type credential named exactly 'Jarvis brain' in n8n. Create it first (Lesson 08, Part D)."
echo "Found the 'Jarvis brain' credential."

# ---------- 2. token ----------
step "2/5  Your bot token"
echo "  From @BotFather in Telegram: /mybots → your bot → API Token (or /newbot for a new bot)."
echo "  Nothing appears while you paste: that's normal. Right-click pastes in most terminals."
read -r -s -p "  Bot token (hidden): " TOKEN; echo
TOKEN="${TOKEN//[[:space:]]/}"
[[ "$TOKEN" =~ ^[0-9]{5,}:[A-Za-z0-9_-]{30,}$ ]] || die "That doesn't look like a bot token (it looks like 123456789:AAF...). Copy it again from @BotFather."
ME=$(tg getMe)
BOT=$(echo "$ME" | jget 'print(d.get("result",{}).get("username","") if d.get("ok") else "")')
[ -n "$BOT" ] || die "Telegram rejected the token. Copy it again from @BotFather (/mybots → API Token)."
echo -e "  Token works: this is ${c_ok}@${BOT}${c_off}"

# ---------- 3. polling ----------
step "3/5  Making sure the bot uses polling (no webhook, nothing public)"
HOOK=$(tg getWebhookInfo | jget 'print(d.get("result",{}).get("url",""))')
if [ -n "$HOOK" ]; then
  tg deleteWebhook "drop_pending_updates=false" >/dev/null
  echo "  Removed an old webhook (from an earlier setup). The bot now waits for n8n to ask."
else
  echo "  No webhook: good."
fi

# ---------- 4. owner ----------
step "4/5  Who may talk to Jarvis: your Telegram user ID"
OWNER="${OWNER_ID:-$(env_get TELEGRAM_OWNER_ID)}"
if [ -n "$OWNER" ]; then
  read -r -p "  Saved owner ID is $OWNER. Keep it? [Y/n] " yn
  case "${yn:-Y}" in [Nn]*) OWNER="" ;; esac
fi
if [ -z "$OWNER" ]; then
  # n8n must not poll at the same time (an earlier install may be running), or it would take the /start message first
  docker stop n8n >/dev/null; STOPPED_N8N=1
  echo -e "  On your phone, open ${c_ok}https://t.me/${BOT}${c_off} and send:  /start"
  echo "  Waiting up to 2 minutes..."
  for _ in 1 2 3; do
    FOUND=$(tg getUpdates "timeout=40&allowed_updates=%5B%22message%22%5D" | jget '
for u in reversed(d.get("result", [])):
    f = (u.get("message") or {}).get("from") or {}
    if f and not f.get("is_bot") and (u.get("message") or {}).get("chat",{}).get("type") == "private":
        print(f.get("id"), f.get("first_name","?")); break')
    [ -n "$FOUND" ] && break
  done
  docker start n8n >/dev/null
  [ -n "${FOUND:-}" ] || die "No message arrived. Send /start to @${BOT} and run the script again."
  OWNER="${FOUND%% *}"
  read -r -p "  Message from ${FOUND#* } (ID $OWNER). Is that you? [Y/n] " yn
  case "${yn:-Y}" in [Nn]*) die "Then someone else messaged your bot. Run again and send /start yourself." ;; esac
fi
[[ "$OWNER" =~ ^[0-9]+$ ]] || die "Owner ID must be a number."
env_set TELEGRAM_OWNER_ID "$OWNER"
echo "  Only Telegram user $OWNER can talk to Jarvis. Everyone else is ignored."

# ---------- 5. import + publish ----------
step "5/5  Importing the workflow into n8n"
w=0; until [ "$(health n8n)" = "healthy" ]; do
  (( w >= 180 )) && die "n8n isn't healthy: docker logs --tail 40 n8n"; sleep 5; w=$((w+5)); done
TEMPLATE=$(curl -fsSL "$RAW/stacks/jarvis/workflows/telegram-chat.json") || die "Couldn't download the workflow template."
# Fill in token, owner and credential inside Python (the token travels via stdin, not the command line)
printf '%s\n%s\n%s\n' "$TOKEN" "$OWNER" "$CRED_ID" | TEMPLATE="$TEMPLATE" python3 -c '
import json, os, sys
token, owner, cred = [sys.stdin.readline().strip() for _ in range(3)]
t = os.environ["TEMPLATE"].replace("__BOT_TOKEN__", token).replace("__OWNER_ID__", owner).replace("__CRED_ID__", cred)
json.loads(t)
sys.stdout.write(t)' | docker exec -i n8n sh -c 'umask 077; cat > /tmp/jarvis-telegram.json' \
  || die "Couldn't prepare the workflow."
OUT=$(docker exec n8n n8n import:workflow --input=/tmp/jarvis-telegram.json 2>&1); RC=$?
docker exec n8n rm -f /tmp/jarvis-telegram.json
echo "  $(echo "$OUT" | tail -1)"
[ $RC -eq 0 ] || die "Import failed (see the line above)."
OUT=$(docker exec n8n n8n publish:workflow --id="$WF_ID" 2>&1); RC=$?
echo "  $(echo "$OUT" | tail -1)"
PUBLISHED=1
[ $RC -eq 0 ] || { PUBLISHED=0; warn "Couldn't publish from the command line: open the workflow in n8n and click Publish."; }
unset TOKEN
echo "  Restarting n8n so the old schedule (if any) stops and the new one starts..."
docker restart n8n >/dev/null
w=0; until [ "$(health n8n)" = "healthy" ]; do
  (( w >= 180 )) && die "n8n didn't come back healthy: docker logs --tail 40 n8n"; sleep 5; w=$((w+5)); done

step "Done!"
[ "$PUBLISHED" = 1 ] || echo -e "  ${c_warn}First: n8n → Workflows → 'Jarvis — Telegram chat' → Publish.${c_off}"
echo -e "  In Telegram, write to ${c_ok}@${BOT}${c_off}: e.g. \"Assalam o alaikum Jarvis, what can you do?\""
echo "  Replies take a few seconds (n8n checks Telegram every 30 seconds, and answers at once when you write)."
echo "  Commands:  /new = forget the conversation and start fresh"
echo "  In n8n: Workflows → 'Jarvis — Telegram chat' (Published). Failed runs appear under Executions."
