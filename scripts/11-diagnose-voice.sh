#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 11: find out WHY the ElevenLabs voice fails
#
# Run ON THE VM as ubuntu:   bash 11-diagnose-voice.sh
# Never prints keys. Safe to share the output.
# =============================================================================
set -uo pipefail
GW="$HOME/lab/gateway"
c_ok="\033[32m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
get() { grep -E "^$1=" "$GW/.env" | head -1 | cut -d= -f2-; }
mask() { sed -E 's/(sk-|xi-|sk_)[A-Za-z0-9_-]{6,}/\1***/g'; }
TMP=$(mktemp -d)

VOICE=$(grep -E '^CLOUD_VOICE=' "$HOME/lab/voice/.env" 2>/dev/null | cut -d= -f2-); VOICE="${VOICE:-JBFqnCBsd6RMkjVDRZzb}"
step "1/4  Voice through the gateway ('speak', voice $VOICE)"
code=$(curl -s -o "$TMP/a" -w '%{http_code}' --max-time 60 http://127.0.0.1:4000/v1/audio/speech \
  -H @<(printf "Authorization: Bearer %s" "$(get LITELLM_MASTER_KEY)") -H "Content-Type: application/json" \
  -d '{"model":"speak","input":"Hello Ahmad","voice":"'"$VOICE"'","response_format":"mp3"}')
echo "  HTTP $code  ($(file -b "$TMP/a" | cut -c1-40))"
[ "$code" = 200 ] || { echo -n "  reason: "; head -c 500 "$TMP/a" | mask; echo; }

step "2/4  Your ElevenLabs key: plan and credits"
code=$(curl -s -o "$TMP/sub" -w '%{http_code}' --max-time 30 https://api.elevenlabs.io/v1/user/subscription \
  -H @<(printf "xi-api-key: %s" "$(get ELEVENLABS_API_KEY)"))
if [ "$code" = 200 ]; then
  python3 -c 'import json; d=json.load(open("'"$TMP/sub"'")); print("  plan:", d.get("tier"), "| credits used:", d.get("character_count"), "of", d.get("character_limit"))'
else
  echo -n "  HTTP $code: "; head -c 300 "$TMP/sub" | mask; echo "   (a missing 'User read' permission is fine)"
fi

step "3/4  Voices your key can use (pre-made voices work on the free plan)"
code=$(curl -s -o "$TMP/v" -w '%{http_code}' --max-time 30 "https://api.elevenlabs.io/v1/voices" \
  -H @<(printf "xi-api-key: %s" "$(get ELEVENLABS_API_KEY)"))
if [ "$code" = 200 ]; then
  python3 -c '
import json; d=json.load(open("'"$TMP/v"'"))
vs=[v for v in d.get("voices",[]) if v.get("category")=="premade"] or d.get("voices",[])
for v in vs[:8]: print("  ", v["voice_id"], "|", v.get("name"), "|", (v.get("labels") or {}).get("gender",""))'
  FIRST=$(python3 -c 'import json; d=json.load(open("'"$TMP/v"'")); vs=[v for v in d.get("voices",[]) if v.get("category")=="premade"] or d.get("voices",[]); print(vs[0]["voice_id"] if vs else "")')
else
  echo -n "  HTTP $code: "; head -c 300 "$TMP/v" | mask; echo; FIRST=""
fi

step "4/4  Direct ElevenLabs test with a pre-made voice (bypassing the gateway)"
if [ -n "$FIRST" ]; then
  code=$(curl -s -o "$TMP/d" -w '%{http_code}' --max-time 60 \
    "https://api.elevenlabs.io/v1/text-to-speech/$FIRST?output_format=mp3_44100_128" \
    -H @<(printf "xi-api-key: %s" "$(get ELEVENLABS_API_KEY)") -H "Content-Type: application/json" \
    -d '{"text":"Hello Ahmad","model_id":"eleven_v3"}')
  echo "  voice $FIRST: HTTP $code  ($(file -b "$TMP/d" | cut -c1-40))"
  [ "$code" = 200 ] || { echo -n "  reason: "; head -c 400 "$TMP/d" | mask; echo; }
else
  echo "  skipped (no voice list)"
fi

step "Voice service log (last lines)"
docker logs --tail 15 voice 2>&1 | mask | sed 's/^/  /'
rm -rf "$TMP"
echo; echo "Copy everything above and send it (no keys are shown)."
