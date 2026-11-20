#!/usr/bin/env bash
# free-ai-lab - remove Jarvis Live (old Lessons 09-10) from the server. One-time cleanup.
#   bash remove-jarvis.sh
# Removes: the jarvis-live container and image, its web page live-<ip>.sslip.io (Apache site + certificate),
#          its fail2ban jail, its folder ~/lab/live, and unpublishes the "Jarvis agents" workflow in n8n.
# Keeps:   the SAR→PKR site, n8n (all your workflows), Bifrost, backups, the Telegram bot.
# Safety:  ~/lab/live is first zipped to /data/backups/jarvis-live-retired-<date>.zip (root only), then deleted.
set -uo pipefail
c_ok='\033[1;32m'; c_bad='\033[1;31m'; c_step='\033[1;36m'; c_off='\033[0m'
step() { echo -e "\n${c_step}$*${c_off}"; }
ok()   { echo -e "${c_ok}✓${c_off} $*"; }
die()  { echo -e "${c_bad}✗ $*${c_off}"; exit 1; }
DIR="$HOME/lab/live"
STAMP=$(date +%Y%m%d-%H%M)

step "1/6  Save a copy of Jarvis Live's folder (just in case)"
if [ -d "$DIR" ]; then
  sudo mkdir -p /data/backups && sudo chmod 700 /data/backups
  (cd "$HOME/lab" && sudo zip -qr -X "/data/backups/jarvis-live-retired-$STAMP.zip" live) || die "Couldn't zip $DIR. Nothing was removed."
  sudo chmod 600 "/data/backups/jarvis-live-retired-$STAMP.zip"
  ok "saved /data/backups/jarvis-live-retired-$STAMP.zip"
else ok "no $DIR (already gone)"; fi

step "2/6  Stop and remove the jarvis-live container"
img=$(docker inspect -f '{{.Config.Image}}' jarvis-live 2>/dev/null || true)
[ -f "$DIR/compose.yaml" ] && (cd "$DIR" && docker compose down --remove-orphans >/dev/null 2>&1) || true
docker rm -f jarvis-live >/dev/null 2>&1 || true
[ -n "$img" ] && docker image rm "$img" >/dev/null 2>&1 || true
docker ps -a --format '{{.Names}}' | grep -qx jarvis-live && die "jarvis-live is still there: docker rm -f jarvis-live"
ok "container removed${img:+ (image $img removed)}"

step "3/6  Take its web page offline (Apache site + certificate)"
sudo a2dissite -q jarvis-live >/dev/null 2>&1 || true
sudo rm -f /etc/apache2/sites-available/jarvis-live.conf /etc/apache2/sites-enabled/jarvis-live.conf
if sudo apache2ctl configtest >/dev/null 2>&1; then sudo systemctl reload apache2; ok "Apache reloaded; the SAR site, n8n and Bifrost pages are unchanged"
else sudo apache2ctl configtest; die "Apache config test failed (shown above). Nothing else was changed in Apache; send this output."; fi
for c in $(sudo ls /etc/letsencrypt/live 2>/dev/null | grep '^live-' || true); do
  sudo certbot delete --cert-name "$c" --non-interactive >/dev/null 2>&1 && ok "certificate $c deleted"
done

step "4/6  Remove its fail2ban jail"
sudo rm -f /etc/fail2ban/jail.d/live-login.conf /etc/fail2ban/filter.d/live-login.conf
sudo systemctl restart fail2ban 2>/dev/null && ok "fail2ban restarted (n8n and Bifrost jails stay)" || ok "fail2ban not running"

step "5/6  Remove its folder and stop backing up its files"
sudo rm -rf "$DIR"
if [ -f /etc/free-ai-lab/backup.env ]; then
  sudo sed -i -E 's# ?/etc/apache2/sites-available/jarvis-live\.conf##; s# ?/etc/fail2ban/(jail|filter)\.d/live-login\.conf##g' /etc/free-ai-lab/backup.env
  ok "backup list updated (/etc/free-ai-lab/backup.env)"
fi
rm -f "$HOME"/09-install-live.sh "$HOME"/10-check-agents.sh "$HOME"/10-install-agents.sh
ok "$DIR removed"

step "6/6  Unpublish the 'Jarvis agents' workflow in n8n"
if docker ps --format '{{.Names}}' | grep -qx n8n; then
  ids=$(docker exec -u node n8n n8n list:workflow 2>/dev/null | sed -nE 's/^(.*[^A-Za-z0-9])?([A-Za-z0-9]{8,})\|Jarvis agents[[:space:]]*$/\2/p')
  if [ -n "$ids" ]; then
    for id in $ids; do
      docker exec -u node n8n n8n unpublish:workflow --id="$id" >/dev/null 2>&1 \
        || docker exec -u node n8n n8n update:workflow --id="$id" --active=false >/dev/null 2>&1 || true
    done
    docker restart n8n >/dev/null
    for i in $(seq 1 40); do
      code=$(docker exec n8n node -e "fetch('http://localhost:5678/healthz').then(r=>console.log(r.status)).catch(()=>console.log(0))" 2>/dev/null || echo 0)
      [ "$code" = 200 ] && break; sleep 3
    done
    [ "$code" = 200 ] && ok "unpublished; n8n restarted and healthy" || die "n8n didn't come back: docker logs --tail 40 n8n"
  else ok "no 'Jarvis agents' workflow found"; fi
else ok "n8n isn't running; skipped"; fi

echo
echo "Still running:"; docker ps --format '  {{.Names}}  ({{.Status}})'
echo -e "\n${c_ok}Jarvis Live is removed.${c_off} Two clicks left in n8n (they can't be done from the command line):"
echo "  • Overview → 'Jarvis agents' → ⋯ → Archive (then delete it from Archived, if you like)"
echo "  • Credentials → 'Jarvis Live secret' → Delete"
