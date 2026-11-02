#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 10: give Jarvis ears and a voice (server side)
#
# Run ON THE SERVER as ubuntu (no sudo):
#   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/10-install-voice.sh -o 10-install-voice.sh && bash 10-install-voice.sh
#
# What it does:
#   1. Asks for your ElevenLabs API key (hidden; Enter keeps / skips) -> ~/lab/brain/.env
#   2. Gateway: 'listen' = ElevenLabs Scribe (backup: Groq Whisper), 'speak' = ElevenLabs v3 (speaks Urdu)
#   3. Builds the voice service: cloud voice first, local Piper when credits run out
#   4. Downloads Piper voices (English, Arabic, Urdu) for the fallback
#   5. Tests both voices and the ears with a speak-then-listen round trip
#
# Everything in n8n (the Telegram workflow) stays in the n8n UI: see Lesson 10, Part D.
# Safe to re-run.
# =============================================================================
set -uo pipefail

RAW="${RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
GW="$HOME/lab/brain"
DIR="$HOME/lab/voice"
ENVF="$DIR/.env"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo missing; }
wait_healthy() { local w=0; until [ "$(health "$1")" = "healthy" ]; do
  (( w >= ${2:-180} )) && { docker logs --tail 30 "$1"; die "$1 didn't become healthy."; }; sleep 5; w=$((w+5)); done; }
gw_get() { grep -m1 "^$1=" "$GW/.env" 2>/dev/null | cut -d= -f2- || true; }
gw_set() { local t="$GW/.env.tmp"; grep -v "^$1=" "$GW/.env" > "$t" || true
           printf '%s=%s\n' "$1" "$2" >> "$t"; mv "$t" "$GW/.env"; chmod 600 "$GW/.env"; }

[ "$(id -u)" -ne 0 ] || die "Run WITHOUT sudo, as ubuntu:  bash $0"
sudo -n true 2>/dev/null || die "Your user needs passwordless sudo (Oracle's ubuntu user has it)."
docker network inspect jarvis >/dev/null 2>&1 || die "The 'jarvis' network is missing. Do Lesson 06 first."
[ -f "$GW/.env" ] || die "The brain isn't installed (Lesson 06)."

# ---------- 1. ElevenLabs key ----------
step "1/6  ElevenLabs API key (typed hidden; nothing appears while you paste: that's normal)"
echo "  elevenlabs.io → Developers → API Keys → Create. Permissions: Text to Speech + Speech to Text."
echo "  Copy the SECRET key (starts with sk_, shown once), not the Key ID."
cur=$(gw_get ELEVENLABS_API_KEY)
if [ -n "$cur" ] && [ "$cur" != "not-set" ]; then hint="saved ...${cur: -4}, Enter keeps it"; else hint="not set, Enter skips"; fi
read -r -s -p "  ElevenLabs key ($hint): " val; echo
val="${val//[[:space:]]/}"
if [ -n "$val" ] && [ "${val#sk_}" = "$val" ]; then
  warn "That doesn't start with 'sk_', so it's not the secret key (probably the Key ID). NOT saved."
  warn "Create a new key in ElevenLabs and copy the value starting with sk_. Then run this script again."
  val=""
fi
if [ -n "$val" ]; then gw_set ELEVENLABS_API_KEY "$val"; echo "    received ${#val} characters, starting sk_ and ending in ...${val: -4}"
elif [ -z "$cur" ]; then gw_set ELEVENLABS_API_KEY not-set; echo "    skipped: ears = Groq Whisper, voice = local Piper only"
else echo "    kept"; fi
unset val cur

# ---------- 2. gateway ----------
step "2/6  Gateway: ears ('listen') and voice ('speak')"
curl -fsSL "$RAW/scripts/06-pick-models.py" -o "$GW/pick-models.py"
python3 "$GW/pick-models.py" | grep -E "listen|speak|elevenlabs|smart  |WARNING" || true
docker compose -f "$GW/compose.yaml" --project-directory "$GW" up -d --no-deps --force-recreate litellm >/dev/null
wait_healthy litellm 240
echo "Gateway restarted with: $(grep -oE 'model_name: (listen|listen-backup|speak)' "$GW/config.yaml" | cut -d' ' -f2 | tr '\n' ' ')"

# ---------- 3. voice service ----------
step "3/6  Voice service: building (the first build takes a few minutes)"
mkdir -p "$DIR/voices"
for f in compose.yaml Dockerfile server.py; do curl -fsSL "$RAW/stacks/voice/$f" -o "$DIR/$f" || die "Couldn't download $f"; done
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" build -q || die "The build failed (see above)."
sudo -n chown -R 1000:1000 "$DIR/voices"

# ---------- 4. settings + local fallback voices ----------
step "4/6  Local fallback voices (English, Arabic, Urdu) and your cloud voice"
piper() { docker run --rm --user 1000 -v "$DIR/voices:/voices" free-ai-lab/voice:local python -m piper.download_voices "$@"; }
ALL=$(piper 2>/dev/null || true)
[ -n "$ALL" ] || warn "Couldn't list Piper voices (is huggingface.co reachable?). The local fallback voice won't work."
pick() { local pref="${2:-}"
  if [ -n "$pref" ] && echo "$ALL" | grep -qx "$pref"; then echo "$pref"; return; fi
  echo "$ALL" | grep "^$1" | grep -- "-medium$" | head -1 || true; }
VEN=$(pick en_US en_US-lessac-medium); VAR=$(pick ar_); VUR=$(pick ur_)
[ -n "$VUR" ] || VUR=$(echo "$ALL" | grep "^ur_" | head -1 || true)

OLD_VOICE=$(grep -m1 '^CLOUD_VOICE=' "$ENVF" 2>/dev/null | cut -d= -f2- || true)
umask 077; : > "$ENVF"; umask 022
echo "GATEWAY_URL=http://litellm:4000/v1" >> "$ENVF"
if grep -q "model_name: speak" "$GW/config.yaml"; then
  echo "GATEWAY_KEY=$(gw_get LITELLM_MASTER_KEY)" >> "$ENVF"
  echo "CLOUD_MODEL=speak" >> "$ENVF"
  DEFAULT_VOICE="${OLD_VOICE:-JBFqnCBsd6RMkjVDRZzb}"
  echo "  Cloud voice: the free ElevenLabs plan can only use PRE-MADE voices through the API, e.g."
  echo "    JBFqnCBsd6RMkjVDRZzb George (male)    EXAVITQu4vr4xnSDxMaL Sarah (female)"
  echo "    CwhRBWXzGAHq8TQ4Fs17 Roger (male)     FGY2WhTYpPnrIDTdsKH5 Laura (female)"
  read -r -p "  Voice ID (Enter = $DEFAULT_VOICE): " VID
  VID="${VID:-$DEFAULT_VOICE}"; VID="${VID//[[:space:]]/}"
  echo "CLOUD_VOICE=$VID" >> "$ENVF"
else
  echo "  No ElevenLabs key: Jarvis speaks with the local Piper voice only."
fi
for pair in "EN:$VEN" "AR:$VAR" "UR:$VUR"; do
  lang="${pair%%:*}"; name="${pair#*:}"
  if [ -z "$name" ]; then warn "No local voice for ${lang}."; continue; fi
  piper "$name" --data-dir /voices >/dev/null 2>&1 || { warn "Download failed for $name"; continue; }
  echo "VOICE_${lang}=${name}.onnx" >> "$ENVF"; echo "  local ${lang}: ${name}"
done

# ---------- 5. start ----------
step "5/6  Starting the voice service"
docker compose -f "$DIR/compose.yaml" --project-directory "$DIR" up -d --force-recreate >/dev/null
wait_healthy voice
docker exec voice python -c "import urllib.request; print('  ', urllib.request.urlopen('http://localhost:5000/health').read().decode())"
docker exec n8n node -e "fetch('http://voice:5000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" >/dev/null 2>&1 \
  && echo "  n8n can reach the voice at http://voice:5000" || warn "n8n can't reach http://voice:5000 (is n8n on the 'jarvis' network? Lesson 08)"

# ---------- 6. round trips ----------
step "6/6  Round-trip tests: Jarvis speaks, then listens to itself"
TMP=$(mktemp -d)
speak() {  # speak <engine> <file>  -> prints the engine that answered
  docker exec voice python -c "
import json, urllib.request
req = urllib.request.Request('http://localhost:5000/speak', headers={'Content-Type': 'application/json'},
      data=json.dumps({'text': 'Hello, this is Jarvis. My voice is working.', 'engine': '$1'}).encode())
try:
    r = urllib.request.urlopen(req, timeout=90); open('/tmp/t.ogg', 'wb').write(r.read()); print(r.headers.get('X-Voice-Engine'))
except Exception as e: print('FAILED', getattr(e, 'code', type(e).__name__))"
  docker cp voice:/tmp/t.ogg "$2" >/dev/null 2>&1 || true; }
listen() {  # listen <model> <file>
  local m; m=$(gw_get LITELLM_MASTER_KEY)
  curl -s --max-time 90 http://127.0.0.1:4000/v1/audio/transcriptions -H @<(printf "Authorization: Bearer %s" "$m") \
    -F file=@"$2" -F model="$1" | python3 -c 'import json,sys
try: d=json.load(sys.stdin); print(d.get("text") or "FAILED: "+str(d.get("error",d))[:160])
except Exception as e: print("FAILED:", e)'; }

if grep -q "model_name: speak" "$GW/config.yaml"; then
  CLOUD=$(speak cloud "$TMP/cloud.ogg")
  printf "  %-30s %s\n" "voice (cloud, ElevenLabs):" "$CLOUD"
  case "$CLOUD" in FAILED*) echo "  Reason (from the voice service):"; docker logs --tail 5 voice 2>&1 | grep -i "cloud voice" | sed 's/^/    /'
                            docker restart voice >/dev/null; wait_healthy voice ;; esac
fi
rm -f "$TMP/local.ogg"; docker exec voice rm -f /tmp/t.ogg >/dev/null 2>&1
printf "  %-30s %s\n" "voice (local, Piper backup):" "$(speak local "$TMP/local.ogg")"
SAMPLE="$TMP/local.ogg"; [ -s "$TMP/cloud.ogg" ] && SAMPLE="$TMP/cloud.ogg"
if [ -s "$SAMPLE" ]; then
  printf "  %-30s %s\n" "ears 'listen' heard:" "$(listen listen "$SAMPLE")"
  grep -q "model_name: listen-backup" "$GW/config.yaml" && printf "  %-30s %s\n" "ears 'listen-backup' heard:" "$(listen listen-backup "$SAMPLE")"
else
  warn "No audio was produced, so the ears couldn't be tested."
fi
rm -rf "$TMP"

step "Done! Server side is ready."
echo "  Ears : gateway 'listen'  → http://litellm:4000/v1/audio/transcriptions"
echo "  Voice: voice service     → http://voice:5000/speak (cloud first, local backup)"
echo
echo "Next, in the n8n UI: import the voice version of the Telegram workflow (Lesson 10, Part D)."
echo "A FAILED cloud line usually means the ElevenLabs key lacks a permission, a library (not pre-made)"
echo "voice was chosen, or the free credits are used up. Jarvis still speaks with the local backup."
