#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — wipe every app from the server, keep the server itself
#
#   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/wipe-apps.sh -o wipe-apps.sh && bash wipe-apps.sh
#
# Use it once, when restarting the course on a server that already has the
# apps from the first version of this course (Open WebUI, Ollama, LiteLLM,
# n8n, voice, autoheal, backups...).
#
# KEEPS:   Ubuntu, your SSH login and hardening, fail2ban, swap, automatic
#          security updates, Tailscale (logged in), the Docker engine.
# REMOVES: every Docker container, volume, image and network; ~/lab;
#          backup/heartbeat timers and scripts; /etc/free-ai-lab (keys);
#          restic; everything published with `tailscale serve` / `funnel`.
#
# It first SHOWS what it will remove, then asks you to type WIPE.
# Nothing is deleted before that. This cannot be undone.
# =============================================================================
set -uo pipefail

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo; echo -e "${c_ok}== $*${c_off}"; }
warn() { echo -e "${c_warn}[!] $*${c_off}"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run as your normal user (ubuntu), not root. The script uses sudo where needed."
sudo -n true 2>/dev/null || die "This needs passwordless sudo (the default ubuntu user on Oracle has it). Log in as ubuntu and try again."

LAB="$HOME/lab"
UNITS="lab-backup.timer lab-backup.service lab-heartbeat.timer lab-heartbeat.service"
BINS="/usr/local/bin/lab-backup /usr/local/bin/lab-restore-test /usr/local/bin/lab-status"
have_docker=0; command -v docker >/dev/null 2>&1 && have_docker=1

# ---------------------------------------------------------------------------
step "What will be removed"
if [ $have_docker -eq 1 ]; then
  echo "Containers:"; sudo docker ps -a --format '  - {{.Names}}  ({{.Image}}, {{.Status}})' || true
  echo "Volumes (app data: chats, n8n workflows, models...):"; sudo docker volume ls -q | sed 's/^/  - /' || true
  echo "Images: $(sudo docker images -q | sort -u | wc -l), disk used:"; sudo docker system df 2>/dev/null | sed 's/^/  /' || true
else
  echo "Docker is not installed (nothing to remove there)."
fi
[ -d "$LAB" ] && { echo "Folder $LAB:"; ls -1 "$LAB" | sed 's/^/  - /'; }
echo "Backup / heartbeat timers:"; systemctl list-unit-files 'lab-*' --no-legend 2>/dev/null | sed 's/^/  - /' || true
for b in $BINS; do [ -e "$b" ] && echo "  - $b"; done
[ -d /etc/free-ai-lab ] && echo "  - /etc/free-ai-lab (backup password + bucket keys)"
command -v restic >/dev/null 2>&1 && echo "  - restic (backup tool)"
if command -v tailscale >/dev/null 2>&1; then
  echo "Published on Tailscale (will be un-published; Tailscale stays logged in):"
  tailscale serve status 2>/dev/null | sed 's/^/  /' || true
fi

echo
warn "This deletes ALL app data on this server: Open WebUI chats, n8n workflows (incl. the Telegram bot workflow),"
warn "gateway keys in .env files, voice settings, local models. Your accounts (Telegram bot, API keys at the providers)"
warn "are NOT touched: you can reuse the same keys later."
read -r -p "Type WIPE (capital letters) to continue, anything else to cancel: " ans
[ "$ans" = "WIPE" ] || { echo "Cancelled. Nothing was changed."; exit 0; }

# ---------------------------------------------------------------------------
step "1/5  Stopping backups and the heartbeat"
for u in $UNITS; do sudo systemctl disable --now "$u" >/dev/null 2>&1 || true; done
for u in $UNITS; do sudo rm -f "/etc/systemd/system/$u"; done
sudo systemctl daemon-reload
sudo rm -f $BINS
sudo rm -rf /etc/free-ai-lab
sudo apt-get remove -y -q restic >/dev/null 2>&1 || true
echo "Done."

# ---------------------------------------------------------------------------
step "2/5  Un-publishing everything from Tailscale (serve + funnel)"
if command -v tailscale >/dev/null 2>&1; then
  sudo tailscale funnel reset >/dev/null 2>&1 || true
  sudo tailscale serve reset  >/dev/null 2>&1 || true
  echo "Now published: $(tailscale serve status 2>&1 | head -1)"
fi

# ---------------------------------------------------------------------------
step "3/5  Removing all Docker apps, data, images and networks"
if [ $have_docker -eq 1 ]; then
  ids=$(sudo docker ps -aq); [ -n "$ids" ] && sudo docker rm -f $ids >/dev/null
  vols=$(sudo docker volume ls -q); [ -n "$vols" ] && sudo docker volume rm -f $vols >/dev/null
  sudo docker network prune -f >/dev/null
  sudo docker image prune -af >/dev/null
  sudo docker builder prune -af >/dev/null 2>&1 || true
  echo "Containers left: $(sudo docker ps -aq | wc -l), volumes left: $(sudo docker volume ls -q | wc -l)"
fi

# ---------------------------------------------------------------------------
step "4/5  Removing the lab folder ($LAB)"
sudo rm -rf "$LAB"
rm -f "$HOME"/0*-*.sh "$HOME"/1*-*.sh "$HOME"/cleanup-lab.sh "$HOME"/07-pick-models.py 2>/dev/null || true
echo "Done."

# ---------------------------------------------------------------------------
step "5/5  What's left"
echo "  Ubuntu:          $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "  fail2ban:        $(systemctl is-active fail2ban 2>/dev/null)"
echo "  Tailscale:       $(tailscale status >/dev/null 2>&1 && echo connected || echo 'not connected')"
[ $have_docker -eq 1 ] && echo "  Docker engine:   $(sudo docker version --format '{{.Server.Version}}' 2>/dev/null) (empty)"
echo "  Disk free:       $(df -h / | awk 'NR==2{print $4}')"
echo "  Memory used:     $(free -h | awk '/Mem:/{print $3" of "$2}')"

echo
echo -e "${c_ok}Server wiped. Apps and data are gone; the server, SSH and Tailscale are ready for the new course.${c_off}"
echo "Outside this server, also do these (they're not on this machine):"
echo "  1. healthchecks.io: pause or delete the old checks, or they'll email you that the server is down."
echo "  2. Oracle Console > Storage > Buckets: delete the old backup bucket (it holds the old encrypted backups)."
echo "  3. Tailscale admin page: nothing to do, this server stays in your tailnet."
