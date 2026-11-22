#!/usr/bin/env bash
# scripts/build.sh — build one distro from its recipe.
#
# Reads recipes/<name>/recipe.yml, dispatches to the matching backend,
# then chunks the rootfs and renders the .cfg. Output lands in
# build/<name>/{kernel.bin, rootfs.ext2, blk*.bin[.gz], blk.txt, config.cfg}, plus
# bios.bin (OpenSBI) for RISC-V recipes.
#
# Meant to run in the build container (Debian + e2fsprogs + curl + python3-yaml).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"          # repo root

usage() { echo "usage: build.sh <recipe-name>   (a dir under recipes/)"; exit 1; }
[ $# -eq 1 ] || usage
name="$1"
recipe_dir="$root/recipes/$name"
[ -f "$recipe_dir/recipe.yml" ] || { echo "no recipe: $recipe_dir/recipe.yml"; exit 1; }

yq() { python3 "$here/recipe.py" "$recipe_dir/recipe.yml" "$1"; }

backend="$(yq backend)"
out="$root/build/$name"
mkdir -p "$out"

echo "== building '$name' (backend=$backend) -> $out"
case "$backend" in
  alpine)    "$here/backends/alpine.sh"    "$recipe_dir" "$out" ;;
  debian)    "$here/backends/debian.sh"    "$recipe_dir" "$out" ;;
  buildroot) "$here/backends/buildroot.sh" "$recipe_dir" "$out" ;;
  *) echo "unknown backend: $backend"; exit 1 ;;
esac

echo "== kernel (source=$(yq kernel.source))"
"$here/kernel.sh" "$recipe_dir" "$out"

# RISC-V guests boot through OpenSBI (bios.bin); x86 needs no firmware image.
case "$(yq arch)" in riscv*) echo "== firmware"; "$here/firmware.sh" "$recipe_dir" "$out" ;; esac

mode="$(yq disk.mode)"
if [ "$mode" = "block" ]; then
  comp="$(yq disk.compression 2>/dev/null || true)"; comp="${comp:-none}"
  echo "== chunking rootfs (block_size=$(yq disk.block_size_kb) KB, compression=$comp)"
  rm -f "$out"/blk*.bin "$out"/blk*.bin.gz   # never keep chunks of an earlier build
  python3 "$here/chunk.py" "$out/rootfs.ext2" -b "$(yq disk.block_size_kb)" -c "$comp" -o "$out"
else
  echo "== disk.mode=$mode — skipping chunking (9p/fs0 image left as-is)"
fi

echo "== rendering config.cfg"
python3 "$here/mkconfig.py" "$recipe_dir" --asset-base '${ASSET_BASE}' -o "$out/config.cfg"

# Drop build intermediates so build/<dist>/ holds only hostable files:
# kernel.bin, bios.bin (RISC-V), rootfs.ext2, blk.txt, the chunks, config.cfg. The user uploads this
# dir wherever they like and points ${ASSET_BASE} in config.cfg at it.
echo "== cleaning intermediates"
rm -rf "$out/rootfs.dir" "$out/minirootfs.tar.gz" "$out/rootfs.tar"

echo "== done: $out"
ls -la "$out" | grep -v ' blk[0-9]' ; echo "  (+ $(ls "$out" | grep -c '^blk[0-9]') chunks)"
