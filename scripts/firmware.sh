#!/usr/bin/env bash
# scripts/firmware.sh <recipe_dir> <out>
#
# Produce <out>/bios.bin, the M-mode firmware a RISC-V guest boots through. x86
# recipes have none (TinyEMU's PC machine needs no BIOS image), and this script
# does nothing for them.
#
#   firmware.opensbi: "1.6"     build OpenSBI's generic fw_jump from source
#   firmware.sha256:  "..."     optional: the source tarball's sha256
#
# TinyEMU's riscv machine puts the firmware at 0x80000000 and the kernel after
# it, aligned to 2 MB (riscv64) or 4 MB (riscv32): 0x80200000 / 0x80400000,
# which is exactly where the generic fw_jump jumps. It hands over its device
# tree in a1, and fw_jump moves that to 34 MB into RAM (FW_JUMP_FDT_OFFSET)
# before starting the kernel, so the kernel Image must stay under 32 MB and the
# guest needs more than 34 MB of RAM. Built with clang/LLVM, which gives a
# position-independent image. OpenSBI is BSD-2-Clause.
set -euo pipefail
recipe_dir="$1"; out="$2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
yq() { python3 "$here/recipe.py" "$recipe_dir/recipe.yml" "$1" 2>/dev/null || true; }

arch="$(yq arch)"
case "$arch" in
  riscv64) xlen=64 ;;
  riscv32) xlen=32 ;;
  *) rm -f "$out/bios.bin"; exit 0 ;;
esac

ver="$(yq firmware.opensbi)"
want_sha="$(yq firmware.sha256)"
[ -n "$ver" ] || { echo "!! arch $arch needs firmware.opensbi (an OpenSBI version) in the recipe"; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/tinyemu-opensbi.XXXXXX")"
trap 'rm -rf "$work"' EXIT
url="https://github.com/riscv-software-src/opensbi/archive/refs/tags/v$ver.tar.gz"
echo "-- firmware: fetching OpenSBI $ver ($url)"
curl -fSL "$url" -o "$work/opensbi.tar.gz"
if [ -n "$want_sha" ]; then
  got_sha="$(sha256sum "$work/opensbi.tar.gz" | cut -d' ' -f1)"
  [ "$got_sha" = "$want_sha" ] || { echo "!! OpenSBI source sha256 is $got_sha, the recipe pins $want_sha"; exit 1; }
  echo "-- firmware: sha256 verified"
fi
mkdir -p "$work/src"
tar -xzf "$work/opensbi.tar.gz" -C "$work/src" --strip-components=1

echo "-- firmware: building generic fw_jump (rv$xlen)"
make -C "$work/src" -j"$(nproc)" LLVM=1 \
  PLATFORM=generic PLATFORM_RISCV_XLEN=$xlen FW_JUMP=y FW_PAYLOAD=n FW_DYNAMIC=n \
  >"$work/build.log" 2>&1 || { tail -40 "$work/build.log"; echo "!! OpenSBI build failed"; exit 1; }
cp "$work/src/build/platform/generic/firmware/fw_jump.bin" "$out/bios.bin"
echo "-- firmware: built $(du -h "$out/bios.bin" | cut -f1) -> $out/bios.bin"
rm -rf "$work"; trap - EXIT
