#!/usr/bin/env python3
"""Split a raw disk image into fixed-size chunks for TinyEMU's block_net.c
HTTP block device (the `drive0` path).

block_net.c expects chunk files plus a `blk.txt` manifest:

    { "block_size": <KB>, "n_block": <count> }                      raw chunks
    { "block_size": <KB>, "n_block": <count>, "compression": "gzip" }

Raw chunks are `blk%09u.bin`, each `block_size * 1024` bytes. With
`--compress gzip` they are `blk%09u.bin.gz` instead, each the gzip of such a
chunk; the engine inflates them after download, which needs a TinyEMU build
from 2026-11 or later. An all-zero chunk, most of an ext2 image's free space,
gzips to a few hundred bytes. The gzip header carries no name or time, so a
rebuild of the same image gives the same files.

`block_size` is given in KB, matching the guest config field of the same name
(block_net.c multiplies it by 2 to get 512-byte sectors). The final chunk is
zero-padded to a full block so every chunk is exactly `block_size * 1024` bytes
once inflated — block_net.c asserts on the size, so short trailing chunks must
not be emitted.
"""
import argparse
import gzip
import json
import os


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image", help="raw disk image to split (e.g. rootfs.ext2)")
    ap.add_argument("-b", "--block-size", type=int, default=256,
                    help="chunk size in KB (default 256); must match recipe disk.block_size_kb")
    ap.add_argument("-c", "--compress", choices=["none", "gzip"], default="none",
                    help="chunk compression (default none)")
    ap.add_argument("-o", "--out-dir", default=".",
                    help="output dir for the chunks + blk.txt (default: cwd)")
    args = ap.parse_args()

    if args.block_size <= 0 or args.block_size & (args.block_size - 1):
        ap.error("block-size must be a power of two number of KB")

    os.makedirs(args.out_dir, exist_ok=True)
    chunk_bytes = args.block_size * 1024
    gz = args.compress == "gzip"

    n = 0
    stored = 0
    with open(args.image, "rb") as fin:
        while True:
            data = fin.read(chunk_bytes)
            if not data:
                break
            if len(data) < chunk_bytes:            # zero-pad the final chunk
                data += b"\x00" * (chunk_bytes - len(data))
            name = "blk%09u.bin" % n
            if gz:
                name += ".gz"
                data = gzip.compress(data, compresslevel=9, mtime=0)
            with open(os.path.join(args.out_dir, name), "wb") as fout:
                fout.write(data)
            stored += len(data)
            n += 1

    manifest = {"block_size": args.block_size, "n_block": n}
    if gz:
        manifest["compression"] = "gzip"
    with open(os.path.join(args.out_dir, "blk.txt"), "w") as fout:
        json.dump(manifest, fout, indent=4)

    print("Split %r into %d %s chunk(s) of %d KB (%.1f MB stored) -> %s" %
          (args.image, n, args.compress if gz else "raw", args.block_size,
           stored / 1048576, args.out_dir))


if __name__ == "__main__":
    main()
