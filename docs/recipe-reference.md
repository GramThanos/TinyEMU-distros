# Recipe reference

A **recipe** is the one thing you edit to define a distro image.
It's a directory under [`recipes/`](../recipes):

```
recipes/<name>/
├── recipe.yml         backend, arch, rootfs source, kernel, disk, vm (required)
├── config.cfg.tmpl    templated TinyEMU .cfg (required)
└── overlay/           files copied into the rootfs (optional)
```

`<name>` is the recipe id you pass to `build.sh` and the output dir name. Suggested convention: `<distro>-<version>-<arch>`, e.g. `alpine-3.20-x86`.

## `recipe.yml`

Read by [`recipe.py`](../scripts/recipe.py) (dotted keys, for the shell backends) and [`mkconfig.py`](../scripts/mkconfig.py) (flattened, for the template).

For example here is an Alpine recipe:

```yaml
name: alpine-3.20-x86
description: Alpine Linux 3.20 (i686), minimal rootfs on a virtio-block disk.
arch: x86 # x86 | riscv64 (| riscv32)
backend: alpine # alpine | debian | buildroot

rootfs:
  version: "3.20.3"
  mirror: https://dl-cdn.alpinelinux.org/alpine
  minirootfs: alpine-minirootfs-3.20.3-x86.tar.gz # under $mirror/v3.20/releases/$arch/
  size_mb: 128 # ext2 image size (mke2fs -d)
  packages: # added via chroot'd apk, else at first boot
    - python3
    - nano

kernel:
  source: build # build | prebuilt | buildroot
  version: "6.12.109" # for source: build — a kernel.org release
  # source: prebuilt / url: https://example.com/path/kernel-x86.bin

disk:
  mode: block # block (drive0 chunked) | 9p (fs0)
  block_size_kb: 512 # chunk size; must match chunk.py -b, power of two
  compression: gzip # gzip | none (raw chunks)

vm:
  machine: pc
  memory_mb: 128
  cmdline: "loglevel=1 console=hvc0 root=/dev/vda rw init=/bin/sh"
```

### Top-level keys

| Key | Required | Notes |
|-----|----------|-------|
| `name` | yes | Recipe id; keep it equal to the directory name. |
| `description` | yes | One line; shown in the web `manifest.json` dropdown. |
| `arch` | yes | `x86` or `riscv64` (`riscv32` is wired but has no recipe). For Alpine, `arch` also names the mirror's release dir. A RISC-V `arch` also needs `firmware:`. |
| `backend` | yes | Selects the build script: `alpine`, `debian`, or `buildroot`. |

### `rootfs.*`

Fields depend on the backend.

| Key | Backend | Notes |
|-----|---------|-------|
| `rootfs.version` | alpine | e.g. `3.20.3`; the mirror branch is derived as `v3.20`. |
| `rootfs.mirror` | alpine | Alpine mirror base URL. |
| `rootfs.minirootfs` | alpine | Tarball filename under `$mirror/v<major.minor>/releases/$arch/`. |
| `rootfs.image` + `rootfs.digest` | debian | A single-layer Docker Hub image and its layer's digest, e.g. `i386/debian` + `sha256:…`. The layer is fetched by digest (anonymous pull token) and checked against it. Preferred: pinned, and hosted by Docker Hub. |
| `rootfs.tarball_url` | debian | Otherwise: a **pinned** URL of a prebuilt rootfs tarball. |
| `rootfs.sha256` | debian | Optional, with `tarball_url`: the tarball's sha256, checked before use. |
| `rootfs.size_mb` | all | ext2 image size handed to `mke2fs -d`. Must exceed the unpacked tree + packages. |
| `rootfs.packages` | alpine, debian | List; installed via a chroot'd `apk` (alpine) or `apt-get` (debian) when the host can run the guest arch, else skipped with a warning (add at first boot). Uses the network, so it is the one step that isn't byte-for-byte reproducible. |

### `kernel.*`

Handled by [`scripts/kernel.sh`](../scripts/kernel.sh); see [kernels.md](kernels.md).

| Key | Notes |
|-----|-------|
| `kernel.source` | `build` (compile a vanilla kernel from source), `prebuilt` (fetch a URL), or `buildroot` (kernel built by the buildroot backend — not implemented yet). |
| `kernel.version` | Used when `source: build` — a kernel.org release, e.g. `6.12.109`. Downloaded from `v<major>.x/linux-<version>.tar.xz`. Pin it for reproducibility. |
| `kernel.url` | When `source: prebuilt`, the image to fetch (e.g. Bellard's `https://bellard.org/jslinux/kernel-x86.bin`). When `source: build`, an optional override for the source-tarball URL. |

### `firmware.*`

RISC-V only; handled by [`scripts/firmware.sh`](../scripts/firmware.sh), which
writes `bios.bin`. See [riscv.md](riscv.md).

| Key | Notes |
|-----|-------|
| `firmware.opensbi` | OpenSBI version, e.g. `"1.6"`. Its generic `fw_jump` is built from the GitHub tag's source. Required for a RISC-V `arch`. |
| `firmware.sha256` | Optional: the source tarball's sha256, checked before building. |

### `disk.*`

| Key | Notes |
|-----|-------|
| `disk.mode` | `block` (default — chunked `drive0`) or `9p` (the older `fs0` network filesystem; skips chunking). |
| `disk.block_size_kb` | Chunk size in KB; passed to `chunk.py -b`. Power of two. Larger = fewer HTTP requests, but each fetches more unused data, fills the engine's 128 MB chunk cache sooner, and makes browser snapshots bigger (downloaded chunks are in them). The recipes use 512: against 256 it cuts a boot's requests by about a third, for about 35% more data. |
| `disk.compression` | `gzip` (the recipes) or `none` (default). `gzip` writes `blk%09u.bin.gz` chunks and marks `blk.txt`; it needs a 2026-11+ TinyEMU. See [pipeline.md](pipeline.md). |

### `vm.*`

These flow into `config.cfg.tmpl` as `$vm_*`.

| Key | → template | Notes |
|-----|-----------|-------|
| `vm.machine` | `$vm_machine` | `pc` for x86, `riscv64` for riscv64. |
| `vm.memory_mb` | `$vm_memory_mb` | Guest RAM in MB. |
| `vm.cmdline` | `$vm_cmdline` | Kernel command line. See below. |

**About `cmdline`.** A bare Alpine *minirootfs* has no init/getty configured, so the seed recipe boots straight to a shell with `init=/bin/sh`:

```
loglevel=1 console=hvc0 root=/dev/vda rw init=/bin/sh
```

- `console=hvc0` — TinyEMU's virtio console.
- `root=/dev/vda` — the virtio-block disk (`drive0`).
- Drop `init=/bin/sh` once the rootfs has a real init (OpenRC, systemV, systemd) so the distro boots normally.

## `config.cfg.tmpl`

A `string.Template` (`$name` placeholders) that `mkconfig.py` renders. The seed template:

```jsonc
/* $name — GENERATED from recipe.yml by scripts/mkconfig.py.
 * Do not edit by hand; edit the recipe instead. */
{
    version: 1,
    machine: "$vm_machine",
    memory_size: $vm_memory_mb,
    kernel: "$ASSET_BASE/kernel.bin",
    cmdline: "$vm_cmdline",
    drive0: { file: "$ASSET_BASE/blk.txt" },
    eth0: { driver: "user" },
}
```

Placeholders available:

- `$ASSET_BASE` — base URL/path for `kernel.bin` + `blk.txt` + chunks. Filled at render time (`--asset-base`), or left literal for later. See [hosting-and-boot.md](hosting-and-boot.md).
- Any flattened recipe field: nested keys join with `_` (`vm.memory_mb` → `$vm_memory_mb`), and lists become comma-joined strings.

Notes:

- `drive0: { file: "$ASSET_BASE/blk.txt" }` points at the **manifest**; the engine reads it and pulls `blk*.bin` from the same directory. For a raw (non-chunked) boot, point `drive0.file` at `rootfs.ext2` instead.
- `eth0: { driver: "user" }` is safe to keep in both targets: native uses SLIRP; the browser ignores the `driver` field and bridges the NIC to the JS `VirtualNetwork`. The guest still has to bring the interface up (`udhcpc`).

## Adding a new recipe

1. `cp -r recipes/alpine-3.20-x86 recipes/<new-name>` and edit `recipe.yml`.
2. Adjust `overlay/` (see the flavour guide for what to put there).
3. `RECIPE=<new-name> docker compose run --rm build`.
4. Boot-test it — [hosting-and-boot.md](hosting-and-boot.md).

Pick the flavour guide that matches your `backend`:
[Alpine](flavour-alpine.md) · [Debian](flavour-debian.md) ·
[Buildroot](flavour-buildroot.md).
