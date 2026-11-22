#!/usr/bin/env python3
"""Render a recipe's config.cfg.tmpl into a concrete TinyEMU .cfg.

The template uses `$name`-style placeholders (string.Template). Recipe fields
are flattened with `_` (so `vm: { memory_mb: 128 }` becomes `$vm_memory_mb`),
and `$ASSET_BASE` is where the kernel + blk chunk files are hosted.

Host-agnostic: pass `--asset-base` to point at wherever the release artifacts
live. The default leaves the literal `${ASSET_BASE}` in place so the emitted
.cfg can be finalized later (e.g. by publish.sh).
"""
import argparse
import os
import sys
from string import Template

try:
    import yaml
except ImportError:
    sys.exit("mkconfig.py needs PyYAML (pip install pyyaml)")


def flatten(d, prefix=""):
    out = {}
    for k, v in d.items():
        key = prefix + str(k)
        if isinstance(v, dict):
            out.update(flatten(v, key + "_"))
        elif isinstance(v, (list, tuple)):
            out[key] = ",".join(map(str, v))
        else:
            out[key] = "" if v is None else str(v)
    return out


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("recipe_dir", help="path to a recipes/<name>/ dir")
    ap.add_argument("--asset-base", default="${ASSET_BASE}",
                    help="base URL/path for kernel + blk files "
                         "(default: leave the literal ${ASSET_BASE})")
    ap.add_argument("-o", "--out", default="-", help="output .cfg (default: stdout)")
    args = ap.parse_args()

    with open(os.path.join(args.recipe_dir, "recipe.yml")) as f:
        recipe = yaml.safe_load(f)
    with open(os.path.join(args.recipe_dir, "config.cfg.tmpl")) as f:
        tmpl = Template(f.read())

    vals = flatten(recipe)
    vals["ASSET_BASE"] = args.asset_base

    rendered = tmpl.safe_substitute(vals)
    if args.out == "-":
        sys.stdout.write(rendered)
    else:
        with open(args.out, "w") as f:
            f.write(rendered)
        print("wrote %s" % args.out, file=sys.stderr)


if __name__ == "__main__":
    main()
