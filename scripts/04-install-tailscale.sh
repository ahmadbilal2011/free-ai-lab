#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 04: put the server on your private Tailscale network
#
# Run ON THE VM:
#   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/04-install-tailscale.sh -o 04-install-tailscale.sh && sudo bash 04-install-tailscale.sh
#
# What it does:
#   1. Installs Tailscale (official package, Arm supported)
#   2. Connects this server to YOUR Tailscale account (you approve in a browser)
#   3. Checks that nothing is published (and that Funnel, the public mode, is off)
#   4. Prints the server's private name and IP for your laptop and phone
#
# It does NOT publish anything and does NOT use Funnel (public).
# Safe to re-run.
# =============================================================================
set -euo pipefail

TS_HOSTNAME="${TS_HOSTNAME:-free-ai-lab}"
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

# ---------- 3. nothing published ----------
step "3/4  Checking that nothing is published"
# Later lessons publish single apps privately with 'tailscale serve'. Right now there should be none,
# and NEVER 'funnel' (that would put an app on the public internet).
if tailscale funnel status 2>/dev/null | grep -qi "funnel on"; then
  warn "Something is PUBLIC through Funnel. Turning it off."; tailscale funnel reset || true
fi
echo "Published apps: $(tailscale serve status 2>&1 | head -1)"

# ---------- 4. summary ----------
step "Done! Summary"
echo "  Private name:  ${TS_NAME}"
echo "  Private IP:    $(tailscale ip -4)"
echo "  Public internet: still only SSH (22) is open"
echo
echo -e "${c_warn}Now do these 3 things (see Lesson 04):${c_off}"
echo "  1) Install Tailscale on your laptop and phone, and sign in with the SAME account."
echo "  2) Test from the laptop:   ssh ubuntu@${TS_HOSTNAME}"
echo "  3) In the Tailscale admin console, turn OFF key expiry for '${TS_HOSTNAME}'"
echo "     (otherwise the server disconnects itself after about 6 months),"
echo "     and turn on HTTPS certificates (DNS page) for later lessons."
