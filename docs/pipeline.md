# The build pipeline

This is the build **process** end to end... what happens between a `recipe.yml` and a hostable `build/<name>/` directory.
Everything here is driven by [`scripts/build.sh`](../scripts/build.sh); the per-distro specifics live in the [flavour guides](README.md).

## Prerequisites: the Docker builder

The pipeline builds ext2 images **without root or loop mounts** (via `mke2fs -d`), so it runs unprivileged inside a small Debian container defined by [`../Dockerfile`](../Dockerfile):

```dockerfile
FROM debian:bookworm-slim
RUN apt-get install -y e2fsprogs curl ca-certificates python3 python3-yaml tar xz-utils \
        build-essential gcc-multilib bc bison flex cpio perl libelf-dev libssl-dev
```

- `e2fsprogs` — `mke2fs -d` / `tune2fs`, the whole reason we don't need `sudo mount`.
- `python3` + `python3-yaml`, the `recipe.py` / `mkconfig.py` / `chunk.py` helpers.
- `curl`, to fetch the rootfs tarball, a prebuilt kernel, or the kernel source.
- `build-essential` + `gcc-multilib` + `bc`/`bison`/`flex`/`libelf-dev`/`libssl-dev`, needed compile a guest kernel from source (`kernel.source: build`), incl. 32-bit (i386) support. (note: these can be removed if there is no need for building kernels).

Build the image once, then run a recipe:
```bash
# (run-once) Prepare the builder docker image
docker compose build builder
# Pick your flavour
export RECIPE=alpine-3.20-x86
# Build your image
docker compose run --rm build
# Check the image available under build/alpine-3.20-x86/
```

Since the [`../docker-compose.yml`](../docker-compose.yml) mounts the repo at `/work`, so output lands back on the host in `build/<name>/`.

You can also run `scripts/build.sh <name>` directly on a Linux host or in WSL if you have `e2fsprogs` + `python3-yaml`.
Do **not** run the scripts from Git Bash on Windows as it mangles absolute POSIX paths passed to `python.exe` (see [troubleshooting.md](troubleshooting.md)).

## Stage by stage

`build.sh <name>` reads `recipes/<name>/recipe.yml`, then:

### 1. Dispatch to a backend

```bash
backend="$(yq backend)"          # alpine | debian | buildroot
case "$backend" in
  alpine)    backends/alpine.sh    "$recipe_dir" "$out" ;;
  debian)    backends/debian.sh    "$recipe_dir" "$out" ;;
  buildroot) backends/buildroot.sh "$recipe_dir" "$out" ;;
esac
```

Each backend produces the **rootfs** image in `build/<name>/`:

- `rootfs.ext2`, the full disk image

(The buildroot backend also emits `kernel.bin` in the same pass; the tarball backends leave the kernel to the next stage.)
How the rootfs is made differs per flavour (unpack a tarball vs. build from source), see the flavour guides.
The **common rootfs recipe** the tarball backends share is:

1. Fetch + unpack the rootfs tarball into a staging dir `rootfs.dir/`.
2. Apply the recipe's `overlay/` on top (`cp -a overlay/. rootfs.dir/`).
3. Optionally add packages (Alpine: a chroot'd `apk`).
4. `mke2fs -q -t ext2 -d rootfs.dir rootfs.ext2 <size_mb>M`, build ext2 straight from the directory, no mount.
5. `tune2fs -c0 -i0 rootfs.ext2`, disable the mount-count / time-based fsck so the guest never forces a check on boot.

### 2. Get the kernel

The [`kernel.sh`](../scripts/kernel.sh) produces `build/<name>/kernel.bin` per the recipe's `kernel.source`:

- `build`, compile a vanilla Linux kernel from kernel.org (`kernel.version`), merging [`kernels/config/tinyemu-x86.fragment`](../kernels/config/tinyemu-x86.fragment) onto `i386_defconfig` → `bzImage`. The default for the Alpine recipe. For `arch: riscv64` it cross-compiles `defconfig` + [`tinyemu-riscv.fragment`](../kernels/config/tinyemu-riscv.fragment) with clang into a raw `Image`, and [`firmware.sh`](../scripts/firmware.sh) then builds the OpenSBI firmware, `bios.bin` (see [riscv.md](riscv.md)).
- `prebuilt`, fetch `kernel.url` (e.g. Bellard's jslinux kernel).
- `buildroot`, already produced by the backend above.

More info available at [kernels.md](kernels.md).

### 3. Chunk the rootfs (block mode)

If `disk.mode: block` (the default), [`chunk.py`](../scripts/chunk.py) splits the image for the virtio-block / HTTP block device:

```bash
python3 chunk.py build/<name>/rootfs.ext2 -b <block_size_kb> -c <none|gzip> -o build/<name>/
```

It writes `blk%09u.bin` chunk files of exactly `block_size_kb * 1024` bytes each, plus a `blk.txt` manifest:

```json
{ "block_size": 256, "n_block": 240 }
```

With `disk.compression: gzip` (`-c gzip`, what the recipes use) each chunk is gzipped instead, as `blk%09u.bin.gz`, and the manifest says so:

```json
{ "block_size": 512, "n_block": 256, "compression": "gzip" }
```

The engine inflates each chunk after downloading it. A chunk that arrives already decoded (a server that sends the `.gz` with `Content-Encoding: gzip`) is used as it is. About 60% of an image's chunks are free space, all zeros, which gzip to a few hundred bytes, so the four disks shrink from about 770 MB to 118 MB. Gzip chunks need a TinyEMU build from 2026-11 or later (`block_net.c`, and `temu.c` for native boots); older builds only read raw ones, which `-c none` still writes.

Two rules the engine relies on (both handled by `chunk.py`):

- **`block_size` is in KB.** `block_net.c` multiplies it by 2 to get 512-byte sectors, so it must match the `-b` you pass (and the recipe's `disk.block_size_kb`) and must be a power of two.
- **The final chunk is zero-padded** to a full block. `block_net.c` asserts on the fetched size, so short trailing chunks would crash it. (The old `blk-split.py` only ever worked because its image divided evenly.)

If `disk.mode: 9p`, chunking is skipped and the image is served over 9p (`fs0`) instead; see [hosting-and-boot.md](hosting-and-boot.md).

### 4. Render the config

The [`mkconfig.py`](../scripts/mkconfig.py) turns the recipe's `config.cfg.tmpl` into a concrete TinyEMU `config.cfg`.
Recipe fields are flattened with `_` (`vm: { memory_mb: 128 }` → `$vm_memory_mb`) and substituted.
The `$ASSET_BASE` marks where the kernel + chunks will be hosted:

```bash
python3 mkconfig.py recipes/<name> --asset-base '${ASSET_BASE}' -o build/<name>/config.cfg
```

The default leaves the literal `${ASSET_BASE}` in place so the emitted `.cfg` can be finalized later (by `publish.sh`, `stage-web.sh`, or a manual `sed`).
See [recipe-reference.md](recipe-reference.md) for the template placeholders and [hosting-and-boot.md](hosting-and-boot.md) for how `${ASSET_BASE}` gets resolved.

### 5. Clean intermediates

The `build.sh` removes the staging tree and downloaded tarballs so `build/<name>/` holds **only hostable files**:

```
rm -rf build/<name>/rootfs.dir build/<name>/minirootfs.tar.gz build/<name>/rootfs.tar
```

## Output

```
build/<name>/             (git-ignored — published as an artifact instead)
├── kernel.bin            the guest kernel
├── bios.bin              RISC-V only: OpenSBI, which boots the kernel
├── rootfs.ext2           the full disk image (source of the chunks; keep it for native raw-`drive0` boots, or delete if you only host chunks)
├── blk.txt               chunk manifest { block_size, n_block }
├── blk000000000.bin      the rootfs split into fixed-size chunks
├── blk000000001.bin
│   ...
├── blk00000000N.bin
└── config.cfg            TinyEMU config, ${ASSET_BASE} still a placeholder
```

## Where to go next

- To learn about changing what's *in* the image, check [recipe-reference.md](recipe-reference.md) and the flavour guide for your distro.
- To learn about booting or shiping what you built, head to [hosting-and-boot.md](hosting-and-boot.md).
- If something broke, consult [troubleshooting.md](troubleshooting.md).
