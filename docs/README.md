# TinyEMU guest-image build guides

This guide provide information on how to build, customize, host, and boot the guest **kernel + rootfs** images that
run inside TinyEMU.

## Read in this order

| #  | Guide | What it covers |
|----|-------|----------------|
| 1  | [pipeline.md](pipeline.md) | The build **process** end to end. Start here. |
| 2  | [recipe-reference.md](recipe-reference.md) | The `recipe.yml` schema and `config.cfg.tmpl` templating. |
| 3a | [flavour-alpine.md](flavour-alpine.md) | **Alpine** flavour: build, add packages, overlay files, first-boot. |
| 3b | [flavour-debian.md](flavour-debian.md) | **Debian** flavour: the pinned rootfs, packages, init. |
| 3c | [flavour-buildroot.md](flavour-buildroot.md) | **Buildroot** flavour: custom rootfs + branding + custom kernel. |
| 4  | [kernels.md](kernels.md) | Kernel options: prebuilt refs and generating your own. |
| 4b | [riscv.md](riscv.md) | **RISC-V** guests: OpenSBI firmware, the cross-compiled kernel, QEMU for packages. |
| 5  | [hosting-and-boot.md](hosting-and-boot.md) | Package, publish, and host a build. |
| 6  | [troubleshooting.md](troubleshooting.md) | The gotchas and how to fix them. |

## The pipeline at a glance

```
recipes/<name>/recipe.yml    (editable image recipe)
        │
        ▼   scripts/build.sh <name>   (in the Docker builder)
   ┌────────────────────────────────────────────────────────────┐
   │ backend (alpine|debian|buildroot)                           │
   │   fetch/unpack rootfs → packages → overlay/ → setup.sh      │
   │   → mke2fs -d rootfs                                        │
   │   fetch/build kernel → kernel.bin                           │
   ├────────────────────────────────────────────────────────────┤
   │ chunk.py     rootfs.ext2 → blk%09u.bin[.gz] + blk.txt       │
   │ mkconfig.py  config.cfg.tmpl → config.cfg (${ASSET_BASE})   │
   └────────────────────────────────────────────────────────────┘
        │
        ▼   build/<name>/   (the whole deliverable)
   kernel.bin · rootfs.ext2 · blk.txt · blk*.bin[.gz] · config.cfg
        │
        ├── publish.sh    → release artifact (host anywhere)
        └── stage-web.sh  → jsLab's _distro/ for local browser testing
```

Every stage is implemented as one script under [`../scripts/`](../scripts).
The recipe is the only thing that you may need to edit.

## Quickstart

While at the repo root:
```bash
# (run-once) Prepare the builder docker image
docker compose build builder
# Pick your flavour
export RECIPE=alpine-3.20-x86
# Build your image
docker compose run --rm build
# Check the image available under build/alpine-3.20-x86/
```

Then boot or host it (see [hosting-and-boot.md](hosting-and-boot.md) for more info).

## Status

- **Two variants per distro** — `<name>` boots the distro's init (OpenRC / sysvinit)
  with networking and basic utilities; `<name>-lite` boots a bare root shell
  (`init=/bin/sh`). See [recipe-reference.md](recipe-reference.md#recipeyml).
- **Alpine x86** — done & verified (native `drive0` + browser chunked HTTP).
- **Debian 12 x86** — done (the official `i386/debian:bookworm-slim` layer).
- **Buildroot** — not implemented; the backend is a stub, the process is
  documented in [flavour-buildroot.md](flavour-buildroot.md).
- **RISC-V** — riscv64 Alpine 3.20 and Debian 13 build and boot ([riscv.md](riscv.md)); riscv32 has no recipe.
