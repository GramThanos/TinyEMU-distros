# RISC-V guests

**Status: builds and boots.** Four recipes, all 64-bit:

| Recipe | System | Disk |
|--------|--------|------|
| [`alpine-3.20-riscv64`](../recipes/alpine-3.20-riscv64) | Alpine 3.20 with OpenRC + python3, nano, less, curl, htop | 192 MB |
| [`alpine-3.20-riscv64-lite`](../recipes/alpine-3.20-riscv64-lite) | Alpine 3.20, no init + python3, nano | 128 MB |
| [`debian-13-riscv64`](../recipes/debian-13-riscv64) | Debian 13 trixie with sysvinit + python3, nano, procps, htop, less, curl, e2fsprogs | 384 MB |
| [`debian-13-riscv64-lite`](../recipes/debian-13-riscv64-lite) | Debian 13 trixie slim, no init + python3, nano, procps, less | 256 MB |

Debian is 13, not 12 as on x86: riscv64 became an official Debian architecture with
trixie. The `-lite` images boot straight to a root shell on `hvc0` (`init=/bin/sh`);
the others boot their init system and log root in on `hvc0`, as the x86 images do
(see the [Alpine](flavour-alpine.md) and [Debian](flavour-debian.md) guides). All run in
TinyEMU's `riscv64` machine, natively (`temu`) or in the browser engine. In the
browser, Alpine riscv64 lite reaches its shell in about 5 s, against about a minute
for Alpine x86 lite.

```bash
RECIPE=alpine-3.20-riscv64 docker compose run --rm build   # -> build/alpine-3.20-riscv64/
RECIPE=debian-13-riscv64-lite docker compose run --rm build
```

## What a RISC-V build adds

A RISC-V build directory has one more file than an x86 one, `bios.bin`, and its
`config.cfg` names it:

```js
machine: "riscv64",
bios: "${ASSET_BASE}/bios.bin",
kernel: "${ASSET_BASE}/kernel.bin",
```

| Piece | Made by | What it is |
|-------|---------|------------|
| `bios.bin` | [`scripts/firmware.sh`](../scripts/firmware.sh) | OpenSBI's generic `fw_jump` (BSD-2-Clause), built from source. M-mode firmware: it gives the kernel the SBI calls (timer, console, reset) and emulates what the CPU lacks, such as the `time` CSR. |
| `kernel.bin` | [`scripts/kernel.sh`](../scripts/kernel.sh) | A raw `Image`, not a bzImage: kernel.org 6.12 LTS, `defconfig` + [`tinyemu-riscv.fragment`](../kernels/config/tinyemu-riscv.fragment). |
| rootfs | the alpine / debian backend | As for x86, but its packages are installed by running the guest's `apk` / `apt-get` under QEMU user mode. |

The recipe gains a `firmware:` section, and `arch` / `vm.machine` say `riscv64`:

```yaml
arch: riscv64
firmware:
  opensbi: "1.6"            # OpenSBI version, built from its GitHub tag
  sha256: d1170210...       # optional: the source tarball's sha256
vm:
  machine: riscv64
  memory_mb: 128
```

## How it boots

TinyEMU puts `bios.bin` at the start of RAM (0x80000000) and the kernel 2 MB above
it (0x80200000), which is where `fw_jump` jumps, and passes a device tree it builds
itself. OpenSBI moves the device tree 34 MB into RAM (0x82200000) before starting
the kernel, so:

- **the kernel `Image` must stay under 32 MB** (the fragment's is 19 MB), and
- **`vm.memory_mb` must be well above 34**; 128 is the smallest the recipes use.

## The toolchain

- **clang/LLVM cross-compiles** the kernel (`make LLVM=1`) and OpenSBI. Debian's
  `gcc-riscv64-linux-gnu` can't be installed next to `gcc-multilib`, which the x86
  kernel build uses.
- **QEMU user mode runs the guest's package manager.** [`scripts/binfmt.sh`](../scripts/binfmt.sh)
  registers the builder's `qemu-riscv64-static` with binfmt_misc (the `F` flag, so
  it works inside the chroot without being copied there). binfmt_misc belongs to the
  Docker host's kernel, so the build service is **privileged**, and the
  registration lasts until the Docker VM restarts. Without it, the package step is
  skipped with a warning, as for any arch the builder can't run.

## The kernel fragment

[`kernels/config/tinyemu-riscv.fragment`](../kernels/config/tinyemu-riscv.fragment)
keeps what TinyEMU's machine has (virtio over MMIO, the PLIC, the SBI timer, ext2/4,
9p) and drops the rest: every SoC platform, PCI, DRM, USB and the like. Two settings
matter more than they look:

- `# CONFIG_HVC_RISCV_SBI is not set`: the SBI console would otherwise take `hvc0`,
  and the virtio console, where TinyEMU's input goes, would become `hvc1`.
- `# CONFIG_RISCV_ISA_V is not set` and the other ISA extensions: the CPU is
  `rv64imafdc` and nothing more.

## What the engine needed

TinyEMU's riscv machine was written for Bellard's 2018 kernel and his `bbl`
firmware. Booting OpenSBI 1.6 and Linux 6.12 took these engine fixes (in the
TinyEMU repository, `riscv_machine.c` / `riscv_cpu.c`), so **older TinyEMU builds
can't boot these images**:

- the device tree's `riscv,isa` is in canonical order (`rv64imafdc`), which Linux
  6.x requires to start with `rv64ima`;
- the HTIF node has a `reg`, without which OpenSBI's console spins forever;
- a `reserved-memory` node covers the firmware below the kernel: OpenSBI only adds
  one when the hart has PMP, and without it Linux hands out OpenSBI's own pages;
- `mvendorid` / `marchid` / `mimpid` read as 0, and `mcounteren.TM` sticks, so
  OpenSBI can emulate `rdtime`;
- the timer follows the engine's snapshot-aware clock, so a resumed browser VM
  keeps time.

The machine has no RTC, so a guest starts in 1970 until something sets the clock
(the TinyEMU agent page does). riscv32 is wired in `kernel.sh` and `firmware.sh`
(`rv32_defconfig`, a 32-bit `fw_jump`) but untested and without a recipe: neither
Alpine nor Debian ships a 32-bit RISC-V port, so it would need a Buildroot userland.
