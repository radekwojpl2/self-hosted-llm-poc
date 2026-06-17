#!/usr/bin/env bash
set -euxo pipefail

# --- Persistent data disk (LUN 0) for models ---
DISK=$(ls /dev/disk/azure/scsi1/lun0 2>/dev/null || true)
DISK=$(readlink -f "$DISK")
if [ -n "$DISK" ]; then
  if ! blkid "$DISK"; then
    mkfs.ext4 -F "$DISK"
  fi
  mkdir -p /mnt/models
  UUID=$(blkid -s UUID -o value "$DISK")
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID /mnt/models ext4 defaults,nofail 0 2" >> /etc/fstab
  mount -a
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y jq curl ubuntu-drivers-common tmux
ubuntu-drivers install
