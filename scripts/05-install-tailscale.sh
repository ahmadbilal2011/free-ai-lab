#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 05: private access from anywhere with Tailscale
#
# Run ON THE VM:
#   sudo bash 05-install-tailscale.sh
#
# What it does:
#   1. Installs Tailscale (official package, Arm supported)
#   2. Connects this server to YOUR Tailscale account (you approve in a browser)
#   3. Publishes Open WebUI with HTTPS *inside your tailnet only*
#      (tailscale serve — NOT funnel, so nothing is on the public internet)
#   4. Prints the private https://... address for your laptop and phone
#
# Safe to re-run.
# =============================================================================
set -euo pipefail

TS_HOSTNAME="${TS_HOSTNAME:-free-ai-lab}"
APP_PORT="${APP_PORT:-3000}"      # Open WebUI on 127.0.0.1:3000 (Lesson 04)
LOGIN_USER="${SUDO_USER:-ubuntu}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo:  sudo bash $0"

ts_state() { tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState",""))' 2>/dev/null || echo ""; }
ts_dns()   { tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || echo ""; }

# ---------- 1. install ----------
step "1/4  Installing Tailscale"
if command -v tailscale >/dev/null; then
  echo "Already installed: $(tailscale version | head -1)"
else
  curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled >/dev/null

# ---------- 2. log in ----------
step "2/4  Connecting this server to your Tailscale account"
if [ "$(ts_state)" = "Running" ]; then
  echo "Already connected as $(ts_dns)"
else
  echo -e "${c_warn}A login link will appear below.${c_off}"
  echo "Open it in your laptop's browser, sign in (Google / Microsoft / GitHub / Apple),"
  echo "and approve the machine. This window waits until you're done."
  echo
  tailscale up --hostname="$TS_HOSTNAME" --operator="$LOGIN_USER"
fi
[ "$(ts_state)" = "Running" ] || die "Tailscale isn't connected. Run the script again."
TS_NAME=$(ts_dns)
echo "Connected. Private name: $TS_NAME   Private IP: $(tailscale ip -4)"

# ---------- 3. serve Open WebUI over HTTPS (tailnet only) ----------
step "3/4  Publishing Open WebUI at https://${TS_NAME} (only your devices can reach it)"
if ! curl -fsS -o /dev/null "http://127.0.0.1:${APP_PORT}/health"; then
  warn "Open WebUI isn't answering on 127.0.0.1:${APP_PORT} yet. Continuing; it will work once it's up."
fi
echo "If a link appears saying HTTPS / Serve is not enabled, open it, click Enable, and come back."
tailscale serve --bg "$APP_PORT"
echo
tailscale serve status

# ---------- 4. check ----------
step "4/4  Checking"
sleep 3
if curl -fsS -o /dev/null --max-time 30 "https://${TS_NAME}/health"; then
  echo -e "${c_ok}HTTPS works:${c_off} https://${TS_NAME}"
else
  warn "Couldn't open https://${TS_NAME} from the server yet (the certificate can take a minute on first use)."
  warn "Try it from your laptop after installing Tailscale there (see the lesson)."
fi

step "Done! Summary"
echo "  This server on Tailscale:  ${TS_NAME}"
echo "  Open WebUI (private):      https://${TS_NAME}"
echo "  Public internet:           still only SSH (22) is open; port ${APP_PORT} is NOT public"
echo
echo -e "${c_warn}Do these 2 things now (see Lesson 05):${c_off}"
echo "  1) Install Tailscale on your laptop and phone, and sign in with the SAME account."
echo "  2) In the Tailscale admin console, turn OFF key expiry for '${TS_HOSTNAME}'"
echo "     (otherwise the server disconnects itself after about 6 months)."
