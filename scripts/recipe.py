#!/usr/bin/env python3
"""Read one dotted key out of a recipe.yml (e.g. `disk.block_size_kb`).

Small helper so the shell backends can pull fields without embedding a YAML
parser in bash. Lists are printed space-separated; None prints empty.
"""
import sys

try:
    import yaml
except ImportError:
    sys.exit("recipe.py needs PyYAML (pip install pyyaml)")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: recipe.py <recipe.yml> <dotted.key>")
    with open(sys.argv[1]) as f:
        cur = yaml.safe_load(f)
    for part in sys.argv[2].split("."):
        if not isinstance(cur, dict) or part not in cur:
            sys.exit("key not found: %s" % sys.argv[2])
        cur = cur[part]
    if isinstance(cur, (list, tuple)):
        print(" ".join(map(str, cur)))
    else:
        print("" if cur is None else cur)


if __name__ == "__main__":
    main()
