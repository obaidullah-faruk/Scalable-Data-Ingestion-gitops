#!/usr/bin/env bash
# Creates the cluster VMs. Safe to rerun: existing VMs are left as they are.
set -euo pipefail

UBUNTU_RELEASE="24.04"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/homelab_ed25519.pub}"

# name cpus memory disk
NODES="
cp-1     2 2.5G 15G
worker-1 2 4G   25G
worker-2 2 4G   20G
"

cd "$(dirname "$0")"

if [[ ! -f "$SSH_PUBLIC_KEY_FILE" ]]; then
  echo "SSH public key not found: $SSH_PUBLIC_KEY_FILE" >&2
  exit 1
fi
ssh_public_key="$(<"$SSH_PUBLIC_KEY_FILE")"
user_data="$(sed "s|\${SSH_PUBLIC_KEY}|$ssh_public_key|" cloud-init.yaml)"

while read -r name cpus memory disk; do
  [[ -z "$name" ]] && continue

  if multipass info "$name" >/dev/null 2>&1; then
    echo "$name already exists, skipping"
    continue
  fi

  echo "Creating $name"
  multipass launch "$UBUNTU_RELEASE" \
    --name "$name" \
    --cpus "$cpus" \
    --memory "$memory" \
    --disk "$disk" \
    --cloud-init - <<<"$user_data"
done <<<"$NODES"

multipass list
