#!/usr/bin/env bash
# backends/debian.sh <recipe_dir> <out_dir>
#
# Build a Debian ext2 rootfs from a PINNED prebuilt rootfs (chosen for
# reproducibility), using `mke2fs -d` (no root/loop mount). Same shape as
# alpine.sh; the only difference is the rootfs source. The kernel is handled
# separately by scripts/kernel.sh.
#
# The rootfs comes from one of:
#   rootfs.image + rootfs.digest   a single-layer image on Docker Hub, fetched
#                                  as its layer blob by digest (the official
#                                  i386/debian images are one layer), e.g.
#                                  image: i386/debian, digest: sha256:...
#   rootfs.tarball_url             any rootfs tarball URL (pin it); checked
#                                  against rootfs.sha256 when that is set
# Either way the download is verified against its sha256 before use.
#
# rootfs.packages are then installed with a chroot'd apt-get when the host can
# run the guest arch (i386 binaries run on an x86_64 builder, riscv64 ones
# through QEMU user mode, set up by scripts/binfmt.sh); otherwise they
# are skipped with a warning. That step uses the network, so it is the one part
# that is not byte-for-byte reproducible. The recipe overlay/ is applied next,
# then the recipe's setup.sh (if any) runs inside the rootfs.
#
# Emits: <out>/rootfs.ext2
set -euo pipefail
recipe_dir="$1"; out="$2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
yq() { python3 "$here/recipe.py" "$recipe_dir/recipe.yml" "$1" 2>/dev/null || true; }

image="$(yq rootfs.image)"
digest="$(yq rootfs.digest)"
tarball_url="$(yq rootfs.tarball_url)"
want_sha="$(yq rootfs.sha256)"
size_mb="$(yq rootfs.size_mb)"
arch="$(yq arch)"

if [ -n "$image" ] && [ -n "$digest" ]; then
  # Docker Hub hands anonymous pull tokens per repository.
  echo "-- fetching $image layer $digest from Docker Hub"
  token="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$image:pull" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
  curl -fSL -H "Authorization: Bearer $token" \
    "https://registry-1.docker.io/v2/$image/blobs/$digest" -o "$out/rootfs.tar"
  want_sha="${digest#sha256:}"
elif [ -n "$tarball_url" ]; then
  echo "-- fetching $tarball_url"
  curl -fSL "$tarball_url" -o "$out/rootfs.tar"
else
  cat >&2 <<'EOF'
!! debian backend: the recipe names no rootfs. Set either
   rootfs.image + rootfs.digest (a single-layer Docker Hub image, by digest), or
   rootfs.tarball_url (+ rootfs.sha256) to a pinned Debian rootfs tarball.
EOF
  exit 1
fi

if [ -n "$want_sha" ]; then
  got_sha="$(sha256sum "$out/rootfs.tar" | cut -d' ' -f1)"
  [ "$got_sha" = "$want_sha" ] || { echo "!! rootfs sha256 is $got_sha, the recipe pins $want_sha"; exit 1; }
  echo "-- sha256 verified"
fi

work="$out/rootfs.dir"
rm -rf "$work"; mkdir -p "$work"
# tar detects gzip/xz itself.
tar -xf "$out/rootfs.tar" -C "$work"

pkgs="$(yq rootfs.packages)"
if [ -n "${pkgs:-}" ]; then
  echo "-- installing packages: $pkgs"
  cp /etc/resolv.conf "$work/etc/resolv.conf" 2>/dev/null || true
  # Maintainer scripts need a few device nodes; the image has an empty /dev.
  # Docker grants CAP_MKNOD by default; the nodes go again before mke2fs (the
  # guest kernel mounts devtmpfs over /dev).
  for n in "null c 1 3" "zero c 1 5" "random c 1 8" "urandom c 1 9" "tty c 5 0"; do
    set -- $n; rm -f "$work/dev/$1"; mknod -m 666 "$work/dev/$1" "$2" "$3" "$4" || true
  done
  # No maintainer script may start a service in the build chroot.
  printf '#!/bin/sh\nexit 101\n' > "$work/usr/sbin/policy-rc.d"; chmod +x "$work/usr/sbin/policy-rc.d"
  if bash "$here/binfmt.sh" "$arch" && chroot "$work" /usr/bin/env DEBIAN_FRONTEND=noninteractive \
       sh -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends $pkgs"; then
    echo "-- packages installed"
  else
    echo "!! apt-get in chroot failed (arch mismatch / not root?) — add packages at first boot"
  fi
  chroot "$work" apt-get clean >/dev/null 2>&1 || true
  rm -rf "$work"/var/lib/apt/lists/* "$work"/dev/* "$work/etc/resolv.conf" "$work/usr/sbin/policy-rc.d"
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

# Kernel handled centrally by scripts/kernel.sh (build.sh calls it next).
echo "-- debian rootfs ready in $out"
