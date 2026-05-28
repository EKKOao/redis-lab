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

mkdir -p "$REDIS_BASE_DIR" "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_BACKUP_DIR" "$REDIS_CONFIG_DIR"

is_mounted() {
  grep -qs " $1 " /proc/mounts
}

fstab_has() {
  grep -qs " $1 " /etc/fstab
}

has_mounts_or_children() {
  local disk=$1
  # Skip the OS disk and anything with mounted children.
  lsblk -nr "$disk" -o MOUNTPOINT | grep -qE '/|\[SWAP\]'
}

is_suitable_data_disk() {
  local disk=$1
  local min_bytes=${REDIS_MIN_LVM_DISK_BYTES:-10737418240}
  local size_bytes type rm

  [ -b "$disk" ] || return 1
  type=$(lsblk -dn -o TYPE "$disk" 2>/dev/null | awk '{print $1}')
  [ "$type" = "disk" ] || return 1

  rm=$(lsblk -dn -o RM "$disk" 2>/dev/null | awk '{print $1}')
  [ "${rm:-0}" = "0" ] || return 1

  size_bytes=$(lsblk -b -dn -o SIZE "$disk" 2>/dev/null | awk '{print $1}')
  [ -n "${size_bytes:-}" ] || return 1
  [ "$size_bytes" -ge "$min_bytes" ] || return 1

  has_mounts_or_children "$disk" && return 1

  # Skip disks already managed by LVM.
  if pvs --noheadings -o pv_name 2>/dev/null | awk '{$1=$1};1' | grep -qx "$disk"; then
    return 1
  fi

  return 0
}

find_unused_disk() {
  lsblk -dn -o NAME,TYPE | awk '$2 == "disk" {print "/dev/"$1}' | while read -r disk; do
    if is_suitable_data_disk "$disk"; then
      echo "$disk"
      return 0
    fi
  done
}

free_extents() {
  vgs --noheadings -o vg_free_count "$REDIS_VG" 2>/dev/null | awk '{$1=$1};1'
}

create_lv_mount() {
  local lv_name=$1
  local lv_size=$2
  local mountpoint=$3
  local device="/dev/$REDIS_VG/$lv_name"

  if ! lvs "$REDIS_VG/$lv_name" >/dev/null 2>&1; then
    if [ "$(free_extents)" -le 0 ]; then
      echo "No free extents left in $REDIS_VG; using directory fallback for $mountpoint." >&2
      return 0
    fi
    lvcreate -L "$lv_size" -n "$lv_name" "$REDIS_VG"
    mkfs.xfs -f "$device"
  fi

  mkdir -p "$mountpoint"
  if ! is_mounted "$mountpoint"; then
    mount "$device" "$mountpoint"
  fi
  if ! fstab_has "$mountpoint"; then
    echo "$device $mountpoint xfs noatime,nodiratime,defaults 0 0" >> /etc/fstab
  fi
}

if [ "${REDIS_USE_LVM:-true}" = "true" ]; then
  if ! vgs "$REDIS_VG" >/dev/null 2>&1; then
    DISK=${REDIS_LVM_DISK:-$(find_unused_disk || true)}
    if [ -n "${DISK:-}" ] && is_suitable_data_disk "$DISK"; then
      echo "Using dedicated Redis data disk: $DISK"
      pvcreate -ff -y "$DISK"
      vgcreate "$REDIS_VG" "$DISK"
    else
      echo "No suitable unused data disk found. Using root filesystem directories under $REDIS_BASE_DIR."
    fi
  fi

  if vgs "$REDIS_VG" >/dev/null 2>&1; then
    create_lv_mount redis_data "$REDIS_DATA_LV_SIZE" "$REDIS_DATA_DIR"
    create_lv_mount redis_logs "$REDIS_LOG_LV_SIZE" "$REDIS_LOG_DIR"
    create_lv_mount redis_backup "$REDIS_BACKUP_LV_SIZE" "$REDIS_BACKUP_DIR"
  fi
else
  echo "REDIS_USE_LVM=false; using root filesystem directories under $REDIS_BASE_DIR."
fi

chown -R "$REDIS_USER:$REDIS_GROUP" "$REDIS_BASE_DIR" "$REDIS_CONFIG_DIR"
chmod 0750 "$REDIS_BASE_DIR" "$REDIS_DATA_DIR" "$REDIS_LOG_DIR" "$REDIS_BACKUP_DIR" "$REDIS_CONFIG_DIR"
lsblk
