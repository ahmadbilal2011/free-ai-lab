#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 03: install Docker Engine + Docker Compose
#
# Run ON THE VM (logged in as ubuntu):
#   sudo bash 03-install-docker.sh
#
# What it does:
#   1. Removes old/unofficial Docker packages (if any)
#   2. Adds Docker's official package repository (works on Arm / aarch64)
#   3. Installs Docker Engine, CLI, containerd, Buildx and the Compose plugin
#   4. Limits container log size so logs can't fill the disk
#   5. Lets the 'ubuntu' user run docker without sudo
#   6. Tests it with the hello-world container and an internet check
#
# Safe to re-run.
# =============================================================================
set -euo pipefail

LOGIN_USER="${SUDO_USER:-ubuntu}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo:  sudo bash $0"
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "This script is for Ubuntu (found: ${ID:-unknown})."
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ---------- 1. remove conflicting packages ----------
step "1/6  Removing old or unofficial Docker packages (if any)"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    apt-get -y -q remove "$pkg"
    echo "Removed $pkg"
  fi
done
echo "Clean."

# ---------- 2. official repository ----------
step "2/6  Adding Docker's official repository for Ubuntu ${CODENAME} ($(dpkg --print-architecture))"
apt-get update -q
apt-get -y -q install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update -q

# ---------- 3. install ----------
step "3/6  Installing Docker Engine and Compose"
apt-get -y -q install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ---------- 4. log limits ----------
step "4/6  Limiting container log size (protects your disk)"
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
  echo "Each container keeps at most 3 x 10 MB of logs."
else
  warn "/etc/docker/daemon.json already exists, leaving it unchanged."
fi
systemctl enable --now docker containerd >/dev/null
systemctl restart docker

# ---------- 5. docker group ----------
step "5/6  Allowing '${LOGIN_USER}' to run docker without sudo"
usermod -aG docker "$LOGIN_USER"
echo "Done. This takes effect after you log out and back in."

# ---------- 6. test ----------
step "6/6  Testing Docker"
if docker run --rm hello-world 2>&1 | grep -q "Hello from Docker!"; then
  echo "hello-world container ran successfully."
else
  die "hello-world test failed. Check: sudo systemctl status docker"
fi
if docker run --rm busybox wget -q -T 10 -O /dev/null https://download.docker.com 2>/dev/null; then
  echo "Containers can reach the internet."
else
  warn "Containers could not reach the internet. Tell your instructor / open an issue with this output."
fi

step "Done! Summary"
echo "  Docker Engine:   $(docker version --format '{{.Server.Version}}')"
echo "  Docker Compose:  $(docker compose version --short)"
echo "  Architecture:    $(docker info --format '{{.Architecture}}')"
echo "  Log limit:       10 MB x 3 files per container"
echo
echo -e "${c_warn}NEXT:${c_off} type 'exit', log in again, then run:  docker ps"
echo "(Logging in again is what gives you the new 'docker' group permission.)"
