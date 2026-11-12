#!/usr/bin/env bash
set -euo pipefail

VERSION="${MUTTER_VERSION:-50.1-0ubuntu2.5}"
JOBS="${JOBS:-$(nproc)}"
WORK="${WORK:-/var/tmp/mutter-build}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$REPO_ROOT/artifacts"
SRC_DIR="$WORK/mutter-${VERSION%%-*}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root inside the arm64 Ubuntu 26.04 environment (or chroot)." >&2
  exit 1
fi

for cmd in apt-get dpkg-buildpackage patch; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done

mkdir -p "$WORK" "$ARTIFACTS"
cd "$WORK"

if [ ! -d "$SRC_DIR" ]; then
  apt-get source "mutter=$VERSION"
fi

cd "$SRC_DIR"

if grep -q "Damage clips must be inside the framebuffer" \
    src/backends/native/meta-kms-update.c; then
  echo "Source already patched; remove $SRC_DIR to rebuild." >&2
  exit 1
fi

for patch_file in "$REPO_ROOT"/patches/*.patch; do
  echo "Applying $(basename "$patch_file")"
  patch -p1 < "$patch_file"
done

DEB_BUILD_OPTIONS="nocheck parallel=$JOBS" \
  dpkg-buildpackage -b -nc -uc -us -j"$JOBS"

cp -f "$WORK/libmutter-18-0_${VERSION}+y7001_arm64.deb" "$ARTIFACTS/"
cp -f "$WORK/gir1.2-mutter-18_${VERSION}+y7001_arm64.deb" "$ARTIFACTS/"
cp -f "$WORK/libmutter-18-0-dbgsym_${VERSION}+y7001_arm64.ddeb" "$ARTIFACTS/"
cp -f "$WORK/mutter_${VERSION}+y7001_arm64.buildinfo" "$ARTIFACTS/"
cp -f "$WORK/mutter_${VERSION}+y7001_arm64.changes" "$ARTIFACTS/"
(cd "$ARTIFACTS" && sha256sum *.deb *.ddeb > SHA256SUMS)

echo "Artifacts in $ARTIFACTS"
