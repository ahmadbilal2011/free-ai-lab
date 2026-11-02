#!/usr/bin/env bash
# =============================================================================
# free-ai-lab — Lesson 07 (part 1): create free backup storage
#
# Run in ORACLE CLOUD SHELL (not on the server):
#   curl -fsSL https://raw.githubusercontent.com/ahmadbilal2011/free-ai-lab/main/scripts/07-create-backup-bucket.sh -o 07-create-backup-bucket.sh && bash 07-create-backup-bucket.sh
#
# Creates, inside Always Free limits (20 GB Object Storage):
#   - a PRIVATE bucket "free-ai-lab-backups"
#   - an S3-compatible access key pair (Customer Secret Key) for restic
# and prints the 5 values the server's backup installer asks for.
#
# Coming from the first version of the course? It reuses the bucket, offers to
# delete the old backups in it, and replaces the old access key (its secret was
# deleted with the old server settings).
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
  OLD=$(oci os object list --bucket-name "$BUCKET" --prefix restic/ --limit 1 --query 'length(data)' --raw-output 2>/dev/null || echo 0)
  if [ -n "$OLD" ] && [ "$OLD" != "0" ] && [ "$OLD" != "null" ]; then
    echo -e "${c_warn}It still holds backups from the first version of the course (folder restic/).${c_off}"
    echo "Their password was deleted with the old server settings, so they can't be restored any more."
    read -r -p "Delete them to free the space? [Y/n] " yn
    case "${yn:-Y}" in
      [Nn]*) echo "Kept. New backups go to a separate folder (jarvis/)." ;;
      *) oci os object bulk-delete --bucket-name "$BUCKET" --prefix restic/ --force >/dev/null && echo "Old backups deleted." ;;
    esac
  fi
else
  oci os bucket create --name "$BUCKET" --compartment-id "$OCI_TENANCY" \
    --public-access-type NoPublicAccess --storage-tier Standard >/dev/null || die "Could not create the bucket."
  echo "Created (private, Standard tier)."
fi

step "3/3  S3-compatible access key for backups"
EXISTING=$(q iam customer-secret-key list --user-id "$USER_OCID" \
  --query "data[?\"display-name\"=='free-ai-lab-restic' && \"lifecycle-state\"=='ACTIVE'] | [0].id")
REUSE=""
if [ -n "$EXISTING" ]; then
  echo -e "${c_warn}A key named 'free-ai-lab-restic' already exists.${c_off} Its secret can't be shown again."
  read -r -p "Do you still have its secret saved in your password manager? [y/N] " yn
  case "${yn:-N}" in
    [Yy]*) REUSE=1; ACCESS="$EXISTING"; SECRET="(the secret you saved earlier)" ;;
    *) oci iam customer-secret-key delete --user-id "$USER_OCID" --customer-secret-key-id "$EXISTING" --force >/dev/null \
         && echo "Old key deleted; creating a new one." \
         || die "Could not delete the old key. Delete it in the Console (Profile → Customer secret keys) and run again." ;;
  esac
fi
if [ -z "$REUSE" ]; then
  OUT=$(oci iam customer-secret-key create --user-id "$USER_OCID" --display-name free-ai-lab-restic 2>&1) \
    || die "Could not create the key (each user can have at most 2):\n$OUT"
  ACCESS=$(echo "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["id"])')
  SECRET=$(echo "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["key"])')
fi

ENDPOINT="https://${NS}.compat.objectstorage.${REGION}.oci.customer-oci.com"
step "Done! The server's installer (07-install-backup.sh) asks for these 5 values:"
echo
echo "  S3 endpoint : $ENDPOINT"
echo "  Bucket      : $BUCKET"
echo "  Region      : $REGION"
echo "  Access key  : $ACCESS"
echo "  Secret key  : $SECRET"
echo
echo -e "${c_warn}The secret key is shown ONLY NOW. Keep it in a password manager; never put it on GitHub.${c_off}"
echo "Tip: type  clear  after copying, so it doesn't stay on screen."
