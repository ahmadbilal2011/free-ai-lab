#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 06: Jarvis's brain (AI gateway + private model)
#
# Run ON THE SERVER as ubuntu (no sudo), after saving your keys in Lesson 05:
#   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/06-install-brain.sh -o 06-install-brain.sh && bash 06-install-brain.sh
#
# What it does:
#   1. Checks Docker and your saved keys (~/lab/brain/.env, from Lesson 05)
#   2. Starts autoheal (restarts frozen containers)
#   3. Starts Ollama and downloads the small PRIVATE model
#   4. Finds the free cloud models that work TODAY and writes the gateway config
#   5. Starts LiteLLM (the gateway), tests every alias and the automatic fallback
#   6. Installs the 'ask' command so you can talk to Jarvis's brain from the terminal
#
# Safe to re-run (e.g. after adding a key, or when a provider renames models).
# Choose a different private model with:  PRIVATE_MODEL=qwen3.5:2b bash 06-install-brain.sh
# =============================================================================
set -euo pipefail

RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
LAB="$HOME/lab"
DIR="$LAB/brain"
ENVF="$DIR/.env"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
wait_healthy() {   # wait_healthy <container> <max-seconds>
  local name="$1" max="$2" waited=0 s
  while :; do
    s=$(health "$name")
    [ "$s" = "healthy" ] && { echo "$name is healthy.                              "; return 0; }
    [ "$s" = "unhealthy" ] && { warn "$name is unhealthy. Logs:"; docker logs --tail 30 "$name"; return 1; }
    (( waited >= max )) && { warn "$name still '$s' after ${max}s. Logs:"; docker logs --tail 30 "$name"; return 1; }
    printf "  waiting for %s (%s, %ss)...\r" "$name" "$s" "$waited"
    sleep 10; waited=$((waited + 10))
  done
}
env_get() { grep -m1 "^$1=" "$ENVF" 2>/dev/null | cut -d= -f2- || true; }
env_set() { local tmp="$ENVF.tmp"; grep -v "^$1=" "$ENVF" > "$tmp" || true; printf '%s=%s\n' "$1" "$2" >> "$tmp"; mv "$tmp" "$ENVF"; chmod 600 "$ENVF"; }
dc() { docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" "$@"; }

# ---------- 1. checks ----------
step "1/6  Checking the server and your keys"
[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo, as ubuntu:  bash $0"
docker ps >/dev/null 2>&1 || die "Docker isn't usable without sudo. Finish Lesson 03 (log out and back in)."
DISK_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
(( DISK_GB >= 12 )) || die "Only ${DISK_GB} GB free disk; need about 12 GB. Free space first (docker image prune -a)."
[ -f "$ENVF" ] || die "No saved keys found ($ENVF). Do Lesson 05 first:  bash 05-add-ai-key.sh groq"
chmod 700 "$DIR"; chmod 600 "$ENVF"
COUNT=0
for k in GROQ_API_KEY NVIDIA_API_KEY OPENROUTER_API_KEY; do
  v=$(env_get "$k"); if [ -n "$v" ] && [ "$v" != "not-set" ]; then echo "  $k: saved (ends in ...${v: -4})"; COUNT=$((COUNT+1)); else echo "  $k: not saved"; fi
done
v=$(env_get GEMINI_API_KEY); [ -n "$v" ] && echo "  GEMINI_API_KEY: saved (general questions only)"
(( COUNT > 0 )) || warn "No cloud keys saved: every answer will come from the slow private model. Add keys with Lesson 05 and re-run."
[ -n "$(env_get LITELLM_MASTER_KEY)" ] || env_set LITELLM_MASTER_KEY "sk-$(openssl rand -hex 24)"
PRIVATE_MODEL="${PRIVATE_MODEL:-$(env_get PRIVATE_MODEL)}"; PRIVATE_MODEL="${PRIVATE_MODEL:-llama3.2:3b}"
env_set PRIVATE_MODEL "$PRIVATE_MODEL"
echo "  Gateway master key: ready (kept in .env).  Private model: $PRIVATE_MODEL"

# ---------- 2. autoheal ----------
step "2/6  Starting autoheal (restarts frozen containers)"
mkdir -p "$LAB/autoheal"
curl -fsSL "$RAW/stacks/autoheal/compose.yaml" -o "$LAB/autoheal/compose.yaml"
docker compose -f "$LAB/autoheal/compose.yaml" up -d --quiet-pull 2>&1 | tail -2 || true
echo "autoheal: $(health autoheal)"

# ---------- 3. ollama + private model ----------
step "3/6  Starting Ollama and the private model '$PRIVATE_MODEL'"
curl -fsSL "$RAW/stacks/brain/compose.yaml"       -o "$DIR/compose.yaml"
curl -fsSL "$RAW/scripts/06-pick-models.py"       -o "$DIR/pick-models.py"
[ -f "$DIR/config.yaml" ] || printf 'model_list: []\ngeneral_settings:\n  master_key: os.environ/LITELLM_MASTER_KEY\n' > "$DIR/config.yaml"
dc pull -q
dc up -d ollama
wait_healthy ollama 180 || die "Ollama didn't become healthy."
docker exec ollama ollama pull "$PRIVATE_MODEL" 2>&1 | tail -1
echo "Loading it into memory with a test question (the first answer takes a while)..."
START=$(date +%s)
ANSWER=$(timeout 600 docker exec ollama ollama run "$PRIVATE_MODEL" "In one short sentence, say hello." 2>/dev/null || true)
[ -n "$ANSWER" ] && echo -e "  private model says: ${c_ok}${ANSWER}${c_off}  ($(( $(date +%s) - START ))s)" || warn "The private model didn't answer yet. Check: docker logs ollama"

# ---------- 4. pick models ----------
step "4/6  Finding the free cloud models that work TODAY (free tiers change often)"
python3 "$DIR/pick-models.py" || warn "No cloud model passed its test. The gateway will answer with the private model only."

# ---------- 5. gateway ----------
step "5/6  Starting the gateway (LiteLLM) and testing it"
dc up -d --no-deps --force-recreate litellm
wait_healthy litellm 240 || die "The gateway didn't become healthy. See the logs above."
MASTER=$(env_get LITELLM_MASTER_KEY)
HDR="$DIR/.last-headers"
ask_json() {  # ask_json MODEL   (body on stdout, response headers saved to $HDR)
  curl -sS --max-time 150 -D "$HDR" http://127.0.0.1:4000/v1/chat/completions \
    -H @<(printf "Authorization: Bearer %s" "$MASTER") -H "Content-Type: application/json" \
    -d "{\"model\":\"$1\",\"max_tokens\":40,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with just: OK\"}]}" 2>/dev/null
}
verdict() {  # verdict ALIAS EXPECTED-model (EXPECTED=BACKUP for the drill)
  # Newer LiteLLM reports the ALIAS as the model name, so we read its own counter
  # header (x-litellm-attempted-fallbacks) to know whether a backup answered.
  ALIAS="$1" EXPECT="$2" HDR="$HDR" python3 -c 'import json,os,sys
a=os.environ["ALIAS"]; exp=os.environ["EXPECT"]
fb=None
try:
  for line in open(os.environ["HDR"], errors="ignore"):
    k,_,v=line.partition(":")
    if k.strip().lower()=="x-litellm-attempted-fallbacks": fb=int(v.strip() or 0)
except Exception: pass
try:
  d=json.load(sys.stdin)
  if "choices" not in d:
    print("FAIL", str(d.get("error",{}).get("message",d))[:110].replace("\n"," ")); sys.exit()
  m=d.get("model","?")
  if exp=="BACKUP":
    if fb is None or fb>=1: print("OK   the broken first choice was skipped; a backup answered")
    else: print("FAIL the drill was not rerouted")
  elif fb==0 or (fb is None and (m==a or exp.split("/")[-1] in m)):
    print("OK   answered by", exp)
  else:
    print("FELL BACK: a backup answered (first choice", exp, "failed right now; fine if rare)")
except Exception as e: print("FAIL", e)'; }
python3 - "$DIR/config.yaml" > "$DIR/.aliases" <<'PY'
import sys, re
name = None
for line in open(sys.argv[1]):
    m = re.match(r"\s*- model_name: (\S+)", line)
    if m: name = m.group(1); continue
    m = re.match(r"\s*model: (\S+)", line)
    if m and name: print(name, m.group(1)); name = None
PY
while read -r alias model; do
  case "$alias" in smart|fast|private|general) ;; *) continue ;; esac
  printf "  %-9s " "$alias"; ask_json "$alias" | verdict "$alias" "$model"
done < "$DIR/.aliases"
rm -f "$DIR/.aliases"
echo "  Fallback drill ('drill' has a broken key on purpose, so a backup must answer):"
printf "  %-9s " "drill"; ask_json drill | verdict drill "BACKUP"
rm -f "$HDR"

# ---------- 6. ask command ----------
step "6/6  Installing the 'ask' command"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ask" <<'EOF'
#!/usr/bin/env bash
# ask "question"            -> Jarvis's brain answers with 'smart'
# ask -m private "question" -> pick an alias: smart, fast, private, general
MODEL=smart; [ "${1:-}" = "-m" ] && { MODEL="$2"; shift 2; }
[ -n "${1:-}" ] || { echo 'Usage: ask [-m smart|fast|private|general] "your question"'; exit 1; }
KEY=$(grep -m1 '^LITELLM_MASTER_KEY=' "$HOME/lab/brain/.env" | cut -d= -f2-)
BODY=$(M="$MODEL" Q="$*" python3 -c 'import json,os; print(json.dumps({"model":os.environ["M"],"messages":[{"role":"user","content":os.environ["Q"]}]}))')
START=$(date +%s.%N)
curl -sS --max-time 180 http://127.0.0.1:4000/v1/chat/completions -H @<(printf "Authorization: Bearer %s" "$KEY") \
  -H "Content-Type: application/json" -d "$BODY" | python3 -c 'import json,sys
d=json.load(sys.stdin)
if "choices" in d: print(d["choices"][0]["message"]["content"].strip()); print("\n[" + d.get("model","?") + "]", end=" ")
else: print("Error:", d.get("error", d))'
echo "$(python3 -c "print(round($(date +%s.%N) - $START, 1))")s"
EOF
chmod 755 "$HOME/.local/bin/ask"
grep -q '.local/bin' "$HOME/.profile" 2>/dev/null || echo 'PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
echo "Installed. To use it in THIS session, run once:  source ~/.profile"
echo "Then try:  ask \"What can you help me with?\""

step "Done! Summary"
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'NAMES|ollama|litellm|autoheal'
echo
echo "Memory:"; free -h | sed -n '1,2p'
echo
echo "Gateway (server-only):     http://127.0.0.1:4000/v1"
echo "From other containers:     http://litellm:4000/v1   (network: jarvis)"
echo "Aliases:                   smart, fast, private$(grep -q 'model_name: general' "$DIR/config.yaml" && echo ', general')"
echo "FELL BACK / FAIL on a line: see Lesson 06, 'If something goes wrong'."
