#!/usr/bin/env bash
# Deletes the cluster VMs and all data on them.
set -euo pipefail

NODES="cp-1 worker-1 worker-2"

read -r -p "Delete $NODES and all their data? [y/N] " answer
[[ "$answer" == "y" ]] || exit 0

for name in $NODES; do
  if multipass info "$name" >/dev/null 2>&1; then
    multipass delete --purge "$name"
    echo "Deleted $name"
  fi
done
