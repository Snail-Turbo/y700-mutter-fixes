#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROOT="${CHROOT:-}"

if [ -z "$CHROOT" ] || [ ! -d "$CHROOT" ]; then
  echo "Usage: CHROOT=/path/to/arm64-chroot $0" >&2
  exit 1
fi

sudo mkdir -p "$CHROOT/mnt/mutter-fixes" "$CHROOT/proc" "$CHROOT/sys" "$CHROOT/dev"
sudo mountpoint -q "$CHROOT/mnt/mutter-fixes" || \
  sudo mount --bind "$REPO_ROOT" "$CHROOT/mnt/mutter-fixes"
sudo mountpoint -q "$CHROOT/proc" || sudo mount -t proc proc "$CHROOT/proc"
sudo mountpoint -q "$CHROOT/sys" || sudo mount --rbind /sys "$CHROOT/sys"
sudo mountpoint -q "$CHROOT/dev" || sudo mount --rbind /dev "$CHROOT/dev"

sudo chroot "$CHROOT" /mnt/mutter-fixes/scripts/build.sh
sudo chown -R "$(id -u):$(id -g)" "$REPO_ROOT/artifacts"
