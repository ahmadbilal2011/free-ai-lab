#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 11: give Jarvis ears and a voice
#
# Run ON THE VM as ubuntu (no sudo):
#   bash 11-install-voice.sh
#
# What it does:
#   1. Asks for your ElevenLabs API key (hidden; Enter keeps/skips) -> gateway .env
#   2. Ears:  gateway 'listen' = ElevenLabs Scribe, 'listen-backup' = Groq Whisper
#      Voice: gateway 'speak'  = ElevenLabs eleven_v3 (Urdu, Arabic, English)
#   3. Builds the voice service: cloud voice first, local Piper when credits run out
#   4. Downloads Piper voices (English, Arabic, Urdu) for the fallback
#   5. Tests both voices and both ears with a speak-then-listen round trip
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
gw_get() { grep -E "^$1=" "$GW/.env" 2>/dev/null | head -1 | cut -d= -f2- || true; }
gw_set() { local t; t=$(mktemp); grep -vE "^$1=" "$GW/.env" > "$t" || true
           printf '%s=%s\n' "$1" "$2" >> "$t"; cat "$t" > "$GW/.env"; rm -f "$t"; }

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo:  bash $0"
docker network inspect ai_default >/dev/null 2>&1 || die "The AI stack isn't running (Lesson 04)."
[ -f "$GW/.env" ] || die "The gateway isn't installed (Lesson 07)."

# ---------- 1. ElevenLabs key ----------
step "1/6  ElevenLabs API key (typed hidden; nothing appears while you paste — that's normal)"
cur=$(gw_get ELEVENLABS_API_KEY)
if [ -n "$cur" ] && [ "$cur" != "not-set" ]; then hint="saved ...${cur: -4}, Enter keeps it"; else hint="not set, Enter skips"; fi
read -r -s -p "  ElevenLabs key ($hint): " val; echo
val=$(printf '%s' "$val" | tr -d '[:space:]')
if [ -n "$val" ]; then gw_set ELEVENLABS_API_KEY "$val"; echo "    received ${#val} characters, ending in ...${val: -4}"
elif [ -z "$cur" ]; then gw_set ELEVENLABS_API_KEY not-set; echo "    skipped: ears = Groq, voice = local Piper only"
else echo "    kept"; fi
unset val cur

# ---------- 2. gateway: listen / listen-backup / speak ----------
step "2/6  Gateway: ears and voice models"
curl -fsSL "$RAW/scripts/07-pick-models.py" -o "$GW/pick-models.py"
python3 "$GW/pick-models.py" || warn "The model picker reported a problem (see above)."
docker compose -f "$GW/compose.yaml" --project-directory "$GW" up -d --force-recreate >/dev/null
wait_healthy litellm
echo "Gateway restarted."

# ---------- 3. voice service ----------
step "3/6  Voice service: building (first build takes a few minutes)"
mkdir -p "$DIR/voices"
for f in compose.yaml Dockerfile server.py; do curl -fsSL "$RAW/stacks/voice/$f" -o "$DIR/$f"; done
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" build -q
sudo chown -R 1000:1000 "$DIR/voices"

# ---------- 4. local fallback voices ----------
step "4/6  Downloading local fallback voices (English, Arabic, Urdu)"
piper() { docker run --rm --user 1000 -v "$DIR/voices:/voices" free-ai-lab/voice:local python -m piper.download_voices "$@"; }
ALL=$(piper 2>/dev/null || true)
[ -n "$ALL" ] || warn "Couldn't list Piper voices (is huggingface.co reachable?). The local fallback voice won't work."
pick() { local pref="${2:-}"
  if [ -n "$pref" ] && echo "$ALL" | grep -qx "$pref"; then echo "$pref"; return; fi
  echo "$ALL" | grep "^$1" | grep -- "-medium$" | head -1 || true; }
VEN=$(pick en_US en_US-lessac-medium); VAR=$(pick ar_); VUR=$(pick ur_)
[ -n "$VUR" ] || VUR=$(echo "$ALL" | grep "^ur_" | head -1 || true)

umask 077; : > "$ENVF"; umask 022
echo "GATEWAY_URL=http://litellm:4000/v1" >> "$ENVF"
echo "GATEWAY_KEY=$(gw_get LITELLM_MASTER_KEY)" >> "$ENVF"
if grep -q "model_name: speak" "$GW/config.yaml"; then echo "CLOUD_MODEL=speak" >> "$ENVF"
else sed -i '/^GATEWAY_KEY=/d' "$ENVF"; fi     # no cloud voice configured: local only
for pair in "EN:$VEN" "AR:$VAR" "UR:$VUR"; do
  lang="${pair%%:*}"; name="${pair#*:}"
  if [ -z "$name" ]; then warn "No local voice for ${lang}."; continue; fi
  piper "$name" --data-dir /voices >/dev/null 2>&1 || { warn "Download failed for $name"; continue; }
  echo "VOICE_${lang}=${name}.onnx" >> "$ENVF"; echo "  ${lang}: ${name}"
done

# ---------- 5. start ----------
step "5/6  Starting the voice service"
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d --force-recreate >/dev/null
wait_healthy voice
docker exec voice python -c "import urllib.request; print('  ', urllib.request.urlopen('http://localhost:5000/health').read().decode())"

# ---------- 6. round trips ----------
step "6/6  Round-trip tests: speak, then listen"
TMP=$(mktemp -d)
speak() {  # speak <engine> <file>  -> prints the engine that answered
  docker exec voice python -c "
import json, sys, urllib.request
req = urllib.request.Request('http://localhost:5000/speak', headers={'Content-Type': 'application/json'},
      data=json.dumps({'text': 'Hello Ahmad, this is Jarvis. Voice is working.', 'engine': '$1'}).encode())
try:
    r = urllib.request.urlopen(req, timeout=90); open('/tmp/t.ogg', 'wb').write(r.read()); print(r.headers.get('X-Voice-Engine'))
except Exception as e: print('FAILED', getattr(e, 'code', type(e).__name__))"
  docker cp voice:/tmp/t.ogg "$2" >/dev/null 2>&1 || true; }
listen() {  # listen <model> <file>
  local m; m=$(gw_get LITELLM_MASTER_KEY)
  curl -s --max-time 90 http://127.0.0.1:4000/v1/audio/transcriptions -H @<(printf "Authorization: Bearer %s" "$m") \
    -F file=@"$2" -F model="$1" | python3 -c 'import json,sys
try: d=json.load(sys.stdin); print(d.get("text") or "FAILED: "+str(d.get("error",d))[:140])
except Exception as e: print("FAILED:", e)'; }

CLOUD=$(speak cloud "$TMP/cloud.ogg")
printf "  %-34s %s\n" "voice (cloud, ElevenLabs):" "$CLOUD"
case "$CLOUD" in FAILED*) docker restart voice >/dev/null; wait_healthy voice ;; esac   # clear the 1-hour cloud pause
printf "  %-34s %s\n" "voice (local, Piper fallback):" "$(speak local "$TMP/local.ogg")"
SAMPLE="$TMP/local.ogg"; [ -s "$TMP/cloud.ogg" ] && SAMPLE="$TMP/cloud.ogg"
if [ -s "$SAMPLE" ]; then
  printf "  %-34s %s\n" "ears 'listen' heard:" "$(listen listen "$SAMPLE")"
  grep -q "model_name: listen-backup" "$GW/config.yaml" && printf "  %-34s %s\n" "ears 'listen-backup' heard:" "$(listen listen-backup "$SAMPLE")"
else
  warn "No audio was produced, so the ears couldn't be tested."
fi
rm -rf "$TMP"

step "Done!"
echo "  Ears : gateway 'listen' (+ 'listen-backup')  →  http://litellm:4000/v1/audio/transcriptions"
echo "  Voice: voice service, cloud first then local →  http://voice:5000/speak"
echo
echo "A 'FAILED' on the cloud lines usually means the ElevenLabs key lacks a permission"
echo "(Text to Speech / Speech to Text) or the free credits are used up. Jarvis still works via the backups."
echo "Next: add voice to your 'Jarvis chat' workflow in n8n (Lesson 11, Part D)."
