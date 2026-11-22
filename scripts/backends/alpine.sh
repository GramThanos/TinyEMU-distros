#!/usr/bin/env bash
# backends/alpine.sh <recipe_dir> <out_dir>
#
# Build an Alpine ext2 rootfs from the official minirootfs tarball, with NO root
# or loop mount (uses `mke2fs -d` to build ext2 straight from a directory tree).
# Adds packages via a chroot'd apk when the host can run the guest arch (i686
# runs on x86_64 with 32-bit libs; riscv64 through QEMU user mode, set up by
# scripts/binfmt.sh); otherwise skips them with a warning so they can be added
# at first boot. Applies the recipe overlay/, then runs the recipe's setup.sh
# (if any) inside the rootfs. The kernel is handled separately by
# scripts/kernel.sh.
#
# Emits: <out>/rootfs.ext2
set -euo pipefail
recipe_dir="$1"; out="$2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
yq() { python3 "$here/recipe.py" "$recipe_dir/recipe.yml" "$1"; }

ver="$(yq rootfs.version)"          # e.g. 3.20.3
mirror="$(yq rootfs.mirror)"
tarball="$(yq rootfs.minirootfs)"
size_mb="$(yq rootfs.size_mb)"
arch="$(yq arch)"                   # 'x86', 'riscv64': Alpine's release dir names
branch="v${ver%.*}"                 # 3.20.3 -> v3.20

work="$out/rootfs.dir"
rm -rf "$work"; mkdir -p "$work"

url="$mirror/$branch/releases/$arch/$tarball"
echo "-- fetching $url"
curl -fSL "$url" -o "$out/minirootfs.tar.gz"
tar -xzf "$out/minirootfs.tar.gz" -C "$work"

pkgs="$(yq rootfs.packages || true)"
if [ -n "${pkgs:-}" ]; then
  echo "-- installing packages: $pkgs"
  cp /etc/resolv.conf "$work/etc/resolv.conf" 2>/dev/null || true
  if bash "$here/binfmt.sh" "$arch" && chroot "$work" /sbin/apk --no-cache add $pkgs; then
    echo "-- packages installed"
  else
    echo "!! apk-in-chroot failed (arch mismatch / not root?) — add at first boot"
  fi
fi

if [ -d "$recipe_dir/overlay" ]; then
  echo "-- applying overlay/"
  cp -a "$recipe_dir/overlay/." "$work/"
fi

if [ -f "$recipe_dir/setup.sh" ]; then
  echo "-- running setup.sh in the rootfs"
  cp "$recipe_dir/setup.sh" "$work/tmp/setup.sh"
  bash "$here/binfmt.sh" "$arch" && chroot "$work" /bin/sh /tmp/setup.sh \
    || { echo "!! setup.sh failed"; exit 1; }
  rm -f "$work/tmp/setup.sh"
fi

echo "-- mke2fs -d (${size_mb} MB, no mount)"
rm -f "$out/rootfs.ext2"
mke2fs -q -t ext2 -d "$work" "$out/rootfs.ext2" "${size_mb}M"
tune2fs -c0 -i0 "$out/rootfs.ext2" >/dev/null

# The kernel is handled centrally by scripts/kernel.sh (build.sh calls it next),
# so every rootfs flavour shares one prebuilt/build path.
echo "-- alpine rootfs ready in $out"
