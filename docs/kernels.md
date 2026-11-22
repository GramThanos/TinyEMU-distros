# Kernels

The guest kernel is independent of the rootfs. Every recipe references a kernel
via `kernel.*`; the backend places it at `build/<name>/kernel.bin`, and the
rendered config loads it as `kernel: "$ASSET_BASE/kernel.bin"`.

## What TinyEMU's x86 core needs

The software x86 core is **32-bit protected mode only** (see the engine repo's
`issues.md`). It boots a Linux kernel image through TinyEMU's `linuxstart`
loader — not via a BIOS/real-mode path. So:

- Use a **32-bit x86 (i686) kernel image**. 64-bit kernels and BIOS/real-mode
  boot (FreeDOS, etc.) are out of scope.
- The kernel must have the drivers the guest actually uses (below), or it boots
  but can't find its console/root.

### Required / recommended kernel config

| Feature | Config | Why |
|---------|--------|-----|
| virtio console | `CONFIG_VIRTIO_CONSOLE` | gives you `hvc0` — the `console=hvc0` in every recipe |
| virtio block | `CONFIG_VIRTIO_BLK` (+ `CONFIG_VIRTIO`, `CONFIG_VIRTIO_PCI`/`_MMIO`) | mounts `drive0` as `/dev/vda` (`root=/dev/vda`) |
| ext2 | `CONFIG_EXT2_FS` (or ext4 for an ext4 image) | reads the rootfs |
| e1000 NIC | `CONFIG_E1000`, `CONFIG_E1000E` | optional networking (`eth0`) |
| 9p | `CONFIG_NET_9P`, `CONFIG_9P_FS` (+ virtio 9p transport) | only if using `disk.mode: 9p` (`fs0`) instead of chunked `drive0` |

A kernel missing virtio-blk can't mount `drive0`; one missing virtio-console
gives no `hvc0` (you'll see nothing on the console). The e1000 menuconfig steps
are in [flavour-buildroot.md](flavour-buildroot.md).

Kernel handling is centralized in [`scripts/kernel.sh`](../scripts/kernel.sh)
(called by `build.sh` after the rootfs backend), so all three modes below work
with any rootfs flavour. Select one with `kernel.source` in the recipe.

## Option 1 — prebuilt (fetch a URL)

Fetch a ready kernel image at build time — the quickest path:

```yaml
kernel:
  source: prebuilt
  url: https://bellard.org/jslinux/kernel-x86.bin
```

Bellard's jslinux kernel is small and has the virtio drivers. It's an older
kernel — fine for minimal userlands; when you want something current or a
guaranteed driver set, build one (Option 2).

### Local / pinned prebuilt kernels

Instead of a URL you can stage a kernel file under
[`kernels/prebuilt/`](../kernels/prebuilt) and point `kernel.url` at it. Per repo
policy, large binaries stay out of git — use that dir for a locally-staged
kernel, not for committing multi-MB blobs.
See [`kernels/prebuilt/README.md`](../kernels/prebuilt/README.md).

## Option 2 — build a kernel from source (default for Alpine)

Compile a **vanilla Linux kernel** from kernel.org for the guest arch. This is how
you get a modern kernel and a guaranteed driver set without depending on any
prebuilt binary:

```yaml
kernel:
  source: build
  version: "6.12.109"      # a v6.x LTS release; downloaded from kernel.org
  # url: https://…         # optional: override the source tarball location
```

What `scripts/kernel.sh` does:

1. Download `linux-<version>.tar.xz` from kernel.org (or `kernel.url`) and unpack.
2. `make ARCH=i386 i386_defconfig`, then merge
   [`kernels/config/tinyemu-x86.fragment`](../kernels/config/tinyemu-x86.fragment)
   (virtio-console/blk/net, ext2/4, e1000, 9p; non-PAE) via the kernel tree's
   `merge_config.sh`, then `make olddefconfig`.
3. `make ARCH=i386 -j$(nproc) bzImage` → copy `arch/x86/boot/bzImage` to
   `kernel.bin`, then delete the ~1.5 GB source tree.

Requirements & notes:

- **Toolchain.** Needs a kernel build toolchain incl. 32-bit support
  (`build-essential`, `gcc-multilib`, `bc`, `bison`, `flex`, `libelf-dev`,
  `libssl-dev`). The repo's [`Dockerfile`](../Dockerfile) already installs these —
  run the build in the container.
- **Pin the version** for reproducibility. Default is a **6.12 LTS**, verified
  booting on the engine; 5.15 also boots if you want an older LTS. Non-PAE keeps
  the software CPU's job simple.
- **Time.** A first compile takes a few minutes.
- **Change the driver set** by editing the fragment (e.g. add a filesystem or a
  NIC); `olddefconfig` folds it in.

> **Modern kernels need a recent engine.** A modern i686 kernel exercises paths
> older kernels don't — it needs an engine **at or after** the `verr`/`verw` and
> PAE A/D-bit fixes (5.15 first surfaced this: it issues `verw` for its MDS
> store-buffer flush). Those fixes are in the engine repo's `x86_cpu.c`; a pre-fix
> engine wedges on boot. Both 5.15 and 6.12 LTS are verified booting on the
> current engine.

## Option 3 — Buildroot (kernel + rootfs from source)

The Buildroot flavour builds the kernel *and* a custom rootfs from source in one
pass (`kernel.source: buildroot`, plus a `linux.config`). Heavier; use it when you
also want a source-built userland. Not implemented yet — see
[flavour-buildroot.md](flavour-buildroot.md).

## Choosing per distro

- **Alpine** → `source: build` (default) compiles a 6.12 LTS kernel; switch to
  `prebuilt` for a faster build.
- **Debian** → `build` for a current kernel with the drivers a fuller userland
  needs; `prebuilt` to unblock.
- **Custom userland** → Buildroot (kernel + rootfs from source).
- **RISC-V** → `source: build` with `arch: riscv64`: the same kernel.org release,
  cross-compiled with clang (`LLVM=1`) from `defconfig` +
  [`tinyemu-riscv.fragment`](../kernels/config/tinyemu-riscv.fragment), as a raw
  `Image`. It boots through OpenSBI; see [riscv.md](riscv.md).
