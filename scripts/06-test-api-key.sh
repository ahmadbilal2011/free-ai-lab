#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 06: test a free AI API key from the server
#
#   bash 06-test-api-key.sh groq
#   bash 06-test-api-key.sh cerebras
#   bash 06-test-api-key.sh openrouter
#   MODEL=llama-3.3-70b-versatile bash 06-test-api-key.sh groq   # also send a test question
#
# The key is typed hidden, used once, and NOT saved anywhere
# (it is passed to curl via a temporary pipe, so it never shows in the process list).
# =============================================================================
set -euo pipefail

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
die() { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

case "${1:-}" in
  groq)       BASE="https://api.groq.com/openai/v1" ;;
  cerebras)   BASE="https://api.cerebras.ai/v1" ;;
  openrouter) BASE="https://openrouter.ai/api/v1" ;;
  gemini)     BASE="https://generativelanguage.googleapis.com/v1beta/openai" ;;
  *) die "Usage: bash $0 groq|cerebras|openrouter|gemini" ;;
esac

read -r -s -p "Paste your $1 API key (hidden) and press Enter: " KEY; echo
[ -n "$KEY" ] || die "No key entered."

echo "Checking the key against $BASE/models ..."
RESP=$(curl -sS --max-time 30 -w '\n%{http_code}' -H @<(printf "Authorization: Bearer %s" "$KEY") "$BASE/models") || die "Network error."
CODE=$(echo "$RESP" | tail -1); BODY=$(echo "$RESP" | sed '$d')
case "$CODE" in
  200) echo -e "${c_ok}Key works.${c_off} Models available to you:" ;;
  401|403) die "The provider rejected the key (HTTP $CODE). Copy it again carefully." ;;
  429) die "Rate limited (HTTP 429): the free limit is used up for now. Try later." ;;
  *) die "Unexpected answer (HTTP $CODE): $(echo "$BODY" | head -c 300)" ;;
esac
echo "$BODY" | python3 -c 'import json,sys; [print("  -", m["id"]) for m in sorted(json.load(sys.stdin).get("data",[]), key=lambda m: m["id"])]' | head -40

if [ -n "${MODEL:-}" ]; then
  echo; echo "Asking $MODEL a test question..."
  START=$(date +%s.%N)
  ANSWER=$(curl -sS --max-time 60 "$BASE/chat/completions" \
    -H @<(printf "Authorization: Bearer %s" "$KEY") -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"In one short sentence, say hello to a DevOps student.\"}]}" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"] if "choices" in d else "ERROR: "+json.dumps(d)[:300])')
  END=$(date +%s.%N)
  echo -e "AI says: ${c_ok}${ANSWER}${c_off}"
  echo "(took $(python3 -c "print(round($END - $START, 1))") seconds)"
fi
unset KEY
