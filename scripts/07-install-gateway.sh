#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 07: LiteLLM gateway with automatic fallback
#
# Run ON THE VM as ubuntu (no sudo):
#   bash 07-install-gateway.sh
#
# What it does:
#   1. Checks the AI stack (Lesson 04) is running
#   2. Downloads the gateway stack to ~/lab/gateway
#   3. Asks for your API keys (hidden) and stores them in ~/lab/gateway/.env
#      (readable only by you, never committed). Press Enter to skip a provider.
#   4. Starts LiteLLM and waits until it's healthy
#   5. Tests every model name and the automatic fallback
#
# Safe to re-run: existing keys in .env are kept unless you type a new one.
# =============================================================================
set -euo pipefail

RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
DIR="$HOME/lab/gateway"
ENVF="$DIR/.env"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
env_get() { grep -E "^$1=" "$ENVF" 2>/dev/null | head -1 | cut -d= -f2- || true; }
env_set() {  # env_set NAME VALUE  (rewrites the line, keeps the file private)
  local tmp; tmp=$(mktemp); grep -vE "^$1=" "$ENVF" > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"; cat "$tmp" > "$ENVF"; rm -f "$tmp"
}

# ---------- 1. checks ----------
step "1/5  Checking the AI stack"
[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
docker network inspect ai_default >/dev/null 2>&1 || die "The AI stack isn't running. Do Lesson 04 first (cd ~/lab/ai && docker compose up -d)."
[ "$(health ollama)" = "healthy" ] || warn "Ollama isn't healthy right now; the 'private' model test may fail."

# ---------- 2. files ----------
step "2/5  Downloading the gateway stack to ~/lab/gateway"
mkdir -p "$DIR"
curl -fsSL "$RAW/stacks/gateway/compose.yaml" -o "$DIR/compose.yaml"
curl -fsSL "$RAW/stacks/gateway/config.yaml"  -o "$DIR/config.yaml"
umask 077; touch "$ENVF"; chmod 600 "$ENVF"; umask 022

# ---------- 3. keys ----------
step "3/5  API keys (typed hidden; press Enter to keep the current one or skip)"
[ -n "$(env_get LITELLM_MASTER_KEY)" ] || env_set LITELLM_MASTER_KEY "sk-$(openssl rand -hex 24)"
for pair in "GROQ_API_KEY:Groq" "NVIDIA_API_KEY:NVIDIA (nvapi-...)" "OPENROUTER_API_KEY:OpenRouter"; do
  var="${pair%%:*}"; label="${pair#*:}"
  cur=$(env_get "$var")
  if [ -n "$cur" ] && [ "$cur" != "not-set" ]; then hint="saved, Enter keeps it"; else hint="not set, Enter skips"; fi
  read -r -s -p "  $label key ($hint): " val; echo
  if [ -n "$val" ]; then env_set "$var" "$val"; elif [ -z "$cur" ]; then env_set "$var" "not-set"; fi
done
unset val
echo "Keys saved in ~/lab/gateway/.env (only you can read it)."

# ---------- 4. start ----------
step "4/5  Starting LiteLLM"
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" pull -q
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d --force-recreate
waited=0
until [ "$(health litellm)" = "healthy" ]; do
  (( waited >= 180 )) && { docker logs --tail 40 litellm; die "LiteLLM didn't become healthy. See the logs above."; }
  printf "  waiting for litellm (%s, %ss)...\r" "$(health litellm)" "$waited"; sleep 10; waited=$((waited+10))
done
echo "LiteLLM is healthy.                         "

# ---------- 5. tests ----------
step "5/5  Testing each model name"
MASTER=$(env_get LITELLM_MASTER_KEY)
ask() {  # ask MODEL [extra-json]
  curl -sS --max-time 120 http://127.0.0.1:4000/v1/chat/completions \
    -H @<(printf "Authorization: Bearer %s" "$MASTER") -H "Content-Type: application/json" \
    -d "{\"model\":\"$1\",\"max_tokens\":30,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with just: OK\"}]${2:-}}" 2>/dev/null
}
summ() { python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)
  if "choices" in d: print("OK   answered by", d.get("model","?"))
  else: print("FAIL", str(d.get("error",{}).get("message",d))[:110].replace("\n"," "))
except Exception as e: print("FAIL", e)'; }

printf "  %-17s " "smart";            ask smart            | summ
printf "  %-17s " "fast";             ask fast             | summ
printf "  %-17s " "smart-nvidia";     ask smart-nvidia     | summ
printf "  %-17s " "smart-openrouter"; ask smart-openrouter | summ
printf "  %-17s " "private";          ask private          | summ
echo
echo "Fallback drill: pretend the primary provider failed..."
printf "  %-17s " "smart (mock fail)"; ask smart ',"mock_testing_fallbacks":true' | summ
echo "  ^ should be answered by a BACKUP model, not Groq."

step "Done!"
echo "Gateway (server-only):  http://127.0.0.1:4000/v1"
echo "Inside Docker:          http://litellm:4000/v1"
echo
echo -e "${c_warn}NEXT:${c_off} add the gateway to Open WebUI (Lesson 07, Part E). You'll need the master key:"
echo "  grep LITELLM_MASTER_KEY ~/lab/gateway/.env"
echo "A FAIL on a backup line usually means a skipped key or a changed model name (see Lesson 07)."
