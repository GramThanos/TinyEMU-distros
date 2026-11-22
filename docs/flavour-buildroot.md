# Flavour: Buildroot (from source)

**Status: not implemented — the backend is a stub** (see [`../future-work.md`](../future-work.md)).
[`scripts/backends/buildroot.sh`](../scripts/backends/buildroot.sh) exits with a
pointer to this guide. This document is the *process* to implement it, plus the
customization mechanics (custom init, users, branding) generalized from an
earlier hand-built Buildroot image.

Use this flavour when a prebuilt tarball won't do — you want a **fully custom
rootfs built from source**, your own package set, custom init/branding, or a
**custom kernel** with exactly the drivers TinyEMU needs.

## When to use Buildroot vs a tarball

| Want… | Use |
|-------|-----|
| A quick, known-good userland | [Alpine](flavour-alpine.md) / [Debian](flavour-debian.md) tarball |
| Custom packages, init, branding, seeded files | **Buildroot** |
| A custom kernel (stop depending on prebuilt) | `kernel.source: build` (no Buildroot needed, see [kernels.md](kernels.md)); or **Buildroot** (`kernel.source: buildroot`) |
| RISC-V (riscv64) | [Alpine](flavour-alpine.md) / [Debian](flavour-debian.md), see [riscv.md](riscv.md) |

## The intended backend flow

`buildroot.sh <recipe_dir> <out>` should port the old harness flow and emit the
same two files every backend produces (`rootfs.ext2`, `kernel.bin`):

1. **Clone/cache Buildroot** at a pinned version (reproducibility).
2. **Configure**: copy the recipe's `buildroot.config` to `.config`
   (`make defconfig` from a stored config, not interactive menuconfig at build
   time).
3. **Overlay**: point Buildroot's rootfs overlay + post-build script at the
   recipe's `overlay/` (init tweaks, users, branding, seeded files).
4. **Kernel** (if `kernel.source: buildroot`): apply the recipe's `linux.config`
   with the drivers below.
5. `make -jN` → `output/images/{rootfs.ext2, bzImage|vmlinux}`.
6. Copy `output/images/rootfs.ext2` → `<out>/rootfs.ext2` and the kernel →
   `<out>/kernel.bin`. `build.sh` then chunks + renders the config as usual.

Recipe additions this backend expects (beyond the [common schema](recipe-reference.md)):

```yaml
backend: buildroot
kernel:
  source: buildroot          # build the kernel too (vs. prebuilt)
# plus these files in recipes/<name>/:
#   buildroot.config         Buildroot .config (from `make savedefconfig` ideally)
#   linux.config             kernel .config (if building the kernel)
#   overlay/                 post-build.sh + init scripts + branding + seeded files
```

## Base Buildroot configuration

Start from the QEMU x86 defconfig, then adjust:

```bash
git clone https://github.com/buildroot/buildroot.git
cd buildroot
make qemu_x86_defconfig
make menuconfig
```

Typical settings to review (`menuconfig`):

```
Toolchain            > Enable WCHAR support
System configuration > System hostname            → <your-hostname>
System configuration > System banner              → <your login banner>
System configuration > Init system                → systemV (or busybox / systemd)
System configuration > /bin/sh                    → busybox' default shell
System configuration > Enable root login with password
System configuration > Root password              → <set one>
System configuration > Custom scripts to run inside the fakeroot environment
                                                  → board/<name>/post-build.sh
Target packages > Interpreter languages & scripting > python3
Target packages > Text editors and viewers          > nano
```

Then capture the config into the recipe so it's reproducible:

```bash
make savedefconfig BR2_DEFCONFIG=../recipes/<name>/buildroot.config
```

## Customizing the rootfs (overlay + post-build)

Two mechanisms you'll reuse for almost any custom distro:

### A post-build script — add a console and install an init script

Buildroot runs this in the fakeroot after the rootfs is assembled. This example
adds a `getty` on `tty1`, installs a custom init script, and removes the default
networking init:

```sh
#!/bin/sh
set -u
set -e

# Add a console on tty1
if [ -e ${TARGET_DIR}/etc/inittab ]; then
    grep -qE '^tty1::' ${TARGET_DIR}/etc/inittab || \
        sed -i '/GENERIC_SERIAL/a\
tty1::respawn:/sbin/getty -L  tty1 0 vt100' ${TARGET_DIR}/etc/inittab
fi

# Install a custom init script
cp board/<name>/S00custom ${TARGET_DIR}/etc/init.d/S00custom
chmod 755 ${TARGET_DIR}/etc/init.d/S00custom

# (optional) drop a default init you don't want
# rm ${TARGET_DIR}/etc/init.d/S40network
```

> For TinyEMU the important console is `hvc0` (virtio-console), set via
> `console=hvc0` in `vm.cmdline`. A `tty1` getty as above is only needed if you
> also want the emulated VGA/keyboard console.

### An init script — banner, a user, a custom prompt

A minimal example of the kind of first-boot setup an init script does — set a
login banner, create a non-root user, and give root a nicer prompt:

```sh
#!/bin/sh
# <name> - first-boot setup

echo "Welcome to <your distro>."

# Create home + add an unprivileged user
mkdir -p /home
/bin/chmod 755 /home
/usr/sbin/adduser -h /home/user/ -s /bin/sh user -D
echo -e "changeme\nchangeme" | /usr/bin/passwd user > /dev/null 2>&1

# Nicer root prompt
cat <<'EOT' >> /root/.profile
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOT
```

Adapt freely — seed files, set a hostname, drop a message of the day, install
service scripts. Keep secrets (real passwords, private keys) **out** of a
git-committed overlay; generate them per deployment instead.

### Mapping to this repo's overlay convention

The generic backends copy `overlay/.` straight onto the rootfs. For Buildroot,
either:

- keep the Buildroot idiom (a `board/<name>/` dir with `post-build.sh` that the
  `.config` references), storing it under `recipes/<name>/overlay/board/…`, or
- convert the post-build steps into plain overlay files where possible (e.g. ship
  `etc/init.d/S00custom` directly) and keep only the dynamic bits (user creation,
  per-deploy secrets) in `post-build.sh`.

## Kernel: enable the e1000 NIC (and more)

If you build the kernel, enable the drivers TinyEMU's guests use. For the NIC:

```
make linux-menuconfig
Device Drivers ─> Network device support ─> Ethernet driver support ─>
    <*> Intel(R) PRO/1000 Gigabit Ethernet support
    <*> Intel(R) PRO/1000 PCI-Express Gigabit Ethernet support
```

See [kernels.md](kernels.md) for the **full** required set (virtio-console,
virtio-blk, ext2, 9p) — a kernel missing virtio-blk can't mount `drive0`, and one
missing virtio-console gives you no `hvc0`.

## Build

Once the backend is implemented:

```bash
RECIPE=<name> docker compose run --rm build
```

Buildroot is heavy (downloads a toolchain, compiles everything). Expect a long
first build; the Buildroot download/ccache dir should be cached between runs.

## RISC-V

RISC-V doesn't depend on this backend: the riscv64 recipes use the Alpine and
Debian backends with a cross-compiled kernel and OpenSBI firmware (see
[riscv.md](riscv.md)). Once this backend exists, a Buildroot riscv32/64
defconfig (e.g. the old `buildroot-riscv32.config`) is one way to add riscv32;
see [`../future-work.md`](../future-work.md).

## Boot & ship

Same as every flavour — [hosting-and-boot.md](hosting-and-boot.md).
