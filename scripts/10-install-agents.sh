#!/usr/bin/env bash
# free-ai-lab - Lesson 10: install the "Jarvis agents" workflow (with the Reminders agent) into n8n for you.
#   bash 10-install-agents.sh
# What it does, using n8n's own command line inside the n8n container:
#   1. makes sure Jarvis Live is the Lesson 10 version (runs 09-install-live.sh if not)
#   2. creates or corrects the "Jarvis Live secret" credential (the same secret Jarvis Live uses)
#   3. finds your Telegram credential and your Telegram ID (from the "Only me" node of Lesson 07)
#   4. unpublishes the old Lesson 09 "Jarvis agents", imports the new one, connects credentials, publishes it
#   5. restarts n8n and runs 10-check-agents.sh
# Run it again any time: it updates the same workflow. Keys and secrets are never printed.
set -euo pipefail
c_ok='\033[1;32m'; c_bad='\033[1;31m'; c_step='\033[1;36m'; c_off='\033[0m'
step() { echo -e "\n${c_step}$*${c_off}"; }
die()  { echo -e "${c_bad}✗ $*${c_off}"; exit 1; }
ok()   { echo -e "${c_ok}✓${c_off} $*"; }
RAW="${FAL_RAW:-https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main}"
LIVE_ENV="$HOME/lab/live/.env"
WF_ID="JarvisAgents0001"            # fixed ID, so running this again updates the same workflow
TMP=$(mktemp -d); chmod 700 "$TMP"
cleanup() { rm -rf "$TMP"; docker exec n8n sh -c 'rm -f /tmp/fal-*' >/dev/null 2>&1 || true; }
trap cleanup EXIT
n8n_cli() { docker exec -u node n8n n8n "$@" 2>&1; }

step "1/6  Jarvis Live and n8n are running"
docker ps --format '{{.Names}}' | grep -qx n8n || die "n8n isn't running (Lesson 06). Check: docker ps -a"
docker ps --format '{{.Names}}' | grep -qx jarvis-live || die "Jarvis Live isn't running (Lesson 09)."
ver=$(docker exec jarvis-live node -e "fetch('http://127.0.0.1:8080/health').then(r=>r.json()).then(j=>console.log(j.version||'old')).catch(()=>console.log('old'))" 2>/dev/null || echo old)
if [ "$ver" != "10" ]; then
  echo "  Jarvis Live is an older version: updating it first (your password, keys and providers are kept)."
  curl -fsSL "$RAW/scripts/09-install-live.sh" -o "$TMP/09.sh" && bash "$TMP/09.sh"
fi
ok "Jarvis Live is the Lesson 10 version; n8n $(docker exec n8n n8n --version 2>/dev/null | tail -1)"
SECRET=$(grep -E '^N8N_TOOL_SECRET=' "$LIVE_ENV" | cut -d= -f2-)
[ -n "$SECRET" ] || die "No N8N_TOOL_SECRET in $LIVE_ENV. Run 09-install-live.sh."

step "2/6  Credentials in n8n"
# exported encrypted: only names, types and IDs are read here
if n8n_cli export:credentials --all --output=/tmp/fal-creds.json >/dev/null; then
  docker exec n8n cat /tmp/fal-creds.json > "$TMP/creds.json" 2>/dev/null || echo '[]' > "$TMP/creds.json"
else echo '[]' > "$TMP/creds.json"; fi
read -r SECRET_ID TG_IDS < <(python3 - "$TMP/creds.json" <<'PY'
import json, sys, secrets, string
try: creds = json.load(open(sys.argv[1]))
except Exception: creds = []
sec = [c for c in creds if c.get('type') == 'httpHeaderAuth' and c.get('name') == 'Jarvis Live secret']
new = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
tg = [c for c in creds if c.get('type') == 'telegramApi']
tg.sort(key=lambda c: c.get('name') != 'Jarvis bot')
print(sec[0]['id'] if sec else new, ','.join(f"{c['id']}:{c['name'].replace(' ', '~')}" for c in tg) or '-')
PY
)
# write (or overwrite) "Jarvis Live secret" with the exact secret Jarvis Live uses
FAL_SECRET="$SECRET" python3 - "$TMP/secret.json" "$SECRET_ID" <<'PY'
import json, os, sys
json.dump([{"id": sys.argv[2], "name": "Jarvis Live secret", "type": "httpHeaderAuth",
            "data": {"name": "X-Jarvis-Secret", "value": os.environ["FAL_SECRET"]}}], open(sys.argv[1], "w"))
PY
chmod 600 "$TMP/secret.json"
docker cp "$TMP/secret.json" n8n:/tmp/fal-secret.json >/dev/null
docker exec -u 0 n8n chown node /tmp/fal-secret.json
out=$(n8n_cli import:credentials --input=/tmp/fal-secret.json) || { echo "$out" | tail -5; die "n8n couldn't save the 'Jarvis Live secret' credential."; }
docker exec n8n rm -f /tmp/fal-secret.json; rm -f "$TMP/secret.json"
ok "credential 'Jarvis Live secret' matches Jarvis Live's secret"

[ "$TG_IDS" != "-" ] || die "No Telegram credential found in n8n. Create it as in Lesson 07, Part A (name: Jarvis bot), then run this again."
IFS=',' read -r -a TGS <<< "$TG_IDS"
TG_CRED="${TGS[0]%%:*}"; TG_NAME="${TGS[0]#*:}"; TG_NAME="${TG_NAME//\~/ }"
if [ "${#TGS[@]}" -gt 1 ] && [ "$TG_NAME" != "Jarvis bot" ]; then
  echo "  Several Telegram credentials:"; i=1; for t in "${TGS[@]}"; do n="${t#*:}"; echo "   $i) ${n//\~/ }"; i=$((i+1)); done
  read -r -p "  Which one is your Jarvis bot? [1] " pick; pick=${pick:-1}
  TG_CRED="${TGS[$((pick-1))]%%:*}"; TG_NAME="${TGS[$((pick-1))]#*:}"; TG_NAME="${TG_NAME//\~/ }"
fi
ok "Telegram credential: $TG_NAME"

step "3/6  Your Telegram ID (who receives reminders)"
n8n_cli export:workflow --all --output=/tmp/fal-wfs.json >/dev/null || true
docker exec n8n cat /tmp/fal-wfs.json > "$TMP/wfs.json" 2>/dev/null || echo '[]' > "$TMP/wfs.json"
TGID=$(python3 - "$TMP/wfs.json" <<'PY'
import json, sys, re
try: wfs = json.load(open(sys.argv[1]))
except Exception: wfs = []
found = []
for w in wfs:
    for n in w.get('nodes', []):
        p = json.dumps(n.get('parameters', {}))
        if n.get('name', '').lower() == 'only me' or 'message.from.id' in p:
            found += re.findall(r'"rightValue":\s*"?(-?\d{5,15})"?', p)
print(found[0] if found else '')
PY
)
if [ -n "$TGID" ]; then
  read -r -p "  Found Telegram ID $TGID in your 'Only me' node. Use it? [Y/n] " yn
  case "${yn:-y}" in [Nn]*) TGID="";; esac
fi
while ! [[ "$TGID" =~ ^-?[0-9]{5,15}$ ]]; do
  read -r -p "  Your Telegram ID (the number in Lesson 07's 'Only me' node): " TGID
done
ok "reminders go to Telegram ID $TGID"

step "4/6  Old 'Jarvis agents' workflows"
while read -r oid; do
  [ -n "$oid" ] && [ "$oid" != "$WF_ID" ] || continue
  n8n_cli unpublish:workflow --id="$oid" >/dev/null 2>&1 || n8n_cli update:workflow --id="$oid" --active=false >/dev/null 2>&1 || true
  ok "unpublished the old one (ID $oid). You can archive it in n8n later"
done < <(n8n_cli list:workflow | sed -nE 's/^(.*[^A-Za-z0-9])?([A-Za-z0-9]{8,})\|Jarvis agents[[:space:]]*$/\2/p')

step "5/6  Import and publish the new 'Jarvis agents'"
curl -fsSL "$RAW/stacks/jarvis/workflows/jarvis-agents.json" -o "$TMP/wf.json"
python3 - "$TMP/wf.json" "$WF_ID" "$SECRET_ID" "$TG_CRED" "$TG_NAME" "$TGID" "$TMP/wfs.json" <<'PY'
import json, sys, uuid
f, wid, sid, tid, tname, tgid, old = sys.argv[1:]
w = json.load(open(f))
w.update({"id": wid, "active": False, "versionId": str(uuid.uuid4())})
try:   # keep reminders already saved, when this runs again
    prev = [x for x in json.load(open(old)) if x.get("id") == wid]
    if prev and prev[0].get("staticData"): w["staticData"] = prev[0]["staticData"]
except Exception: pass
sec = {"httpHeaderAuth": {"id": sid, "name": "Jarvis Live secret"}}
for n in w["nodes"]:
    if n["type"] in ("n8n-nodes-base.webhook", "n8n-nodes-base.httpRequest"): n["credentials"] = sec
    if n["type"] == "n8n-nodes-base.telegram":
        n["credentials"] = {"telegramApi": {"id": tid, "name": tname}}; n["parameters"]["chatId"] = tgid
json.dump(w, open(f, "w"))
PY
docker cp "$TMP/wf.json" n8n:/tmp/fal-wf.json >/dev/null
docker exec -u 0 n8n chown node /tmp/fal-wf.json
out=$(n8n_cli import:workflow --input=/tmp/fal-wf.json) || { echo "$out" | tail -8; die "n8n couldn't import the workflow."; }
ok "imported (reminders you already had are kept)"
if ! out=$(n8n_cli publish:workflow --id="$WF_ID"); then
  out2=$(n8n_cli update:workflow --id="$WF_ID" --active=true) || { echo "$out"; echo "$out2" | tail -5; die "n8n couldn't publish the workflow."; }
fi
echo "$out" | grep -iE "error|conflict|already" && die "Publishing reported a problem (above)." || true
ok "published"

step "6/6  Restart n8n so the webhooks and the every-minute check start"
docker restart n8n >/dev/null
for i in $(seq 1 40); do
  s=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}running{{end}}' n8n 2>/dev/null || echo starting)
  code=$(docker exec n8n node -e "fetch('http://localhost:5678/healthz').then(r=>console.log(r.status)).catch(()=>console.log(0))" 2>/dev/null || echo 0)
  [ "$code" = 200 ] && break; sleep 3
done
[ "$code" = 200 ] || die "n8n didn't come back. Check: docker logs --tail 40 n8n"
ok "n8n is back"

echo
curl -fsSL "$RAW/scripts/10-check-agents.sh" -o "$TMP/check.sh" && bash "$TMP/check.sh"
