#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 08 (part 1): create free backup storage
#
# Run in ORACLE CLOUD SHELL (not on the VM):
#   bash 08-create-backup-bucket.sh
#
# Creates, inside Always Free limits (20 GB Object Storage):
#   - a PRIVATE bucket "free-ai-lab-backups"
#   - an S3-compatible access key pair (Customer Secret Key) for restic
# and prints the 4 values the VM backup installer asks for.
# =============================================================================
set -uo pipefail
BUCKET="${BUCKET:-free-ai-lab-backups}"

c_ok="\033[32m"; c_warn="\033[33m"; c_err="\033[31m"; c_off="\033[0m"
step() { echo -e "\n${c_ok}==>${c_off} $*"; }
die()  { echo -e "${c_err}[x] $*${c_off}" >&2; exit 1; }
q()    { oci "$@" --raw-output 2>/dev/null | grep -v '^null$' || true; }

[ -n "${OCI_TENANCY:-}" ] || die "Run this in Oracle Cloud Shell."
REGION="${OCI_REGION:?}"
USER_OCID="${OCI_CS_USER_OCID:-}"
[ -n "$USER_OCID" ] || die "OCI_CS_USER_OCID is not set. Open Cloud Shell from the Console and try again."

step "1/3  Object Storage namespace"
NS=$(q os ns get --query data)
[ -n "$NS" ] || die "Could not read the Object Storage namespace."
echo "Namespace: $NS   Region: $REGION"

step "2/3  Private bucket '$BUCKET'"
if oci os bucket get --bucket-name "$BUCKET" >/dev/null 2>&1; then
  echo "Bucket already exists."
else
  oci os bucket create --name "$BUCKET" --compartment-id "$OCI_TENANCY" \
    --public-access-type NoPublicAccess --storage-tier Standard >/dev/null || die "Could not create the bucket."
  echo "Created (private, Standard tier)."
fi

step "3/3  S3-compatible access key for backups"
EXISTING=$(q iam customer-secret-key list --user-id "$USER_OCID" \
  --query "data[?\"display-name\"=='free-ai-lab-restic' && \"lifecycle-state\"=='ACTIVE'] | [0].id")
if [ -n "$EXISTING" ]; then
  echo -e "${c_warn}A key named 'free-ai-lab-restic' already exists (Access Key: $EXISTING).${c_off}"
  echo "Its secret can't be shown again. If you lost it, delete it in the Console"
  echo "(Profile → User settings → Customer secret keys) and run this script again."
  SECRET="(already created earlier — use the secret you saved)"
  ACCESS="$EXISTING"
else
  OUT=$(oci iam customer-secret-key create --user-id "$USER_OCID" --display-name free-ai-lab-restic 2>&1) \
    || die "Could not create the key (each user can have at most 2):\n$OUT"
  ACCESS=$(echo "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["id"])')
  SECRET=$(echo "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["key"])')
fi

ENDPOINT="https://${NS}.compat.objectstorage.${REGION}.oci.customer-oci.com"
step "Done! Copy these 4 values into the VM installer (08-install-backup.sh):"
echo
echo "  S3 endpoint : $ENDPOINT"
echo "  Bucket      : $BUCKET"
echo "  Region      : $REGION"
echo "  Access key  : $ACCESS"
echo "  Secret key  : $SECRET"
echo
echo -e "${c_warn}The secret key is shown ONLY NOW. Keep it in a password manager; never put it on GitHub.${c_off}"
echo "Tip: type  clear  after copying, so it doesn't stay on screen."
