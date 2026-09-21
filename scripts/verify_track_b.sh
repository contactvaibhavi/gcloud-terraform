#!/usr/bin/env bash
# End-to-end smoke test for Track B (ansible/vpc.tf + packages.yaml).
#
# Prerequisites:
#   - gcloud, terraform, ansible-playbook, ansible
#   - ansible/key.json service-account key with Compute permissions
#   - Real values for SSH_USER, SSH_PUBLIC_KEY, SSH_PRIVATE_KEY (or edit vpc.tf)
#   - GCP_PROJECT
#
# Usage:
#   export GCP_PROJECT=your-project-id
#   export SSH_USER=$(whoami)
#   export SSH_PUBLIC_KEY=$HOME/.ssh/id_rsa.pub
#   export SSH_PRIVATE_KEY=$HOME/.ssh/id_rsa
#   # place key.json in ansible/ OR set GOOGLE_APPLICATION_CREDENTIALS and
#   # copy/symlink to ansible/key.json (vpc.tf hard-requires file("key.json"))
#   ./scripts/verify_track_b.sh
#
# Env:
#   SKIP_DESTROY=1  leave the VM up
#   KEEP_WORKDIR=1  keep temp dir

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_SRC="$ROOT/ansible"
ZONE="${ZONE:-us-east4-a}"
INSTANCE="${INSTANCE:-example-instance}"
WORKDIR=""
APPLIED=0

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_terraform() {
  if ! command -v terraform >/dev/null 2>&1; then
    die "Terraform is not installed or not on PATH.
Install Terraform >= 1.x (https://developer.hashicorp.com/terraform/install), then re-run.
macOS (Homebrew): brew tap hashicorp/tap && brew install hashicorp/tap/terraform"
  fi
  local ver
  ver="$(terraform version -json 2>/dev/null | sed -n 's/.*"terraform_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -z "$ver" ]]; then
    ver="$(terraform version | head -1 | awk '{print $2}' | sed 's/^v//')"
  fi
  log "Terraform $ver ($(command -v terraform))"
  local major="${ver%%.*}"
  [[ -n "$major" && "$major" -ge 1 ]] || die "Terraform >= 1.x required (found: ${ver:-unknown})"
}

cleanup() {
  local ec=$?
  if [[ "$APPLIED" -eq 1 && "${SKIP_DESTROY:-0}" != "1" && -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    log "destroying Track B resources in $WORKDIR"
    (cd "$WORKDIR" && terraform destroy -auto-approve) || {
      echo "WARNING: terraform destroy failed; check project ${GCP_PROJECT:-?}" >&2
      ec=1
    }
  elif [[ "$APPLIED" -eq 1 && "${SKIP_DESTROY:-0}" == "1" ]]; then
    echo "WARNING: SKIP_DESTROY=1; resources still running in $WORKDIR" >&2
  fi
  if [[ -n "$WORKDIR" && -d "$WORKDIR" && "${KEEP_WORKDIR:-0}" != "1" && "${SKIP_DESTROY:-0}" != "1" ]]; then
    rm -rf "$WORKDIR"
  fi
  exit "$ec"
}
trap cleanup EXIT

log "checking Terraform"
require_terraform
need_cmd ansible-playbook
need_cmd gcloud

GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "${GCP_PROJECT}" && "${GCP_PROJECT}" != "(unset)" ]] \
  || die "set GCP_PROJECT"

SSH_USER="${SSH_USER:-}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-}"
[[ -n "$SSH_USER" ]] || die "set SSH_USER (Linux username injected via instance metadata)"
[[ -n "$SSH_PUBLIC_KEY" && -f "$SSH_PUBLIC_KEY" ]] || die "set SSH_PUBLIC_KEY to an existing .pub file"
[[ -n "$SSH_PRIVATE_KEY" && -f "$SSH_PRIVATE_KEY" ]] || die "set SSH_PRIVATE_KEY to an existing private key file"

KEY_JSON="${KEY_JSON:-$ANSIBLE_SRC/key.json}"
[[ -f "$KEY_JSON" ]] || die "missing service-account key at $KEY_JSON (vpc.tf uses file(\"key.json\"))"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/gcloud-tf-verify-b.XXXXXX")"
log "workdir $WORKDIR"
cp "$ANSIBLE_SRC/vpc.tf" "$ANSIBLE_SRC/clusterinventory.tpl" "$ANSIBLE_SRC/packages.yaml" "$WORKDIR/"
cp "$KEY_JSON" "$WORKDIR/key.json"

# Rewrite placeholder defaults to real values for this run only.
python3 - "$WORKDIR/vpc.tf" "$GCP_PROJECT" "$SSH_PUBLIC_KEY" "$SSH_PRIVATE_KEY" "$SSH_USER" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
project, pub, priv, user = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
text = path.read_text()
replacements = {
    'default = "<YOUR HOME DIR>/.ssh/id_rsa.pub"': f'default = "{pub}"',
    'default = "<YOUR HOME DIR>/.ssh/id_rsa"': f'default = "{priv}"',
    'default = "<YOUR ID on VM>"': f'default = "{user}"',
    'project    = "<YOUR GCP PROJECT NAME>"': f'project    = "{project}"',
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"placeholder not found in vpc.tf: {old}")
    text = text.replace(old, new, 1)
path.write_text(text)
PY

cd "$WORKDIR"
log "terraform init"
terraform init -input=false
log "terraform validate"
terraform validate
log "terraform apply"
terraform apply -auto-approve -input=false
APPLIED=1

[[ -f cluster.inventory ]] || die "cluster.inventory was not written"
FIP="$(terraform output -raw instance_fip)"
log "instance_fip=$FIP"

log "waiting for SSH on $FIP"
ready=0
for ((i = 1; i <= 40; i++)); do
  if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -i "$SSH_PRIVATE_KEY" "${SSH_USER}@${FIP}" true 2>/dev/null; then
    ready=1
    break
  fi
  sleep 5
done
[[ "$ready" -eq 1 ]] || die "SSH to $FIP never succeeded"

log "ansible-playbook packages.yaml"
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i cluster.inventory packages.yaml

log "verifying packages on host"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i "$SSH_PRIVATE_KEY" "${SSH_USER}@${FIP}" \
  'command -v wget && command -v iperf3 && command -v iperf'

log "PASS: Track B packages installed on $FIP"
exit 0
