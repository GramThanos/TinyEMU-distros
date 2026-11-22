#!/usr/bin/env bash
# backends/buildroot.sh <recipe_dir> <out_dir>
#
# STUB — not implemented. Build a fully custom rootfs (and optionally the kernel) from
# source with Buildroot. Ports the old build-harness flow:
#   * clone buildroot, apply recipe's buildroot.config as .config
#   * drop overlay/ (post-build.sh, init scripts, branding)
#   * apply linux.config (virtio-console/blk, e1000, 9p) if building the kernel
#   * make -jN  ->  output/images/{rootfs.ext2, bzImage|vmlinux}
#   * copy rootfs.ext2 + kernel into <out>/, then build.sh chunks it
#
# RISC-V doesn't need this backend: riscv64 images are built by the alpine /
# debian backends (see docs/riscv.md). A Buildroot riscv32/64 defconfig is an
# option once this backend exists.
set -euo pipefail
recipe_dir="$1"; out="$2"

cat >&2 <<EOF
!! buildroot backend is a stub — not implemented yet.
   recipe_dir=$recipe_dir out=$out
   See docs/flavour-buildroot.md for the flow to port.
EOF
exit 1
