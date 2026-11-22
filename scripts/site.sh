#!/usr/bin/env bash
# site.sh <site-dir> <base-url> <name>.tar...
#
# Build a static site (e.g. GitHub Pages) that hosts each image ready to boot:
#
#   <site-dir>/<name>/        the extracted <name>.tar: kernel.bin, blk.txt, the
#                             chunks, bios.bin (RISC-V), and config.cfg with
#                             ${ASSET_BASE} set to <base-url>/<name>
#   <site-dir>/manifest.json  { "distros": [ {name, description, arch, config, url} ] }
#                             (the format stage-web.sh writes for jsLab)
#   <site-dir>/index.html     a list of the images
#
# <base-url> must be the site's absolute URL (e.g. https://<owner>.github.io/<repo>):
# the browser resolves the kernel and drive URLs against different bases, so the
# .cfg only works with absolute URLs. Descriptions/arch come from recipes/<name>/
# recipe.yml when it exists. The raw rootfs.img.gz files are NOT put on the site
# (the site hosts the chunked form); they stay on the release.
set -euo pipefail
usage() { echo "usage: site.sh <site-dir> <base-url> <name>.tar..." >&2; exit 1; }
[ $# -ge 3 ] || usage
site="$1"; base="${2%/}"; shift 2
case "$base" in http://*|https://*) ;; *) echo "base-url must be absolute: $base" >&2; exit 1 ;; esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
mkdir -p "$site"

entries="$(mktemp)"; trap 'rm -f "$entries"' EXIT
for tar in "$@"; do
  [ -f "$tar" ] || { echo "no such file: $tar" >&2; exit 1; }
  name="$(basename "$tar" .tar)"
  dst="$site/$name"
  echo "== $name -> $dst"
  rm -rf "$dst"; mkdir -p "$dst"
  tar -xf "$tar" -C "$dst"
  [ -f "$dst/config.cfg" ] || { echo "$tar has no config.cfg" >&2; exit 1; }
  sed -i "s#\${ASSET_BASE}#$base/$name#g" "$dst/config.cfg"

  desc="$name"; arch="?"
  if [ -f "$root/recipes/$name/recipe.yml" ]; then
    desc="$(python3 "$here/recipe.py" "$root/recipes/$name/recipe.yml" description 2>/dev/null || echo "$name")"
    arch="$(python3 "$here/recipe.py" "$root/recipes/$name/recipe.yml" arch 2>/dev/null || echo "?")"
  fi
  size="$(du -sh "$dst" | cut -f1)"
  printf '%s\t%s\t%s\t%s\n' "$name" "$desc" "$arch" "$size" >> "$entries"
done

python3 - "$site" "$base" "$entries" <<'PY'
import html, json, os, sys
site, base, entries = sys.argv[1:4]
rows = [l.rstrip("\n").split("\t") for l in open(entries, encoding="utf-8") if l.strip()]
distros = [{"name": n, "description": d, "arch": a,
            "config": "%s/config.cfg" % n, "url": "%s/%s/config.cfg" % (base, n)}
           for n, d, a, _ in rows]
distros.sort(key=lambda e: e["name"])
with open(os.path.join(site, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump({"distros": distros}, f, indent=2)

size = {n: s for n, _, _, s in rows}
items = "\n".join(
    '<tr><td><a href="%s/config.cfg">%s</a></td><td>%s</td><td>%s</td><td>%s</td></tr>'
    % (html.escape(e["name"]), html.escape(e["name"]), html.escape(e["arch"]),
       html.escape(e["description"]), html.escape(size[e["name"]]))
    for e in distros)
with open(os.path.join(site, "index.html"), "w", encoding="utf-8") as f:
    f.write("""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TinyEMU distro images</title>
<style>
 body{font:15px/1.5 system-ui,sans-serif;max-width:60rem;margin:2rem auto;padding:0 1rem}
 table{border-collapse:collapse;width:100%%} td,th{text-align:left;padding:.4rem .6rem;border-bottom:1px solid #8884}
 code{font-size:.9em}
</style></head><body>
<h1>TinyEMU distro images</h1>
<p>Each image's <code>config.cfg</code> boots it in TinyEMU (browser or native) straight from here,
with the disk streamed in chunks. Machine-readable list: <a href="manifest.json">manifest.json</a>.</p>
<table><thead><tr><th>Image (config)</th><th>Arch</th><th>Description</th><th>Size</th></tr></thead>
<tbody>
%s
</tbody></table>
</body></html>
""" % items)
print("site:", site, "->", [e["name"] for e in distros])
PY

total="$(du -sm "$site" | cut -f1)"
echo "== site size: ${total} MB"
if [ "$total" -gt 1000 ]; then echo "!! over GitHub Pages' 1 GB site limit" >&2; exit 1; fi
