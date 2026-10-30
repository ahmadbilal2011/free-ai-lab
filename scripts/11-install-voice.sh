#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 11: give Jarvis ears and a voice
#
# Run ON THE VM as ubuntu (no sudo):
#   bash 11-install-voice.sh
#
# What it does:
#   1. Ears:  adds a 'listen' model to the gateway (Groq's free Whisper, cloud)
#   2. Voice: builds a tiny local text-to-speech service (Piper, open source)
#   3. Downloads Piper voices for English, Arabic and Urdu
#   4. Starts the voice service (no port on the host: only n8n can reach it)
#   5. Round-trip test: Jarvis speaks a sentence, then 'listen' transcribes it
#
# Safe to re-run.
# =============================================================================
set -euo pipefail

RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
GW="$HOME/lab/gateway"
DIR="$HOME/lab/voice"
ENVF="$DIR/.env"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
wait_healthy() { local w=0; until [ "$(health "$1")" = "healthy" ]; do
  (( w >= ${2:-180} )) && { docker logs --tail 30 "$1"; die "$1 didn't become healthy."; }; sleep 5; w=$((w+5)); done; }

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
docker network inspect ai_default >/dev/null 2>&1 || die "The AI stack isn't running (Lesson 04)."
[ -f "$GW/.env" ] || die "The gateway isn't installed (Lesson 07)."

# ---------- 1. ears ----------
step "1/5  Ears: adding 'listen' (speech-to-text) to the gateway"
curl -fsSL "$RAW/scripts/07-pick-models.py" -o "$GW/pick-models.py"
python3 "$GW/pick-models.py" || warn "The model picker reported a problem (see above)."
grep -q "model_name: listen" "$GW/config.yaml" \
  || warn "No speech-to-text model found (needs a Groq key). Voice notes won't be understood until it's added."
docker compose -f "$GW/compose.yaml" --project-directory "$GW" up -d --force-recreate >/dev/null
wait_healthy litellm
echo "Gateway restarted with 'listen'."

# ---------- 2. voice service ----------
step "2/5  Voice: building the local text-to-speech service (first build takes a few minutes)"
mkdir -p "$DIR/voices"
for f in compose.yaml Dockerfile server.py; do curl -fsSL "$RAW/stacks/voice/$f" -o "$DIR/$f"; done
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" build -q
sudo chown -R 1000:1000 "$DIR/voices"

# ---------- 3. voices ----------
step "3/5  Downloading voices (English, Arabic, Urdu)"
piper() { docker run --rm --user 1000 -v "$DIR/voices:/voices" free-ai-lab/voice:local python -m piper.download_voices "$@"; }
ALL=$(piper 2>/dev/null || true)
[ -n "$ALL" ] || die "Couldn't list Piper voices (is huggingface.co reachable from the server?)."
pick() {  # pick <lang prefix> [preferred name]
  local pref="${2:-}"
  if [ -n "$pref" ] && echo "$ALL" | grep -qx "$pref"; then echo "$pref"; return; fi
  echo "$ALL" | grep "^$1" | grep -- "-medium$" | head -1 || true
}
VEN=$(pick en_US en_US-lessac-medium); VAR=$(pick ar_); VUR=$(pick ur_)
[ -n "$VUR" ] || VUR=$(echo "$ALL" | grep "^ur_" | head -1 || true)
umask 077; : > "$ENVF"; umask 022
for pair in "EN:$VEN" "AR:$VAR" "UR:$VUR"; do
  lang="${pair%%:*}"; name="${pair#*:}"
  if [ -z "$name" ]; then warn "No Piper voice found for ${lang}; Jarvis will reply in text only for that language."; continue; fi
  piper "$name" --data-dir /voices >/dev/null 2>&1 || { warn "Download failed for $name"; continue; }
  echo "VOICE_${lang}=${name}.onnx" >> "$ENVF"
  echo "  ${lang}: ${name}"
done

# ---------- 4. start ----------
step "4/5  Starting the voice service"
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d --force-recreate >/dev/null
wait_healthy voice
docker exec voice python -c "import urllib.request; print('  ', urllib.request.urlopen('http://localhost:5000/health').read().decode())"

# ---------- 5. round trip ----------
step "5/5  Round-trip test: speak, then listen"
docker exec voice python -c "
import json, urllib.request
req = urllib.request.Request('http://localhost:5000/speak', data=json.dumps({'text': 'Hello Ahmad, this is Jarvis. Voice is working.'}).encode(), headers={'Content-Type': 'application/json'})
open('/tmp/test.ogg', 'wb').write(urllib.request.urlopen(req).read())"
TMP=$(mktemp -d); docker cp voice:/tmp/test.ogg "$TMP/test.ogg" >/dev/null
echo "  Jarvis spoke: $(du -h "$TMP/test.ogg" | cut -f1) of OGG/Opus audio"
MASTER=$(grep -E '^LITELLM_MASTER_KEY=' "$GW/.env" | cut -d= -f2-)
HEARD=$(curl -s --max-time 60 http://127.0.0.1:4000/v1/audio/transcriptions \
  -H @<(printf "Authorization: Bearer %s" "$MASTER") -F file=@"$TMP/test.ogg" -F model=listen \
  | python3 -c 'import json,sys
try: d=json.load(sys.stdin); print(d.get("text") or "ERROR: "+str(d.get("error",d))[:150])
except Exception as e: print("ERROR:", e)')
unset MASTER; rm -rf "$TMP"
echo -e "  'listen' heard:  ${c_ok}${HEARD}${c_off}"

step "Done!"
echo "  Ears  (speech-to-text): gateway model 'listen'  →  http://litellm:4000/v1/audio/transcriptions"
echo "  Voice (text-to-speech): local service            →  http://voice:5000/speak"
echo
echo "Next: add voice to your 'Jarvis chat' workflow in n8n (Lesson 11, Part D)."
