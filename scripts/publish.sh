#!/usr/bin/env bash
# publish.sh [-t TAG] [--latest] [--pack-only] [--no-raw] <recipe-name>...
#
# Package built distros and upload them, together, to one release.
#
#   -t TAG       release tag to upload to (created if missing). Default, for a
#                single recipe only: distro-<name>.
#   --latest     mark the release as the repository's latest release
#                (so .../releases/latest/download/<file> points at it).
#   --pack-only  only stage the files in build/release/; don't upload.
#   --no-raw     only the .tar, not the raw files.
#
# Per recipe, staged in build/release/ from build/<name>/:
#   <name>.tar          kernel.bin, blk.txt, the chunks (blk*.bin[.gz]), config.cfg
#                       (literal ${ASSET_BASE}), bios.bin for RISC-V — for hosting
#   <name>-kernel.bin   raw kernel
#   <name>-bios.bin     raw OpenSBI firmware (RISC-V only)
#   <name>-rootfs.img.gz  the whole ext2 disk image (rootfs.ext2), unchunked,
#                       gzipped (mostly free space: 256 MB -> ~40 MB)
#   <name>-config.cfg   config that boots the raw files above, by relative path,
#                       when they sit in one directory (e.g. native `temu`) and
#                       <name>-rootfs.img.gz has been gunzipped to <name>-rootfs.img
#
# If build/<name>/ is missing but build/release/<name>.tar exists (e.g.
# downloaded from an earlier CI job), the staged files are uploaded as they are.
#
# Host-agnostic by design: the default uploads to GitHub Releases via `gh`, but
# the .cfg only needs its ${ASSET_BASE} pointed at wherever these files end up,
# so swapping hosts is a change to the upload step below.
set -euo pipefail
usage() { echo "usage: publish.sh [-t TAG] [--latest] [--pack-only] [--no-raw] <recipe-name>..." >&2; exit 1; }

tag=""; latest=0; pack_only=0; raw=1; names=()
while [ $# -gt 0 ]; do
  case "$1" in
    -t|--tag)    [ $# -ge 2 ] || usage; tag="$2"; shift 2 ;;
    --latest)    latest=1; shift ;;
    --pack-only) pack_only=1; shift ;;
    --no-raw)    raw=0; shift ;;
    -h|--help)   usage ;;
    -*)          echo "unknown option: $1" >&2; usage ;;
    *)           names+=("$1"); shift ;;
  esac
done
[ ${#names[@]} -gt 0 ] || usage
if [ -z "$tag" ] && [ "$pack_only" = 0 ]; then
  [ ${#names[@]} -eq 1 ] || { echo "several recipes need a release tag: -t TAG" >&2; exit 1; }
  tag="distro-${names[0]}"
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
stage="$root/build/release"
mkdir -p "$stage"

raw_suffixes=(kernel.bin bios.bin rootfs.img.gz config.cfg)

stage_recipe() {   # build/<name>/ -> build/release/<name>.tar + <name>-*
  local name="$1" out="$root/build/$1" s
  rm -f "$stage/$name.tar" "$stage/$name-rootfs.img"
  for s in "${raw_suffixes[@]}"; do rm -f "$stage/$name-$s"; done

  echo "== packaging $out -> $stage/$name.tar"
  ( cd "$out" && tar -cf "$stage/$name.tar" kernel.bin $([ -f bios.bin ] && echo bios.bin) blk.txt blk*.bin* config.cfg )

  [ "$raw" = 1 ] || return 0
  echo "== raw files -> $stage/$name-{kernel.bin,rootfs.img.gz,config.cfg$([ -f "$out/bios.bin" ] && echo ,bios.bin)}"
  cp -f "$out/kernel.bin" "$stage/$name-kernel.bin"
  if [ -f "$out/bios.bin" ]; then cp -f "$out/bios.bin" "$stage/$name-bios.bin"; fi
  [ -f "$out/rootfs.ext2" ] || { echo "missing $out/rootfs.ext2 (needed for the raw image)" >&2; exit 1; }
  # -n: no name/timestamp in the header, so the same disk gives the same .gz
  gzip -9 -n -c "$out/rootfs.ext2" > "$stage/$name-rootfs.img.gz"
  # Point the config at the raw files, side by side, instead of ${ASSET_BASE}/...
  sed -e "s#\${ASSET_BASE}/kernel\.bin#$name-kernel.bin#g" \
      -e "s#\${ASSET_BASE}/bios\.bin#$name-bios.bin#g" \
      -e "s#\${ASSET_BASE}/blk\.txt#$name-rootfs.img#g" \
      -e "s#^ \* \${ASSET_BASE} is where.*\*/\$# * Boots the raw release files ($name-*) placed in the same directory;\n * gunzip $name-rootfs.img.gz first. */#" \
      "$out/config.cfg" > "$stage/$name-config.cfg"
  if grep -q '"\${ASSET_BASE}' "$stage/$name-config.cfg"; then
    echo "!! $name-config.cfg still references \${ASSET_BASE} (not a block-mode recipe?)" >&2
  fi
}

assets=()
for name in "${names[@]}"; do
  if [ -d "$root/build/$name" ]; then
    stage_recipe "$name"
  elif [ -f "$stage/$name.tar" ]; then
    echo "== using staged $stage/$name.tar (+ raw files, if any)"
  else
    echo "not built: $root/build/$name (run build.sh $name first)" >&2; exit 1
  fi
  assets+=("$stage/$name.tar")
  if [ "$raw" = 1 ]; then
    for s in "${raw_suffixes[@]}"; do
      if [ -f "$stage/$name-$s" ]; then assets+=("$stage/$name-$s"); fi
    done
  fi
done

[ "$pack_only" = 1 ] && { echo "== staged (not uploaded):"; printf '    %s\n' "${assets[@]}"; exit 0; }

if ! command -v gh >/dev/null 2>&1; then
  echo "gh not found — files are staged at:"
  printf '    %s\n' "${assets[@]}"
  echo "Upload them to your host and set \${ASSET_BASE} (in the .tar's config.cfg) to its base URL."
  exit 0
fi

if ! gh release view "$tag" >/dev/null 2>&1; then
  echo "== creating GitHub Release '$tag'"
  create=(gh release create "$tag" -t "TinyEMU distro images ($tag)" -n "Auto-built TinyEMU distro images.")
  if [ -n "${GITHUB_SHA:-}" ]; then create+=(--target "$GITHUB_SHA"); fi
  "${create[@]}"
fi

echo "== uploading ${#assets[@]} file(s) to '$tag'"
gh release upload "$tag" "${assets[@]}" --clobber

# Keep the notes in step with what the release holds (re-runs may add images).
list="$(gh release view "$tag" --json assets --jq '.assets[].name' | sort)"
notes="Auto-built TinyEMU distro images. Per image \`<name>\`:

- \`<name>.tar\` — for hosting: kernel.bin, blk.txt, the rootfs chunks, config.cfg (with a literal \${ASSET_BASE}) and, for RISC-V, bios.bin.
- \`<name>-kernel.bin\`, \`<name>-rootfs.img.gz\` (whole ext2 disk, gzipped), \`<name>-bios.bin\` (RISC-V) — the raw files.
- \`<name>-config.cfg\` — boots the raw files when they are in the same directory, after \`gunzip <name>-rootfs.img.gz\` (e.g. \`temu <name>-config.cfg\`).

Files:
$(printf '%s\n' "$list" | sed 's/^/- `/; s/$/`/')"
edit=(gh release edit "$tag" --notes "$notes")
if [ "$latest" = 1 ]; then edit+=(--latest); fi
"${edit[@]}"

echo "== uploaded to '$tag'."
