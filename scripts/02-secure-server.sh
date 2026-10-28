#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 02: secure the Ubuntu VM
#
# Run ON THE VM (logged in as ubuntu):
#   sudo bash 02-secure-server.sh
#
# What it does:
#   1. Installs all updates
#   2. Turns on automatic security updates
#   3. Hardens SSH: keys only, no passwords, no root login, max 3 tries
#   4. Installs fail2ban: blocks IPs that keep guessing SSH logins
#   5. Adds a 4 GB swap file (safety net for AI models in Lesson 04)
#   6. Sets the timezone to Asia/Riyadh
#   7. Checks the firewall (keeps Oracle's built-in iptables rules)
#
# Safe to re-run. It checks you have a working SSH key BEFORE disabling
# passwords, and tests the SSH config before applying it.
# =============================================================================
set -euo pipefail

TIMEZONE="${TIMEZONE:-Asia/Riyadh}"
SWAP_GB="${SWAP_GB:-4}"
LOGIN_USER="${SUDO_USER:-ubuntu}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo:  sudo bash $0"
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "This script is for Ubuntu (found: ${ID:-unknown})."

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a          # don't stop to ask which services to restart
APT_OPTS=(-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# ---------- 1. updates ----------
step "1/7  Installing all updates (this can take a few minutes)"
apt-get update -q
apt-get "${APT_OPTS[@]}" full-upgrade
apt-get "${APT_OPTS[@]}" install unattended-upgrades fail2ban python3-systemd
apt-get -y -q autoremove

# ---------- 2. automatic security updates ----------
step "2/7  Turning on automatic security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades >/dev/null
echo "Security updates will now install automatically every day."

# ---------- 3. SSH hardening ----------
step "3/7  Hardening SSH"
AUTH_KEYS="/home/${LOGIN_USER}/.ssh/authorized_keys"
if [ ! -s "$AUTH_KEYS" ] || ! grep -Eq '^(ssh-|ecdsa-)' "$AUTH_KEYS"; then
  die "No SSH key found in $AUTH_KEYS. Refusing to disable passwords (you could be locked out)."
fi
echo "Found SSH key(s) for '${LOGIN_USER}' — safe to disable password login."

SSHD_DROPIN=/etc/ssh/sshd_config.d/99-free-ai-lab.conf
cat > "$SSHD_DROPIN" <<'EOF'
# free-ai-lab hardening (Lesson 02)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF
if sshd -t; then
  systemctl reload ssh 2>/dev/null || systemctl restart ssh
  echo "SSH now accepts keys only. Root login is off."
else
  rm -f "$SSHD_DROPIN"
  die "SSH config test failed, so the change was undone. Your SSH is unchanged."
fi

# ---------- 4. fail2ban ----------
step "4/7  Setting up fail2ban (blocks repeated failed SSH logins)"
cat > /etc/fail2ban/jail.local <<'EOF'
# free-ai-lab (Lesson 02)
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
backend = systemd
EOF
systemctl enable fail2ban >/dev/null
systemctl restart fail2ban
sleep 2
if fail2ban-client status sshd >/dev/null 2>&1; then
  echo "fail2ban is watching SSH: 5 failures in 10 min = banned for 1 hour."
else
  warn "fail2ban did not start correctly. Check later with: sudo systemctl status fail2ban"
fi

# ---------- 5. swap ----------
step "5/7  Adding a ${SWAP_GB} GB swap file"
if swapon --show | grep -q .; then
  echo "Swap already exists:"; swapon --show
else
  fallocate -l "${SWAP_GB}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "Swap of ${SWAP_GB} GB created and enabled at boot."
fi
echo 'vm.swappiness=10' > /etc/sysctl.d/99-free-ai-lab.conf
sysctl -q -p /etc/sysctl.d/99-free-ai-lab.conf
echo "Swappiness set to 10 (use RAM first, swap only when needed)."

# ---------- 6. timezone ----------
step "6/7  Setting timezone to ${TIMEZONE}"
timedatectl set-timezone "$TIMEZONE"
echo "Server time is now: $(date)"

# ---------- 7. firewall check ----------
step "7/7  Checking the firewall"
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  warn "UFW is active. Oracle recommends NOT using UFW on its Ubuntu images. See Lesson 02."
else
  echo "UFW is off (correct for Oracle images)."
fi
echo "Oracle's built-in iptables rules (incoming traffic):"
iptables -L INPUT -n --line-numbers | sed 's/^/  /'
echo "Expected: ACCEPT for port 22 (SSH), then a final REJECT for everything else."

# ---------- summary ----------
step "Done! Summary"
echo "  Updates:            installed, automatic security updates ON"
echo "  SSH:                keys only, no root, max 3 tries"
echo "  fail2ban:           $(systemctl is-active fail2ban)"
echo "  Swap:               $(swapon --show --noheadings --bytes | awk '{s+=$3} END {printf "%.0f GB", s/1024/1024/1024}')"
echo "  Timezone:           $(timedatectl show -p Timezone --value)"
echo
if [ -f /var/run/reboot-required ]; then
  warn "A reboot is needed to finish updates. First test SSH in a NEW window (see lesson), then run:  sudo reboot"
fi
echo -e "${c_warn}IMPORTANT:${c_off} keep this window open and test SSH in a NEW window before closing it."
