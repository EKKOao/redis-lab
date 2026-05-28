#!/usr/bin/env bash
set -euo pipefail

swapoff -a || true
cp -a /etc/fstab /etc/fstab.bak.$(date +%Y%m%d%H%M%S)
sed -i.bak '/[[:space:]]swap[[:space:]]/s/^/# disabled for redis: /' /etc/fstab

if [ "$(swapon --show | wc -l)" -eq 0 ]; then
  echo "Swap is disabled."
else
  echo "Swap is still active:"
  swapon --show
  exit 1
fi
