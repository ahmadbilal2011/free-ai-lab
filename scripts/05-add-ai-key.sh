#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 05: test a free AI API key, and keep it safely for Jarvis
#
# Run ON THE SERVER, as your normal user (ubuntu), one provider at a time:
#   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/05-add-ai-key.sh -o 05-add-ai-key.sh
#   bash 05-add-ai-key.sh groq
#   bash 05-add-ai-key.sh nvidia
#   bash 05-add-ai-key.sh openrouter
#   bash 05-add-ai-key.sh gemini        # optional, general questions only
#   bash 05-add-ai-key.sh status        # which keys are saved (never shows them)
#
# What it does:
#   1. You paste the key HIDDEN (it never appears on screen or in the process list)
#   2. Checks the key with the provider and lists the models you can use
#   3. Asks one real model a test question and shows how fast it answered
#   4. If you agree, saves the key in ~/lab/brain/.env (only you can read it),
#      where the AI gateway (Lesson 06) will find it. Never on GitHub.
# =============================================================================
set -uo pipefail

ENV_FILE="${ENV_FILE:-$HOME/lab/brain/.env}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
ok()   { echo -e "${c_ok}$*${c_off}"; }
warn() { echo -e "${c_warn}[!] $*${c_off}"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run as your normal user (ubuntu), without sudo, so the key file belongs to you."
command -v curl >/dev/null && command -v python3 >/dev/null || die "Needs curl and python3 (both come with Ubuntu)."

# --- the key file: created private (600) before anything is written ----------
env_get() { [ -f "$ENV_FILE" ] && grep -m1 "^$1=" "$ENV_FILE" | cut -d= -f2- || true; }
env_set() {   # printf is a shell builtin, so the key never shows in the process list
  mkdir -p "$(dirname "$ENV_FILE")"; chmod 700 "$(dirname "$ENV_FILE")"
  umask 077; touch "$ENV_FILE"; chmod 600 "$ENV_FILE"
  local tmp="$ENV_FILE.tmp"; grep -v "^$1=" "$ENV_FILE" > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"; mv "$tmp" "$ENV_FILE"; chmod 600 "$ENV_FILE"
}
show() { local v; v=$(env_get "$1"); if [ -n "$v" ]; then echo "saved (${#v} characters, ends in ...${v: -4})"; else echo "not saved"; fi; }

if [ "${1:-}" = "status" ]; then
  echo "Keys in $ENV_FILE:"
  for k in GROQ_API_KEY NVIDIA_API_KEY OPENROUTER_API_KEY GEMINI_API_KEY; do printf '  %-20s %s\n' "$k" "$(show $k)"; done
  exit 0
fi

case "${1:-}" in
  groq)       BASE="https://api.groq.com/openai/v1";                          VAR=GROQ_API_KEY;       SITE="https://console.groq.com/keys" ;;
  nvidia)     BASE="https://integrate.api.nvidia.com/v1";                     VAR=NVIDIA_API_KEY;     SITE="https://build.nvidia.com" ;;
  openrouter) BASE="https://openrouter.ai/api/v1";                            VAR=OPENROUTER_API_KEY; SITE="https://openrouter.ai/keys" ;;
  gemini)     BASE="https://generativelanguage.googleapis.com/v1beta/openai"; VAR=GEMINI_API_KEY;     SITE="https://aistudio.google.com/apikey" ;;
  *) die "Usage: bash $0 groq | nvidia | openrouter | gemini | status" ;;
esac
PROVIDER="$1"

echo "Provider: $PROVIDER   (key page: $SITE)"
echo "Currently: $(show $VAR)"
[ "$PROVIDER" = "gemini" ] && warn "Gemini's free tier uses your prompts in Saudi Arabia: Jarvis will use it for general questions only."
echo
read -r -s -p "Paste your $PROVIDER API key (hidden) and press Enter: " KEY; echo
KEY="${KEY//[[:space:]]/}"
[ -n "$KEY" ] || die "No key entered."
echo "Received ${#KEY} characters, ending in ...${KEY: -4}"

# ---------------------------------------------------------------------------
echo; echo "1/3  Checking the key with $PROVIDER..."
RESP=$(curl -sS --max-time 30 -w '\n%{http_code}' -H @<(printf "Authorization: Bearer %s" "$KEY") "$BASE/models") || die "Network error. Check the server's internet: curl -sI https://www.google.com"
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
case "$CODE" in
  200) ok "Key works." ;;
  400|401|403) die "$PROVIDER rejected the key (HTTP $CODE). Copy it again carefully from $SITE (the whole key, no spaces)." ;;
  429) die "Rate limited (HTTP 429): the free limit is used up for now. Try again later." ;;
  *) die "Unexpected answer (HTTP $CODE): $(echo "$BODY" | head -c 300)" ;;
esac

# ---------------------------------------------------------------------------
echo; echo "2/3  Models you can use (chat models, best first):"
CANDIDATES=$(echo "$BODY" | PROVIDER="$PROVIDER" python3 -c '
import json, os, sys
p = os.environ["PROVIDER"]
ids = [m.get("id", "") for m in json.load(sys.stdin).get("data", [])]
skip = ("whisper", "tts", "guard", "embed", "rerank", "vision", "image", "audio", "moderation", "safety", "parse", "ocr", "retriever", "clip", "vlm")
ids = [i for i in ids if i and not any(s in i.lower() for s in skip)]
if p == "openrouter":
    ids = [i for i in ids if i.endswith(":free")]
prefs = ["gpt-oss-120b", "nemotron-3-ultra", "llama-3.3-70b", "qwen3", "deepseek", "llama-4", "gpt-oss-20b", "gemini-2.5-flash", "flash", "llama", "qwen", "mistral"]
def rank(i):
    for n, s in enumerate(prefs):
        if s in i.lower(): return n
    return len(prefs)
ids.sort(key=lambda i: (rank(i), i))
print("\n".join(ids))
')
TOTAL=$(echo "$CANDIDATES" | grep -c . || true)
echo "$CANDIDATES" | head -12 | sed 's/^/  - /'
[ "$TOTAL" -gt 12 ] && echo "  ... and $((TOTAL - 12)) more"
[ "$TOTAL" -gt 0 ] || warn "No free chat models found for this key. On OpenRouter, only models ending in :free are free."

# ---------------------------------------------------------------------------
echo; echo "3/3  Asking a model a test question..."
ANSWERED=0
for MODEL in $(echo "$CANDIDATES" | head -4); do
  START=$(date +%s.%N)
  OUT=$(curl -sS --max-time 60 "$BASE/chat/completions" \
    -H @<(printf "Authorization: Bearer %s" "$KEY") -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"max_tokens\":200,\"messages\":[{\"role\":\"user\",\"content\":\"In one short sentence, say hello to Jarvis's owner.\"}]}" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin); print(d["choices"][0]["message"]["content"].strip()[:300])
except Exception:
    print("")' 2>/dev/null)
  END=$(date +%s.%N)
  if [ -n "$OUT" ]; then
    echo -e "  $MODEL says: ${c_ok}${OUT}${c_off}"
    echo "  (answered in $(python3 -c "print(round($END - $START, 1))") seconds)"
    ANSWERED=1; break
  else
    echo "  $MODEL didn't answer (busy, retired or not free right now), trying the next one..."
  fi
done
[ $ANSWERED -eq 1 ] || warn "The key works, but none of the first models answered right now. That's OK: Lesson 06 tests every model and picks working ones."

# ---------------------------------------------------------------------------
echo
read -r -p "Save this key for Jarvis's AI gateway (in $ENV_FILE, readable only by you)? [Y/n] " yn
case "${yn:-Y}" in
  [Nn]*) echo "Not saved. The key was used only for this test." ;;
  *) env_set "$VAR" "$KEY"; ok "Saved as $VAR: $(show $VAR)" ;;
esac
unset KEY

echo
echo "Next: run this script for the other providers, then check with:  bash $0 status"
echo "Then close any Notepad / note where you pasted the key, without saving it."
