#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 04: install my own AI (Ollama + Open WebUI + autoheal)
#
# Run ON THE VM as the ubuntu user (NO sudo — you're in the docker group):
#   bash 04-install-ai.sh
#
# Choose a different first model with:  MODEL=gemma3:4b bash 04-install-ai.sh
#
# What it does:
#   1. Checks Docker, free RAM and free disk
#   2. Starts autoheal (~/lab/autoheal) — restarts frozen containers
#   3. Starts Ollama + Open WebUI (~/lab/ai), with a private secret in .env
#   4. Downloads a small AI model and asks it a test question
#   5. Waits until Open WebUI is ready and prints how to open it
#
# Safe to re-run.
# =============================================================================
set -euo pipefail

MODEL="${MODEL:-llama3.2:3b}"
RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
LAB="$HOME/lab"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo "missing"; }

wait_healthy() {   # wait_healthy <container> <max-seconds>
  local name="$1" max="$2" waited=0 s
  while :; do
    s=$(health "$name")
    [ "$s" = "healthy" ] && { echo "$name is healthy."; return 0; }
    [ "$s" = "unhealthy" ] && { warn "$name is unhealthy. Logs:"; docker logs --tail 30 "$name"; return 1; }
    (( waited >= max )) && { warn "$name still '$s' after ${max}s."; return 1; }
    printf "  waiting for %s (%s, %ss)...\r" "$name" "$s" "$waited"
    sleep 10; waited=$((waited + 10))
  done
}

# ---------- 1. pre-flight ----------
step "1/5  Checking the server"
[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo, as the ubuntu user:  bash $0"
docker ps >/dev/null 2>&1 || die "Docker isn't usable without sudo yet. Finish Lesson 03 (log out and back in)."
MEM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
DISK_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
echo "RAM: ~${MEM_GB} GB   Free disk: ${DISK_GB} GB   Model: ${MODEL}"
(( DISK_GB >= 15 )) || die "Less than 15 GB free disk. Free some space first (docker image prune)."

# ---------- 2. autoheal ----------
step "2/5  Starting autoheal (restarts frozen containers)"
mkdir -p "$LAB/autoheal"
curl -fsSL "$RAW/stacks/autoheal/compose.yaml" -o "$LAB/autoheal/compose.yaml"
docker compose -f "$LAB/autoheal/compose.yaml" up -d
sleep 5
if [ "$(health autoheal)" = "running" ]; then
  echo "autoheal is running."
else
  warn "autoheal is not running (status: $(health autoheal)). Your AI still works; tell your instructor:"
  docker logs --tail 20 autoheal 2>&1 || true
fi

# ---------- 3. AI stack ----------
step "3/5  Starting Ollama + Open WebUI"
mkdir -p "$LAB/ai"
curl -fsSL "$RAW/stacks/ai/compose.yaml" -o "$LAB/ai/compose.yaml"
if [ ! -f "$LAB/ai/.env" ]; then
  umask 077
  echo "WEBUI_SECRET_KEY=$(openssl rand -hex 32)" > "$LAB/ai/.env"
  umask 022
  echo "Created a private secret in ~/lab/ai/.env (readable only by you; never commit it)."
else
  echo "Reusing existing ~/lab/ai/.env"
fi
echo "Downloading images (Open WebUI is large, a few minutes the first time)..."
docker compose -f "$LAB/ai/compose.yaml" --project-directory "$LAB/ai" pull -q
docker compose -f "$LAB/ai/compose.yaml" --project-directory "$LAB/ai" up -d
wait_healthy ollama 120 || die "Ollama didn't become healthy."

# ---------- 4. model ----------
step "4/5  Downloading the AI model '${MODEL}' and testing it"
docker exec ollama ollama pull "$MODEL"
echo
echo "Asking a test question (the first answer is slow: the model loads into RAM)..."
START=$(date +%s)
ANSWER=$(timeout 600 docker exec ollama ollama run "$MODEL" "In one short sentence, say hello to a new student learning DevOps." 2>/dev/null || true)
END=$(date +%s)
if [ -n "$ANSWER" ]; then
  echo -e "AI says: ${c_ok}${ANSWER}${c_off}"
  echo "(took $((END - START)) seconds including loading the model)"
else
  warn "The test question got no answer. Check: docker logs ollama"
fi

# ---------- 5. Open WebUI ----------
step "5/5  Waiting for Open WebUI (first start can take up to 10 minutes)"
if wait_healthy open-webui 600; then
  WEBUI_OK=yes
else
  WEBUI_OK=no
  warn "Open WebUI isn't ready yet. It may still be finishing its first start. Check: docker logs -f open-webui"
fi

step "Done! Summary"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo
echo "Models downloaded:"
docker exec ollama ollama list
echo
echo "Memory now:"; free -h | sed -n '1,2p'
echo
if [ "$WEBUI_OK" = yes ]; then
  echo -e "${c_ok}Open WebUI is ready.${c_off} It's private (server-only, port 3000 is not public)."
else
  echo "Open WebUI is still starting. Check later with: docker ps"
fi
echo -e "${c_warn}NEXT:${c_off} Lesson 05 (Tailscale) gives you a private https:// address for your laptop and phone."
echo "Create your Open WebUI account there first: the FIRST account becomes the admin."
