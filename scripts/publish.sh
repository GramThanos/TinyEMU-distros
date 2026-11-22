#!/usr/bin/env bash
# publish.sh <recipe-name> — package a built distro and upload it as a release
# artifact.
#
# Host-agnostic by design: the default uploads to GitHub Releases via `gh`, but
# the .cfg only needs its ${ASSET_BASE} pointed at wherever these files end up,
# so swapping hosts is a one-line change to the upload step below.
#
# The published tarball contains: kernel.bin, blk.txt, the chunks (blk*.bin or,
# compressed, blk*.bin.gz), config.cfg, and
# bios.bin for RISC-V recipes.
set -euo pipefail
name="${1:?usage: publish.sh <recipe-name>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$root/build/$name"
[ -d "$out" ] || { echo "not built: $out (run build.sh $name first)"; exit 1; }

tag="distro-$name"
tar="$root/build/$name.tar"
echo "== packaging $out -> $tar"
( cd "$out" && tar -cf "$tar" kernel.bin $([ -f "$out/bios.bin" ] && echo bios.bin) blk.txt blk*.bin* config.cfg )

if command -v gh >/dev/null 2>&1; then
  echo "== uploading to GitHub Release '$tag'"
  gh release view "$tag" >/dev/null 2>&1 || \
    gh release create "$tag" -t "$name distro image" \
       -n "Auto-built TinyEMU distro image ($name)."
  gh release upload "$tag" "$tar" --clobber
  echo "== uploaded. Point \${ASSET_BASE} at the release's extracted files when rendering the .cfg."
else
  echo "gh not found — artifact is packaged at:"
  echo "    $tar"
  echo "Upload it to your host and set \${ASSET_BASE} to its base URL."
fi
