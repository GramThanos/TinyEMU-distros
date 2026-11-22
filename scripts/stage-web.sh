#!/usr/bin/env bash
# stage-web.sh <recipe-name> <jsLab-dir> [origin]
#
# Stage a built distro into a jsLab checkout (github.com/gramthanos/jsLab) for
# local, same-origin serving, and register it in <jsLab-dir>/_distro/manifest.json
# so its demos (demos/demo.html, demos/linux-distro.html) offer it in a dropdown. Assets are copied under <web-dir>/_distro/<name>/ and the .cfg is
# rendered with ABSOLUTE URLs against the local serving origin — required because
# the browser resolves the kernel URL relative to the .cfg dir but the drive URL
# relative to the document root, so only absolute URLs satisfy both.
# Open demos/linux-distro.html (single-VM, dependency-free) to boot a staged distro.
#
# Run this in the Linux builder container or WSL, NOT Git Bash on Windows —
# Git Bash mangles the absolute POSIX paths it passes to the native python.exe.
#
# This is the local-dev counterpart to publish.sh (which uploads to a real host).
set -euo pipefail
name="${1:?usage: stage-web.sh <recipe-name> <jsLab-dir> [origin]}"
webdir="${2:?usage: stage-web.sh <recipe-name> <jsLab-dir> [origin]}"
# The browser resolves the kernel URL relative to the .cfg's dir but the drive
# URL relative to the document root, so only FULLY-ABSOLUTE URLs satisfy both
# (a relative/root-relative base boots the kernel but not the drive, or vice
# versa). Bake absolute URLs against the local serving origin — match this to how
# you serve jsLab (default http://localhost:8000; `npm run serve` there).
origin="${3:-http://localhost:8000}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
out="$root/build/$name"
recipe_dir="$root/recipes/$name"
[ -d "$out" ] || { echo "not built: $out (run build.sh $name first)"; exit 1; }
[ -d "$webdir" ] || { echo "no such web dir: $webdir"; exit 1; }

dst="$webdir/_distro/$name"
mkdir -p "$dst"
echo "== staging $name -> $dst"
cp -f "$out/kernel.bin" "$out/blk.txt" "$dst/"
[ ! -f "$out/bios.bin" ] || cp -f "$out/bios.bin" "$dst/"   # RISC-V firmware
cp -f "$out"/blk*.bin* "$dst/"   # raw .bin or gzip .bin.gz chunks
python3 "$here/mkconfig.py" "$recipe_dir" --asset-base "$origin/_distro/$name" -o "$dst/config.cfg"
# NOTE: eth0 is kept. The browser WASM build ignores the eth0 "driver" field and
# bridges the NIC to JS (jsemu.c create_vm), so eth0:{driver:"user"} works in the
# browser (guest NIC ⇄ VirtualNetwork) AND natively (temu-soft SLIRP). The guest
# still has to bring the interface up (udhcpc) to actually use it.

manifest="$webdir/_distro/manifest.json"
python3 - "$manifest" "$name" "$recipe_dir/recipe.yml" <<'PY'
import json, sys, os, yaml
manifest, name, recipe = sys.argv[1:4]
data = {}
if os.path.exists(manifest):
    try:
        data = json.load(open(manifest))
    except Exception:
        data = {}
entries = {e["name"]: e for e in data.get("distros", [])}
r = yaml.safe_load(open(recipe))
entries[name] = {
    "name": name,
    "description": r.get("description", name),
    "arch": r.get("arch", "?"),
    "config": "_distro/%s/config.cfg" % name,
}
data["distros"] = sorted(entries.values(), key=lambda e: e["name"])
json.dump(data, open(manifest, "w"), indent=2)
print("manifest updated:", manifest, "->", sorted(entries))
PY
echo "== done. Serve $webdir over HTTP and open demos/demo.html — '$name' is in the dropdown."
