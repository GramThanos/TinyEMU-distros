# Future work

Ideas and features still to explore. What already exists is described in [README.md](README.md) and [docs/](docs/README.md).

## Buildroot backend

`scripts/backends/buildroot.sh` is a stub. It would build a rootfs (and optionally the kernel) from source, for images that need their own package set, init, users or branding. Planned flow (detail in [docs/flavour-buildroot.md](docs/flavour-buildroot.md)):

- Clone Buildroot at a pinned version; apply the recipe's `buildroot.config` as `.config` (from `qemu_x86_defconfig`).
- Apply `overlay/` and a `post-build.sh` hook (branding, a demo user, init).
- Optionally build the kernel too (`kernel.source: buildroot`), with `linux.config` enabling virtio-console/blk, e1000 and 9p. Not needed just for a source-built kernel: `kernel.source: build` already does that.
- Copy `output/images/{rootfs.ext2, bzImage|vmlinux}` to the build directory, then let `build.sh` chunk it as usual.
- Add a sample custom recipe (users, branding) to exercise it.
- Cache the Buildroot download / ccache directory between runs.

## riscv32

`kernel.sh`, `firmware.sh` and `binfmt.sh` already handle `riscv32`, but there is no recipe. Options: an Alpine / Debian-style recipe if a riscv32 userland is available, or the Buildroot backend with a riscv32 defconfig (the old `buildroot-riscv32.config` is a starting point).

## Persistent disks

The chunked `drive0` block device is the base for a copy-on-write overlay in the browser runtime (`block_device_init_js`), so guest writes survive a reload. The work is on the runtime side; this repo would only need to keep the image format compatible.

## Skip unchanged builds

Hash the build inputs (recipe, overlay, kernel config fragment, scripts), store the hash in `build/<name>/`, and skip the build when it matches. `--force` rebuilds anyway.

## Integrity hashes

- **Chunks:** write a `blk.integrity.txt` with an integrity hash for every chunk.
- **Other files:** `config.cfg` optionally carries integrity hashes for the files it references (kernel, bios); the chunks are covered by `blk.integrity.txt`.
- **The config itself:** support an integrity hash for `config.cfg`, so a tampered image is detected. Needs support in TinyEMU / jsLab as well.

## Compression by default

Every recipe sets `disk.compression: gzip`, but the built-in default in `build.sh` / `chunk.py` is still `none`. Decide whether `gzip` should be the default.
