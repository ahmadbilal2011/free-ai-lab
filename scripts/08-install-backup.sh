#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 08 (part 2): encrypted nightly backups + monitoring
#
# Run ON THE VM:
#   sudo bash 08-install-backup.sh
#
# Installs:
#   restic                 encrypted, deduplicated backups to Oracle Object Storage
#   /usr/local/bin/lab-backup        the backup job (also runnable by hand)
#   /usr/local/bin/lab-restore-test  proves a backup can really be restored
#   /usr/local/bin/lab-status        one-screen health check of the whole lab
#   systemd timers         backup every night 03:30, heartbeat every 5 minutes
#
# Secrets go to /etc/free-ai-lab/backup.env (root only, never committed).
# Safe to re-run: press Enter to keep saved values.
# =============================================================================
set -euo pipefail

CONF_DIR=/etc/free-ai-lab
CONF="$CONF_DIR/backup.env"
LOGIN_USER="${SUDO_USER:-ubuntu}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo:  sudo bash $0"

conf_get() { grep -E "^$1=" "$CONF" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//' || true; }
conf_set() { local tmp; tmp=$(mktemp); grep -vE "^$1=" "$CONF" > "$tmp" 2>/dev/null || true
             printf '%s="%s"\n' "$1" "$2" >> "$tmp"; cat "$tmp" > "$CONF"; rm -f "$tmp"; }
ask() {  # ask VAR "Question" [secret]
  local var="$1" q="$2" secret="${3:-}" cur val; cur=$(conf_get "$var")
  local hint="Enter keeps current"; [ -z "$cur" ] && hint="required"
  [ -n "$secret" ] && [ -n "$cur" ] && hint="saved ...${cur: -4}, Enter keeps it"
  [ -z "$secret" ] && [ -n "$cur" ] && hint="current: $cur"
  if [ -n "$secret" ]; then read -r -s -p "  $q ($hint): " val; echo; else read -r -p "  $q ($hint): " val; fi
  val=$(printf '%s' "$val" | tr -d '[:space:]')
  [ -n "$val" ] && conf_set "$var" "$val"
  [ -n "$(conf_get "$var")" ] || [ "$var" = HC_BACKUP_URL ] || [ "$var" = HC_HEARTBEAT_URL ] || die "$var is required."
}

# ---------- 1. restic ----------
step "1/6  Installing restic"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
apt-get update -q >/dev/null
apt-get install -y -q restic curl >/dev/null
echo "restic $(restic version | awk '{print $2}')"

# ---------- 2. settings ----------
step "2/6  Backup settings (from 08-create-backup-bucket.sh in Cloud Shell)"
install -d -m 700 "$CONF_DIR"; touch "$CONF"; chmod 600 "$CONF"
ask S3_ENDPOINT "S3 endpoint (https://...customer-oci.com)"
ask S3_BUCKET   "Bucket"
ask S3_REGION   "Region (e.g. me-riyadh-1)"
ask AWS_ACCESS_KEY_ID     "Access key"
ask AWS_SECRET_ACCESS_KEY "Secret key (hidden)" secret
echo
echo "  Monitoring (optional, free at https://healthchecks.io). Paste ping URLs, or Enter to skip:"
ask HC_BACKUP_URL    "Backup check URL"
ask HC_HEARTBEAT_URL "Heartbeat check URL"
[ -n "$(conf_get BACKUP_STOP)" ] || conf_set BACKUP_STOP "open-webui"
[ -n "$(conf_get BACKUP_EXCLUDE_VOLUMES)" ] || conf_set BACKUP_EXCLUDE_VOLUMES "ai_ollama"
conf_set RESTIC_REPOSITORY "s3:$(conf_get S3_ENDPOINT)/$(conf_get S3_BUCKET)/restic"

NEW_PASSWORD=""
if [ -z "$(conf_get RESTIC_PASSWORD)" ]; then
  NEW_PASSWORD=$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-32)
  conf_set RESTIC_PASSWORD "$NEW_PASSWORD"
fi

# ---------- 3. repository ----------
step "3/6  Connecting to the backup repository"
set -a; . "$CONF"; set +a
R=(restic -o "s3.region=$S3_REGION")
if "${R[@]}" cat config >/dev/null 2>&1; then
  echo "Repository already exists and the password matches."
else
  "${R[@]}" init || die "Could not create the repository. Check endpoint, bucket, region and keys."
  echo "New encrypted repository created."
fi

if [ -n "$NEW_PASSWORD" ]; then
  echo
  echo -e "${c_warn}=================== SAVE THIS NOW ===================${c_off}"
  echo -e "  Backup encryption password:  ${c_ok}${NEW_PASSWORD}${c_off}"
  echo "  Without it, NOBODY (not even you) can restore the backups."
  echo "  If the server is lost, this file is lost with it."
  echo "  Put it in a password manager (with the Oracle secret key), NOT on GitHub."
  echo -e "${c_warn}=====================================================${c_off}"
  read -r -p "  Type SAVED when it's safely stored: " ok
  [ "$ok" = "SAVED" ] || warn "You can show it later with: sudo grep RESTIC_PASSWORD $CONF"
  clear 2>/dev/null || true
fi
unset NEW_PASSWORD

# ---------- 4. tools ----------
step "4/6  Installing lab-backup, lab-restore-test, lab-status"
cat > /usr/local/bin/lab-backup <<'EOF'
#!/usr/bin/env bash
# free-ai-lab nightly backup. Run by hand any time:  sudo lab-backup
set -uo pipefail
set -a; . /etc/free-ai-lab/backup.env; set +a
R=(restic -o "s3.region=$S3_REGION")
hc() { [ -n "${HC_BACKUP_URL:-}" ] && curl -fsS -m 10 --retry 3 "${HC_BACKUP_URL}$1" >/dev/null 2>&1 || true; }
STOPPED=()
restart() { for c in "${STOPPED[@]}"; do docker start "$c" >/dev/null && echo "started $c again"; done; STOPPED=(); }
trap restart EXIT                                   # containers always come back, even on error
hc /start

# 1. Pause apps that use SQLite files, so the copy is consistent (about 30 seconds)
for c in $BACKUP_STOP; do
  if [ -n "$(docker ps -q -f "name=^${c}$")" ]; then docker stop -t 30 "$c" >/dev/null && STOPPED+=("$c") && echo "paused $c"; fi
done

# 2. What we back up: lab folders (compose files, configs, .env keys) + every Docker volume except big re-downloadable ones
PATHS=(/home/ubuntu/lab)
for v in $(docker volume ls -q); do
  case " $BACKUP_EXCLUDE_VOLUMES " in *" $v "*) continue ;; esac
  PATHS+=("/var/lib/docker/volumes/$v/_data")
done
"${R[@]}" backup --host free-ai-lab --tag lab "${PATHS[@]}"; RC=$?
restart

# 3. Keep 7 daily, 4 weekly, 6 monthly; tidy once a week (saves API requests)
if [ "$RC" -eq 0 ] && [ "$(date +%u)" = 7 ]; then
  "${R[@]}" forget --host free-ai-lab --tag lab --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune || RC=$?
fi
if [ "$RC" -eq 0 ]; then hc ""; echo "Backup OK"; else hc /fail; echo "Backup FAILED (code $RC)"; fi
exit "$RC"
EOF

cat > /usr/local/bin/lab-restore-test <<'EOF'
#!/usr/bin/env bash
# Restore the latest backup into a temporary folder and check key files. Changes nothing live.
set -euo pipefail
set -a; . /etc/free-ai-lab/backup.env; set +a
R=(restic -o "s3.region=$S3_REGION")
DEST=$(mktemp -d /tmp/lab-restore-test.XXXX)
echo "Snapshots in the repository:"; "${R[@]}" snapshots --compact
echo; echo "Restoring the latest snapshot into $DEST ..."
"${R[@]}" restore latest --target "$DEST" >/dev/null
check() { if [ -e "$DEST$1" ]; then echo "  OK    $1"; else echo "  MISSING $1"; FAIL=1; fi; }
FAIL=0
check /home/ubuntu/lab/ai/compose.yaml
check /home/ubuntu/lab/ai/.env
check /home/ubuntu/lab/gateway/.env
check /home/ubuntu/lab/gateway/config.yaml
check /var/lib/docker/volumes/ai_open-webui/_data/webui.db
echo "  Restored size: $(du -sh "$DEST" | cut -f1)"
rm -rf "$DEST"
[ "$FAIL" -eq 0 ] && echo "RESTORE TEST PASSED" || { echo "RESTORE TEST FAILED"; exit 1; }
EOF

cat > /usr/local/bin/lab-status <<'EOF'
#!/usr/bin/env bash
# One-screen health check of the lab. Use 'sudo lab-status' to include backup info.
G="\033[32m"; Y="\033[33m"; Rd="\033[31m"; N="\033[0m"
echo -e "== free-ai-lab status  $(date '+%Y-%m-%d %H:%M %Z') =="
echo; echo "Containers:"
docker ps -a --format '  {{.Names}}\t{{.Status}}' | sed -e "s/(healthy)/$(printf "$G")(healthy)$(printf "$N")/" \
  -e "s/(unhealthy)/$(printf "$Rd")(unhealthy)$(printf "$N")/" -e "s/Exited/$(printf "$Rd")Exited$(printf "$N")/"
MEM=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%d", (t-a)*100/t}' /proc/meminfo)
DISK=$(df --output=pcent / | tail -1 | tr -dc '0-9')
echo; echo "Server:"
echo "  Memory used : ${MEM}%  $([ "$MEM" -lt 20 ] && printf "$Y(below 20%%: Oracle may treat an idle A1 VM as reclaimable, see Lesson 08)$N")"
echo "  Disk used   : ${DISK}%  $([ "$DISK" -gt 85 ] && printf "$Rd(getting full: docker image prune)$N")"
echo "  Swap        : $(free -h | awk '/Swap/{print $3" / "$2}')"
echo "  Load (1m)   : $(cut -d' ' -f1 /proc/loadavg) on $(nproc) CPUs"
echo "  Uptime      : $(uptime -p)"
command -v tailscale >/dev/null && echo "  Tailscale   : $(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("BackendState","?"), d["Self"]["DNSName"].rstrip("."))' 2>/dev/null || echo unknown)"
if [ "$(id -u)" -eq 0 ] && [ -f /etc/free-ai-lab/backup.env ]; then
  set -a; . /etc/free-ai-lab/backup.env; set +a
  LAST=$(restic -o "s3.region=$S3_REGION" snapshots --latest 1 --json 2>/dev/null | python3 -c 'import json,sys; s=json.load(sys.stdin); print(s[-1]["time"][:16].replace("T"," ") if s else "none")' 2>/dev/null || echo "unreachable")
  echo; echo "Backups:"; echo "  Last backup : $LAST (UTC)"
  echo "  Next run    : $(systemctl list-timers lab-backup.timer --no-legend 2>/dev/null | awk '{print $1, $2, $3}')"
else
  echo; echo "(run 'sudo lab-status' to include backups)"
fi
EOF
chmod 755 /usr/local/bin/lab-backup /usr/local/bin/lab-restore-test /usr/local/bin/lab-status

# ---------- 5. timers ----------
step "5/6  Scheduling: backup nightly at 03:30, heartbeat every 5 minutes"
cat > /etc/systemd/system/lab-backup.service <<'EOF'
[Unit]
Description=free-ai-lab nightly backup (restic -> Oracle Object Storage)
Wants=network-online.target
After=network-online.target docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/lab-backup
Nice=10
IOSchedulingClass=idle
EOF
cat > /etc/systemd/system/lab-backup.timer <<'EOF'
[Unit]
Description=Run free-ai-lab backup every night
[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=10m
Persistent=true
[Install]
WantedBy=timers.target
EOF
cat > /etc/systemd/system/lab-heartbeat.service <<'EOF'
[Unit]
Description=free-ai-lab heartbeat: keep the private model loaded + ping healthchecks.io
[Service]
Type=oneshot
EnvironmentFile=/etc/free-ai-lab/backup.env
# 1) make sure the private model is loaded (no-op if it already is; keeps it ready after a reboot)
ExecStart=-/usr/bin/curl -s -m 120 http://127.0.0.1:11434/api/generate -d '{"model":"llama3.2:3b","keep_alive":-1}' -o /dev/null
# 2) tell healthchecks.io we're alive
ExecStart=/bin/sh -c '[ -z "$HC_HEARTBEAT_URL" ] || curl -fsS -m 10 --retry 3 "$HC_HEARTBEAT_URL" >/dev/null'
EOF
cat > /etc/systemd/system/lab-heartbeat.timer <<'EOF'
[Unit]
Description=free-ai-lab heartbeat every 5 minutes
[Timer]
OnBootSec=2m
OnUnitActiveSec=5m
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now lab-backup.timer lab-heartbeat.timer >/dev/null
echo "Timers active:"; systemctl list-timers 'lab-*' --no-legend | sed 's/^/  /'

# ---------- 6. first backup + restore test ----------
step "6/6  First backup now (Open WebUI pauses for a few seconds), then a restore test"
/usr/local/bin/lab-backup
echo
/usr/local/bin/lab-restore-test

step "Done!"
echo "  sudo lab-status        health of the whole lab"
echo "  sudo lab-backup        back up right now"
echo "  sudo lab-restore-test  prove the latest backup restores"
[ -z "$(conf_get HC_HEARTBEAT_URL)" ] && warn "No healthchecks.io URLs set: nobody will email you if the server or a backup dies. See Lesson 08, Part E."
true
