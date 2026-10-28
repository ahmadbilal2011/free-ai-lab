#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — create an Oracle Cloud Always Free Arm VM from Cloud Shell
#
# What it creates (all inside Always Free limits):
#   - VCN "free-ai-lab-vcn" (10.0.0.0/16) + internet gateway + public subnet
#     (Oracle's default security list allows only SSH port 22 + ICMP)
#   - VM "free-ai-lab": Ubuntu 24.04 aarch64, VM.Standard.A1.Flex,
#     2 OCPU / 12 GB RAM, 100 GB boot volume, public IPv4, user "ubuntu"
#   - An SSH key pair in Cloud Shell (~/.ssh/free-ai-lab), unless you bring your own
#
# Safe to re-run: it reuses existing network pieces and stops if the VM exists.
# It refuses to run if it would go above the Always Free limits.
#
# Usage (in Oracle Cloud Shell):
#   bash create-free-vm.sh                                   # easiest: key is created for you
#   SSH_PUBLIC_KEY="ssh-ed25519 AAAA..." bash create-free-vm.sh   # advanced: use your own key
# =============================================================================
set -uo pipefail

# ---------- settings (change only if you know why) ----------
NAME="${NAME:-free-ai-lab}"
OCPUS="${OCPUS:-2}"
MEMORY_GB="${MEMORY_GB:-12}"
BOOT_GB="${BOOT_GB:-100}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"     # retries when Oracle is out of capacity
RETRY_SECONDS="${RETRY_SECONDS:-60}"

# Always Free limits (2026)
FREE_A1_OCPUS=2
FREE_A1_MEMORY_GB=12
FREE_STORAGE_GB=200

SHAPE="VM.Standard.A1.Flex"
VCN_NAME="${NAME}-vcn"
IGW_NAME="${NAME}-igw"
SUBNET_NAME="${NAME}-public-subnet"

# ---------- helpers ----------
c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
warn() { echo -e "${c_warn}[!]${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
# run an oci query; print the result, or nothing if empty/null
q()    { oci "$@" --raw-output 2>/dev/null | grep -v '^null$' || true; }

show_connect_help() {
  local ip="$1"
  echo
  if [ -n "$KEY_PATH" ]; then
    echo "1) Connect right now from this Cloud Shell:"
    echo "     ssh -i ~/.ssh/${NAME} ubuntu@${ip}"
    echo
    echo "2) To connect from your Windows laptop, download the private key:"
    echo "     Cloud Shell menu (gear/settings icon, top right) -> Download"
    echo "     File path:  ${KEY_PATH}"
    echo "   Then follow Lesson 01, Part D (Windows) to move it and fix its permissions."
  else
    echo "Connect from Windows PowerShell with your own key:"
    echo "     ssh -i \$HOME\\.ssh\\oci_free_ai_lab ubuntu@${ip}"
  fi
  echo
  echo "Reminder: never commit the IP address or the private key to GitHub."
}

# ---------- 0. pre-flight checks ----------
step "Checking environment"
command -v oci >/dev/null || die "The 'oci' CLI was not found. Run this inside Oracle Cloud Shell."
[ -n "${OCI_TENANCY:-}" ] || die "OCI_TENANCY is not set. Run this inside Oracle Cloud Shell."
COMPARTMENT="$OCI_TENANCY"   # root compartment, simplest for beginners

KEY="${SSH_PUBLIC_KEY:-}"
KEY_PATH=""   # set only when this script manages the key
if [ -z "$KEY" ]; then
  KEY_PATH="$HOME/.ssh/${NAME}"
  if [ -f "$KEY_PATH" ] && [ -f "$KEY_PATH.pub" ]; then
    echo "Using existing Cloud Shell key: $KEY_PATH"
  else
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    rm -f "$KEY_PATH" "$KEY_PATH.pub"   # clear any half-made key from an earlier failed run
    # Oracle Cloud Shell runs in FIPS mode, which forbids ED25519, so we use RSA 4096
    ssh-keygen -q -t rsa -b 4096 -N "" -C "$NAME" -f "$KEY_PATH" </dev/null \
      || die "Could not create an SSH key."
    echo "Created SSH key pair (RSA 4096) in Cloud Shell: $KEY_PATH (private) and $KEY_PATH.pub (public)"
  fi
  KEY=$(cat "$KEY_PATH.pub")
fi
echo "$KEY" | grep -q "PRIVATE" && die "That looks like a PRIVATE key. Never paste it anywhere. Use the .pub file."
echo "$KEY" | grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[a-z0-9-]+) [A-Za-z0-9+/=]+' \
  || die "SSH_PUBLIC_KEY doesn't look like a public key. It must start with ssh-ed25519."

HOME_REGION=$(q iam region-subscription list --query 'data[?"is-home-region"] | [0]."region-name"')
CURRENT_REGION="${OCI_REGION:-unknown}"
echo "Home region:    ${HOME_REGION:-unknown}"
echo "Current region: $CURRENT_REGION"
if [ -n "$HOME_REGION" ] && [ "$HOME_REGION" != "$CURRENT_REGION" ]; then
  die "Always Free resources only exist in your HOME region ($HOME_REGION).
    Switch the Console region (top right) to it, reopen Cloud Shell, and run again."
fi

# ---------- 1. does the VM already exist? ----------
step "Looking for an existing VM named '$NAME'"
EXISTING=$(q compute instance list --compartment-id "$COMPARTMENT" --all \
  --display-name "$NAME" \
  --query 'data[?"lifecycle-state"!=`TERMINATED` && "lifecycle-state"!=`TERMINATING`] | [0].id')
if [ -n "$EXISTING" ]; then
  IP=$(q compute instance list-vnics --instance-id "$EXISTING" --query 'data[0]."public-ip"')
  echo "VM already exists: $EXISTING"
  echo "Public IP: ${IP:-<none>}"
  echo "Nothing to do."
  show_connect_help "${IP:-<SERVER_IP>}"
  exit 0
fi

# ---------- 2. stay inside Always Free limits ----------
step "Checking Always Free usage (root compartment)"
USED_OCPUS=$(q compute instance list --compartment-id "$COMPARTMENT" --all \
  --query "sum(data[?shape==\`$SHAPE\` && \"lifecycle-state\"!=\`TERMINATED\`].\"shape-config\".ocpus)")
USED_MEM=$(q compute instance list --compartment-id "$COMPARTMENT" --all \
  --query "sum(data[?shape==\`$SHAPE\` && \"lifecycle-state\"!=\`TERMINATED\`].\"shape-config\".\"memory-in-gbs\")")
USED_OCPUS=${USED_OCPUS%.*}; USED_OCPUS=${USED_OCPUS:-0}
USED_MEM=${USED_MEM%.*};     USED_MEM=${USED_MEM:-0}

mapfile -t ADS < <(oci iam availability-domain list --compartment-id "$COMPARTMENT" \
  --query 'data[].name' 2>/dev/null | tr -d '[]", ' | grep -v '^$')
[ "${#ADS[@]}" -gt 0 ] || die "Could not list availability domains. Is Cloud Shell signed in?"

USED_STORAGE=0
for AD in "${ADS[@]}"; do
  s=$(q bv boot-volume list --compartment-id "$COMPARTMENT" --availability-domain "$AD" --all \
      --query 'sum(data[?"lifecycle-state"!=`TERMINATED`]."size-in-gbs")')
  USED_STORAGE=$(( USED_STORAGE + ${s%.*} + 0 )) 2>/dev/null || true
done
s=$(q bv volume list --compartment-id "$COMPARTMENT" --all \
    --query 'sum(data[?"lifecycle-state"!=`TERMINATED`]."size-in-gbs")')
USED_STORAGE=$(( USED_STORAGE + ${s%.*} + 0 )) 2>/dev/null || true

echo "A1 in use:      ${USED_OCPUS} OCPU / ${USED_MEM} GB   (free limit ${FREE_A1_OCPUS} / ${FREE_A1_MEMORY_GB})"
echo "Storage in use: ${USED_STORAGE} GB                (free limit ${FREE_STORAGE_GB})"
echo "This VM adds:   ${OCPUS} OCPU / ${MEMORY_GB} GB RAM / ${BOOT_GB} GB disk"

(( USED_OCPUS + OCPUS > FREE_A1_OCPUS ))       && die "This would exceed the free A1 OCPU limit. Remove other A1 VMs first."
(( USED_MEM + MEMORY_GB > FREE_A1_MEMORY_GB )) && die "This would exceed the free A1 memory limit. Remove other A1 VMs first."
(( USED_STORAGE + BOOT_GB > FREE_STORAGE_GB )) && die "This would exceed the free 200 GB storage. Delete unused volumes, or set BOOT_GB lower (minimum 50)."
echo "OK — still inside Always Free."

# ---------- 3. network ----------
step "Network: VCN"
VCN_ID=$(q network vcn list --compartment-id "$COMPARTMENT" --all --display-name "$VCN_NAME" \
  --query 'data[?"lifecycle-state"==`AVAILABLE`] | [0].id')
if [ -z "$VCN_ID" ]; then
  VCN_ID=$(oci network vcn create --compartment-id "$COMPARTMENT" \
    --display-name "$VCN_NAME" --cidr-blocks '["10.0.0.0/16"]' --dns-label freeailab \
    --wait-for-state AVAILABLE --query 'data.id' --raw-output) || die "Could not create the VCN."
  echo "Created VCN"
else
  echo "Reusing VCN"
fi

step "Network: internet gateway"
IGW_ID=$(q network internet-gateway list --compartment-id "$COMPARTMENT" --vcn-id "$VCN_ID" --all \
  --query 'data[?"lifecycle-state"==`AVAILABLE`] | [0].id')
if [ -z "$IGW_ID" ]; then
  IGW_ID=$(oci network internet-gateway create --compartment-id "$COMPARTMENT" --vcn-id "$VCN_ID" \
    --display-name "$IGW_NAME" --is-enabled true \
    --wait-for-state AVAILABLE --query 'data.id' --raw-output) || die "Could not create the internet gateway."
  echo "Created internet gateway"
else
  echo "Reusing internet gateway"
fi

step "Network: route to the internet"
RT_ID=$(q network vcn get --vcn-id "$VCN_ID" --query 'data."default-route-table-id"')
oci network route-table update --rt-id "$RT_ID" --force \
  --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$IGW_ID\"}]" \
  --wait-for-state AVAILABLE >/dev/null || die "Could not update the route table."
echo "Default route -> internet gateway"

step "Network: public subnet"
SUBNET_ID=$(q network subnet list --compartment-id "$COMPARTMENT" --vcn-id "$VCN_ID" --all \
  --display-name "$SUBNET_NAME" --query 'data[?"lifecycle-state"==`AVAILABLE`] | [0].id')
if [ -z "$SUBNET_ID" ]; then
  SUBNET_ID=$(oci network subnet create --compartment-id "$COMPARTMENT" --vcn-id "$VCN_ID" \
    --display-name "$SUBNET_NAME" --cidr-block "10.0.0.0/24" --dns-label public \
    --wait-for-state AVAILABLE --query 'data.id' --raw-output) || die "Could not create the subnet."
  echo "Created public subnet (default security list: SSH 22 + ICMP only)"
else
  echo "Reusing public subnet"
fi

# ---------- 4. image ----------
step "Finding the latest Ubuntu 24.04 Arm (aarch64) image"
IMAGE_ID=$(q compute image list --compartment-id "$COMPARTMENT" --all \
  --operating-system "Canonical Ubuntu" --operating-system-version "24.04" --shape "$SHAPE" \
  --sort-by TIMECREATED --sort-order DESC \
  --query "data[?contains(\"display-name\", 'aarch64') && !contains(\"display-name\", 'Minimal')] | [0].id")
[ -n "$IMAGE_ID" ] || die "No Ubuntu 24.04 aarch64 image found in this region."
IMAGE_NAME=$(q compute image get --image-id "$IMAGE_ID" --query 'data."display-name"')
echo "Image: $IMAGE_NAME"

# ---------- 5. launch (with capacity retries) ----------
KEYFILE=$(mktemp); echo "$KEY" > "$KEYFILE"; trap 'rm -f "$KEYFILE"' EXIT

step "Creating VM '$NAME' (${OCPUS} OCPU / ${MEMORY_GB} GB / ${BOOT_GB} GB disk)"
INSTANCE_ID=""
for (( attempt=1; attempt<=MAX_ATTEMPTS; attempt++ )); do
  for AD in "${ADS[@]}"; do
    echo "Attempt $attempt/$MAX_ATTEMPTS in $AD ..."
    OUT=$(oci compute instance launch \
      --compartment-id "$COMPARTMENT" --availability-domain "$AD" \
      --display-name "$NAME" --shape "$SHAPE" \
      --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" \
      --image-id "$IMAGE_ID" --boot-volume-size-in-gbs "$BOOT_GB" \
      --subnet-id "$SUBNET_ID" --assign-public-ip true \
      --ssh-authorized-keys-file "$KEYFILE" \
      --wait-for-state RUNNING --query 'data.id' --raw-output 2>&1)
    STATUS=$?
    if [ $STATUS -eq 0 ]; then
      INSTANCE_ID=$(echo "$OUT" | grep -o 'ocid1\.instance[^" ]*' | tail -1)
      [ -n "$INSTANCE_ID" ] && break 2
    fi
    if echo "$OUT" | grep -qi "out of host capacity\|out of capacity"; then
      warn "Oracle is out of free Arm capacity in $AD right now."
    elif echo "$OUT" | grep -qi "LimitExceeded\|limit"; then
      die "Oracle says a limit would be exceeded:\n$OUT"
    else
      die "Launch failed:\n$OUT"
    fi
  done
  if (( attempt < MAX_ATTEMPTS )); then
    echo "Waiting ${RETRY_SECONDS}s before retrying (press Ctrl+C to stop; re-running is safe)..."
    sleep "$RETRY_SECONDS"
  fi
done
[ -n "$INSTANCE_ID" ] || die "Still no capacity after $MAX_ATTEMPTS attempts. Try again later (night / early morning works best)."

# ---------- 6. result ----------
IP=$(q compute instance list-vnics --instance-id "$INSTANCE_ID" --query 'data[0]."public-ip"')
step "Done! Your Always Free VM is RUNNING"
echo "Name:      $NAME"
echo "Shape:     $SHAPE  (${OCPUS} OCPU / ${MEMORY_GB} GB RAM)"
echo "Disk:      ${BOOT_GB} GB"
echo "Username:  ubuntu"
echo "Public IP: ${IP:-<check the Console>}"
show_connect_help "${IP:-<SERVER_IP>}"
