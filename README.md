# TinyEMU-distros

Automated **guest images** (kernel + rootfs) for TinyEMU.
Build bootable images for multiple distros from small, committed **recipes**.

See **[docs/](docs/README.md)** for the step-by-step build guides (pipeline, recipe reference, per-flavour how-tos, kernels, hosting & boot, troubleshooting).

To grab a TinyEMU build, visit my [TinyEMU](https://github.com/gramthanos/TinyEMU) fork, or check out Bellard's original [TinyEMU](https://bellard.org//tinyemu/) project.


## Layout

```
.
├── README.md                  this file
├── future-work.md             ideas and features still to explore
├── Dockerfile                 the build container (e2fsprogs, kernel toolchains, clang, qemu-user)
├── docker-compose.yml         builder / build / publish services
├── recipes/<name>/            COMMITTED, declarative
│   ├── recipe.yml             backend, arch, rootfs source, kernel, disk, vm
│   ├── config.cfg.tmpl        templated TinyEMU .cfg ($ASSET_BASE + recipe vals)
│   └── overlay/               files copied into the rootfs (init, motd, users, ...)
├── scripts/
│   ├── build.sh <name>        dispatcher: recipe -> backend -> kernel -> firmware -> chunk -> .cfg
│   ├── backends/
│   │   ├── alpine.sh          minirootfs tarball -> mke2fs -d -> apk -> overlay
│   │   ├── debian.sh          pinned rootfs (Docker Hub layer or tarball) -> apt -> mke2fs -d -> overlay
│   │   └── buildroot.sh       from source, custom/branded, custom kernel           (stub)
│   ├── kernel.sh              kernel.bin: prebuilt, or built from kernel.org (x86, riscv)
│   ├── firmware.sh            bios.bin for RISC-V: OpenSBI fw_jump, built from source
│   ├── binfmt.sh              lets the builder run riscv64 binaries (QEMU user mode)
│   ├── chunk.py               split rootfs.ext2 -> blk*.bin[.gz] + blk.txt (block_net.c)
│   ├── mkconfig.py            render config.cfg.tmpl -> concrete .cfg
│   ├── recipe.py              read one dotted key from recipe.yml (shell helper)
│   ├── publish.sh <name>      package + upload build/<name> as a release artifact
│   └── stage-web.sh <name>    stage a build into a jsLab checkout for browser testing
├── docs/                      step-by-step build guides
├── kernels/prebuilt/          reference kernels for kernel.source: prebuilt
└── build/<name>/             (git-ignored) output: kernel.bin, bios.bin (RISC-V),
                               rootfs.ext2, blk*.bin[.gz], blk.txt, config.cfg
```

## Disk mechanism (default)

New distros use **chunked virtio-block (`drive0`)**: `chunk.py` splits `rootfs.ext2` into 512 KB chunks, gzipped as `blk%09u.bin.gz` (`disk.compression: gzip`; raw `blk%09u.bin` with `none`), plus a `blk.txt` manifest, which `block_net.c`'s HTTP block device streams on demand. Self-hostable static files, no 9p server, no HTTP range requests. (`disk.mode: 9p` selects the older `fs0` network-filesystem path instead.)

## Usage

```bash
# (run-once) Prepare the builder docker image
docker compose build builder
# Pick your flavour
export RECIPE=alpine-3.20-x86
# Build your image
docker compose run --rm build
# Check the image available under build/alpine-3.20-x86/
```

The `build/<dist>/` is the whole deliverable, a self-contained, hostable directory:

```
build/alpine-3.20-x86/
├── kernel.bin            the guest kernel
├── rootfs.ext2           the full disk image (source of the chunks; keep for
│                         native `drive0` use, or delete if you only host chunks)
├── blk.txt               chunk manifest { block_size, n_block }
├── blk000000000.bin …    the rootfs split into fixed-size chunks (virtio-block/HTTP)
└── config.cfg            TinyEMU config with a literal ${ASSET_BASE} placeholder
```

### Hosting it (you choose where)

Upload the directory to any static host, then point `${ASSET_BASE}` in `config.cfg` at its base URL. The browser needs **absolute** URLs (it resolves the kernel relative to the .cfg dir but the drive relative to the document root), so `${ASSET_BASE}` must be a full absolute URL, e.g.:

```bash
sed -i 's#${ASSET_BASE}#https://cdn.example.com/tinyemu/alpine-3.20-x86#g' \
    build/alpine-3.20-x86/config.cfg
# upload build/alpine-3.20-x86/* to that URL; open config.cfg in TinyEMU (web or native).
```

Helpers: `scripts/publish.sh <dist>` packages + uploads to a GitHub Release; `scripts/stage-web.sh <dist> <jsLab-dir> [origin]` copies a build into a [jsLab](https://github.com/gramthanos/jsLab) checkout for local testing (writes `_distro/manifest.json`; open `demos/linux-distro.html`).

## Status

- **Alpine x86 — done & verified.** `build.sh alpine-3.20-x86` produces a clean `build/alpine-3.20-x86/`; boots to a root shell natively (`temu-soft`, raw `drive0`) and in-browser (chunked HTTP, jsLab's `demos/linux-distro.html` and the multi-VM `demos/demo.html`, inline + worker).
- **Kernel from source.** `kernel.source: build` compiles a vanilla Linux kernel (default 6.12 LTS; 5.15 also verified) with a TinyEMU config fragment — no dependence on a prebuilt binary. `prebuilt` (fetch a URL) still works. See [docs/kernels.md](docs/kernels.md).
- **Debian 12 x86** — `recipes/debian-12-x86/`: the official `i386/debian:bookworm-slim` layer, pinned by digest, plus python3, nano, procps and less; boots to a root shell on `hvc0`.
- **RISC-V (riscv64)** — `recipes/alpine-3.20-riscv64/` and `recipes/debian-13-riscv64/`: the same kernel cross-compiled, OpenSBI as firmware (`bios.bin`), packages installed under QEMU user mode. Needs a TinyEMU build with the riscv fixes of 2026-11. See [docs/riscv.md](docs/riscv.md).
- **Later:** buildroot backend, riscv32, integrity hashes. See [future-work.md](future-work.md).

## Licence

The recipes and scripts in this repository are MIT, see [LICENSE](LICENSE). The images they build are not: each contains a Linux kernel (GPL-2.0) and a distro whose packages carry their own licences, and the RISC-V firmware is OpenSBI (BSD-2-Clause). Publish an image together with its recipe, which records where each part comes from.
