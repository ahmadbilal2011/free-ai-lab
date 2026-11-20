#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 08: nightly .zip backups in /data/backups on the server
#
# Run ON THE VM:
#   sudo bash 08-install-backup.sh
#
# Installs:
#   lab-backup          back up now -> /data/backups/lab-YYYYMMDD-HHMM.zip (keeps the newest 14)
#   lab-restore-test    check the newest zip opens and holds the key files (changes nothing)
#   lab-restore <zip>   put a backup back (stops the apps, restores, starts them again)
#   lab-status          one-screen health check (containers, memory, disk, last backup)
#   a timer that runs lab-backup every night at 03:30
#
# What's in each zip: ~/lab (compose files, .env keys, n8n and Bifrost data) plus the Apache
# sites and fail2ban rules for n8n and Bifrost. Old moved-aside folders are skipped.
# n8n and Bifrost are stopped for a few seconds so their SQLite databases are copied consistently.
#
# Limit: the zips live on the SAME disk. They protect against mistakes, not against losing the VM.
# Copy one to your laptop now and then (the lesson shows the one-line command).
# =============================================================================
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/data/backups}"
KEEP="${KEEP:-14}"
LAB_USER="${SUDO_USER:-ubuntu}"
LAB_DIR="$(getent passwd "$LAB_USER" | cut -d: -f6)/lab"
CONF=/etc/free-ai-lab/backup.env

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo:  sudo bash $0"
[ -d "$LAB_DIR/jarvis" ] || die "No $LAB_DIR/jarvis found. Do Lessons 05-06 first."

step "1/5  Tools"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
apt-get install -y -q zip unzip >/dev/null
echo "zip and unzip installed."

step "2/5  Backup folder $BACKUP_DIR (only root can read it: the zips contain your keys)"
install -d -m 700 -o root -g root "$BACKUP_DIR"
install -d -m 700 /etc/free-ai-lab
cat > "$CONF" <<EOF
LAB_DIR="$LAB_DIR"
BACKUP_DIR="$BACKUP_DIR"
KEEP="$KEEP"
STOP_APPS="n8n bifrost"
EXTRA_FILES="/etc/apache2/sites-available/n8n-public.conf /etc/apache2/sites-available/ai-gateway.conf /etc/fail2ban/jail.d/n8n-login.conf /etc/fail2ban/filter.d/n8n-login.conf /etc/fail2ban/jail.d/bifrost-login.conf /etc/fail2ban/filter.d/bifrost-login.conf"
EOF
chmod 600 "$CONF"
echo "Settings in $CONF: keep the newest $KEEP zips."

step "3/5  Commands"
cat > /usr/local/bin/lab-backup <<'EOF'
#!/usr/bin/env bash
# Back up ~/lab + n8n/Bifrost server config into one zip. Run as root (the timer does).
set -euo pipefail
. /etc/free-ai-lab/backup.env
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
STAMP=$(date +%Y%m%d-%H%M); OUT="$BACKUP_DIR/lab-$STAMP.zip"; TMP="$OUT.part"
FREE_MB=$(df -Pm "$BACKUP_DIR" | awk 'NR==2{print $4}')
[ "$FREE_MB" -gt 1024 ] || { echo "Less than 1 GB free on $BACKUP_DIR, backup skipped"; exit 1; }
STOPPED=()
start_again() { for c in "${STOPPED[@]}"; do docker start "$c" >/dev/null 2>&1 || echo "WARNING: could not start $c"; done; }
trap start_again EXIT                                      # apps always come back, even if the zip fails
for c in $STOP_APPS; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then docker stop -t 20 "$c" >/dev/null && STOPPED+=("$c"); fi
done
LIST=("$LAB_DIR")
for f in $EXTRA_FILES; do [ -e "$f" ] && LIST+=("$f"); done
rm -f "$TMP"
zip -q -r -y "$TMP" "${LIST[@]}" \
  -x "*/n8n.old-*" "*.retired-*" "*/.env.old-*" "*.before-restore-*" "*/node_modules/*" "*.log"
start_again; STOPPED=(); trap - EXIT                       # restart right after zipping
mv "$TMP" "$OUT"; chmod 600 "$OUT"
unzip -tq "$OUT" >/dev/null || { echo "Zip check FAILED: $OUT"; exit 1; }
ls -1t "$BACKUP_DIR"/lab-*.zip | tail -n +$((KEEP + 1)) | xargs -r rm -f   # keep the newest $KEEP
echo "Backup OK: $OUT ($(du -h "$OUT" | cut -f1)), $(ls "$BACKUP_DIR"/lab-*.zip | wc -l) kept"
EOF

cat > /usr/local/bin/lab-restore-test <<'EOF'
#!/usr/bin/env bash
# Unzip the newest backup into a temporary folder and check the key files. Changes nothing live.
set -euo pipefail
. /etc/free-ai-lab/backup.env
LATEST=$(ls -1t "$BACKUP_DIR"/lab-*.zip 2>/dev/null | head -1)
[ -n "$LATEST" ] || { echo "No backups yet. Run: sudo lab-backup"; exit 1; }
DEST=$(mktemp -d /tmp/lab-restore-test.XXXX)
echo "Testing $LATEST ..."
unzip -q "$LATEST" -d "$DEST"
FAIL=0
check() { if [ -e "$DEST$1" ]; then echo "  OK      $1"; else echo "  MISSING $1"; FAIL=1; fi; }
for f in "$LAB_DIR"/*/compose.yaml "$LAB_DIR"/*/.env "$LAB_DIR"/jarvis/n8n/database.sqlite $EXTRA_FILES; do
  case "$f" in *.old-*|*.retired-*|*.before-restore-*) continue ;; esac   # left out of backups on purpose
  [ -e "$f" ] && check "$f"
done
[ -d "$LAB_DIR/gateway/data" ] && check "$LAB_DIR/gateway/data"
echo "  Unzipped size: $(du -sh "$DEST" | cut -f1)"
rm -rf "$DEST"
[ "$FAIL" -eq 0 ] && echo "RESTORE TEST PASSED" || { echo "RESTORE TEST FAILED"; exit 1; }
EOF

cat > /usr/local/bin/lab-restore <<'EOF'
#!/usr/bin/env bash
# Put a backup back:  sudo lab-restore /data/backups/lab-YYYYMMDD-HHMM.zip
# Takes a safety backup of the current state first, then replaces ~/lab and the n8n/Bifrost config.
set -euo pipefail
. /etc/free-ai-lab/backup.env
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
ZIP="${1:-}"; [ -f "$ZIP" ] || { echo "Usage: sudo lab-restore <zip>   (see: sudo ls -lt $BACKUP_DIR)"; exit 1; }
unzip -tq "$ZIP" >/dev/null || { echo "That zip is damaged."; exit 1; }
read -r -p "Replace the current n8n + Bifrost data with $(basename "$ZIP")? Type RESTORE: " a
[ "$a" = RESTORE ] || { echo "Cancelled."; exit 1; }
echo "Safety backup of the current state first..."; lab-backup
for d in "$LAB_DIR"/jarvis "$LAB_DIR"/gateway; do [ -f "$d/compose.yaml" ] && (cd "$d" && docker compose down >/dev/null 2>&1 || true); done
SAFE="$LAB_DIR.before-restore-$(date +%Y%m%d-%H%M)"; mv "$LAB_DIR" "$SAFE"
unzip -q -o -X "$ZIP" -d /                                 # -X restores file owners (n8n and Bifrost run as uid 1000)
OWNER=$(stat -c %U "$SAFE"); chown "$OWNER:$OWNER" "$LAB_DIR"
for d in "$LAB_DIR"/gateway "$LAB_DIR"/jarvis "$LAB_DIR"/autoheal; do [ -f "$d/compose.yaml" ] && (cd "$d" && docker compose up -d >/dev/null); done
apache2ctl configtest >/dev/null 2>&1 && systemctl reload apache2
systemctl restart fail2ban 2>/dev/null || true
echo "Restored. The previous state is kept in $SAFE (delete it when all is fine)."
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
echo "  Memory used : ${MEM}%  $([ "$MEM" -lt 20 ] && printf "$Y(below 20%%: see Lesson 08, Part E)$N")"
echo "  Disk used   : ${DISK}%  $([ "$DISK" -gt 85 ] && printf "$Rd(getting full)$N")"
echo "  Load (1m)   : $(cut -d' ' -f1 /proc/loadavg) on $(nproc) CPUs"
echo "  Uptime      : $(uptime -p)"
if [ "$(id -u)" -eq 0 ] && [ -f /etc/free-ai-lab/backup.env ]; then
  . /etc/free-ai-lab/backup.env
  LAST=$(ls -1t "$BACKUP_DIR"/lab-*.zip 2>/dev/null | head -1)
  echo; echo "Backups ($BACKUP_DIR):"
  if [ -n "$LAST" ]; then
    AGE=$(( ($(date +%s) - $(stat -c %Y "$LAST")) / 3600 ))
    echo "  Last backup : $(basename "$LAST") ($(du -h "$LAST" | cut -f1)), ${AGE}h ago $([ "$AGE" -gt 30 ] && printf "$Rd(older than a day!)$N")"
  else echo -e "  Last backup : ${Rd}none yet${N}"; fi
  echo "  Kept        : $(ls "$BACKUP_DIR"/lab-*.zip 2>/dev/null | wc -l) zips, $(du -sh "$BACKUP_DIR" | cut -f1) in total"
  echo "  Next run    : $(systemctl list-timers lab-backup.timer --no-legend 2>/dev/null | awk '{print $1, $2, $3}')"
else
  echo; echo "(run 'sudo lab-status' to include backups)"
fi
EOF
chmod 755 /usr/local/bin/lab-backup /usr/local/bin/lab-restore-test /usr/local/bin/lab-restore /usr/local/bin/lab-status
echo "lab-backup, lab-restore-test, lab-restore, lab-status installed."

step "4/5  Nightly timer (03:30)"
cat > /etc/systemd/system/lab-backup.service <<'EOF'
[Unit]
Description=free-ai-lab nightly zip backup
After=docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/lab-backup
EOF
cat > /etc/systemd/system/lab-backup.timer <<'EOF'
[Unit]
Description=free-ai-lab nightly zip backup at 03:30
[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
RandomizedDelaySec=5m
[Install]
WantedBy=timers.target
EOF
# remove leftovers from the older cloud-backup version, if any
systemctl disable --now lab-heartbeat.timer >/dev/null 2>&1 || true
rm -f /etc/systemd/system/lab-heartbeat.* /usr/local/bin/lab-heartbeat
systemctl daemon-reload
systemctl enable --now lab-backup.timer >/dev/null
echo "Next run: $(systemctl list-timers lab-backup.timer --no-legend | awk '{print $1, $2, $3}')"

step "5/5  First backup and restore test"
/usr/local/bin/lab-backup
/usr/local/bin/lab-restore-test

step "Done!"
echo "  Backups: $BACKUP_DIR (newest $KEEP kept). Check any time: sudo lab-status"
echo "  Copy one to your laptop now and then (Lesson 08, Part D): the zips are on the same disk as the data."
