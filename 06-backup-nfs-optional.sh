#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$SCRIPT_DIR/00-env.sh" ]; then
  # shellcheck source=00-env.sh
  source "$SCRIPT_DIR/00-env.sh"
elif [ -f /vagrant/00-env.sh ]; then
  # Vagrant's shell path provisioner copies scripts to /tmp; this fallback keeps manual/path execution safe.
  # shellcheck source=/vagrant/00-env.sh
  source /vagrant/00-env.sh
else
  echo "Unable to locate 00-env.sh. Run from the project directory or through Vagrant." >&2
  exit 1
fi

if [ "$ENABLE_NFS_BACKUP" != "true" ]; then
  echo "ENABLE_NFS_BACKUP=false; skipping optional backup NFS setup."
  exit 0
fi

HOSTNAME=$(hostname -s)
mkdir -p "$REDIS_BACKUP_DIR"
chown "$REDIS_USER:$REDIS_GROUP" "$REDIS_BACKUP_DIR"
chmod 0750 "$REDIS_BACKUP_DIR"

if [ "$HOSTNAME" = "$REDIS_CLUSTER_CREATOR_HOSTNAME" ]; then
  apt-get update -y
  apt-get install -y nfs-kernel-server
  if ! grep -q "^$REDIS_BACKUP_DIR " /etc/exports; then
    echo "$REDIS_BACKUP_DIR $NFS_BACKUP_NETWORK(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
  fi
  exportfs -a
  systemctl enable --now nfs-kernel-server
else
  apt-get update -y
  apt-get install -y nfs-common
  if ! grep -q "$NFS_BACKUP_SERVER_IP:$REDIS_BACKUP_DIR" /proc/mounts; then
    mount "$NFS_BACKUP_SERVER_IP:$REDIS_BACKUP_DIR" "$REDIS_BACKUP_DIR"
  fi
  if ! grep -q "$NFS_BACKUP_SERVER_IP:$REDIS_BACKUP_DIR" /etc/fstab; then
    echo "$NFS_BACKUP_SERVER_IP:$REDIS_BACKUP_DIR $REDIS_BACKUP_DIR nfs defaults,_netdev 0 0" >> /etc/fstab
  fi
fi
