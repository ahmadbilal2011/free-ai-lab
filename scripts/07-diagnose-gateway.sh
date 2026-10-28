#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 07: find out WHY a provider falls back
#
# Run ON THE VM as ubuntu:   bash 07-diagnose-gateway.sh
#
# Never prints your keys: only their length and last 4 characters.
# =============================================================================
set -uo pipefail
ENVF="$HOME/lab/gateway/.env"
c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }

step "1/4  Do the keys reach the container? (length ...last4, never the key)"
for v in GROQ_API_KEY NVIDIA_API_KEY OPENROUTER_API_KEY LITELLM_MASTER_KEY; do
  docker exec litellm sh -c "x=\"\${$v:-}\"; printf '  %-20s length %-3s ...%s\n' $v \${#x} \"\$(printf %s \"\$x\" | tail -c 4)\""
done
echo "  (length 0 or 7 = 'not-set' means the key is missing inside the container)"

step "2/4  Can the container reach each provider over the internet?"
for url in https://api.groq.com/openai/v1/models https://integrate.api.nvidia.com/v1/models https://openrouter.ai/api/v1/models; do
  code=$(docker exec litellm python3 -c "
import urllib.request,urllib.error,sys
try: print(urllib.request.urlopen('$url', timeout=15).status)
except urllib.error.HTTPError as e: print(e.code)
except Exception as e: print('NO-NETWORK', type(e).__name__, str(e)[:80])" 2>&1)
  printf "  %-45s %s\n" "$url" "$code"
done
echo "  (200 or 401 = network OK.  NO-NETWORK = the container can't reach the internet)"

step "3/4  Does each key + model work when called DIRECTLY (bypassing LiteLLM)?"
get() { grep -E "^$1=" "$ENVF" | head -1 | cut -d= -f2-; }
# model names come from the GENERATED config, so this always tests what the gateway really uses
cfg_model() { grep -A2 "model_name: $1\$" "$HOME/lab/gateway/config.yaml" | sed -n 's/^ *model: [a-z]*\///p' | head -1; }
for row in "groq|GROQ_API_KEY|https://api.groq.com/openai/v1|$(cfg_model smart-groq)" \
           "nvidia|NVIDIA_API_KEY|https://integrate.api.nvidia.com/v1|$(cfg_model smart-nvidia)" \
           "openrouter|OPENROUTER_API_KEY|https://openrouter.ai/api/v1|$(cfg_model smart-openrouter)"; do
  IFS='|' read -r name var base model <<<"$row"
  [ -n "$model" ] || { printf "  %-11s not in config (no key, or no model passed the picker)\n" "$name"; continue; }
  key=$(get "$var")
  out=$(curl -s --max-time 40 -w '\n%{http_code}' "$base/chat/completions" \
        -H @<(printf "Authorization: Bearer %s" "$key") -H "Content-Type: application/json" \
        -d "{\"model\":\"$model\",\"max_tokens\":5,\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}")
  code=$(echo "$out" | tail -1)
  msg=$(echo "$out" | sed '$d' | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin); e=d.get("error") or d.get("detail")
  print("works" if "choices" in d else str(e)[:160].replace("\n"," "))
except Exception: print("(not JSON)")')
  printf "  %-11s HTTP %-4s %s\n" "$name" "$code" "$msg"
done
unset key
echo "  (200 works = key + model OK.  401/403 = key rejected.  404 / 'not found' = model renamed)"

step "4/4  LiteLLM's own health check of every model (real error messages)"
MASTER=$(get LITELLM_MASTER_KEY)
curl -s --max-time 180 -H @<(printf "Authorization: Bearer %s" "$MASTER") http://127.0.0.1:4000/health \
| python3 -c '
import json,sys,re
try: d=json.load(sys.stdin)
except Exception as e: print("  could not read /health:", e); sys.exit()
for e in d.get("healthy_endpoints",[]):   print("  HEALTHY  ", e.get("model"))
for e in d.get("unhealthy_endpoints",[]):
    err=str(e.get("error","")).replace("\n"," ")
    err=re.sub(r"(sk-|nvapi-|gsk_)[A-Za-z0-9_\-]{6,}", r"\1***", err)   # mask anything key-like
    print("  BROKEN   ", e.get("model"), "->", err[:260])
'
unset MASTER
echo
echo "Copy everything above (it contains no keys) and send it to your instructor / chat."
