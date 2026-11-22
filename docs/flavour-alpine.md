# Flavour: Alpine Linux

Two recipes per arch, built from the same minirootfs:

| Recipe | Boots into | Packages | Disk |
|--------|-----------|----------|------|
| [`alpine-3.20-x86`](../recipes/alpine-3.20-x86) | OpenRC, DHCP on eth0, root autologin on `hvc0` | alpine-base, ifupdown-ng, python3, nano, less, curl, htop | 192 MB |
| [`alpine-3.20-x86-lite`](../recipes/alpine-3.20-x86-lite) | a root shell as PID 1 (`init=/bin/sh`) | python3, nano | 128 MB |

(`alpine-3.20-riscv64` and `alpine-3.20-riscv64-lite` are the same for RISC-V, see [riscv.md](riscv.md).)
The lite image boots to a root shell natively (raw `drive0`) and in-browser (chunked HTTP).
This is the reference flavour, you may copy it when starting a new tarball-based distro.

Backend: [`scripts/backends/alpine.sh`](../scripts/backends/alpine.sh)

## How the backend works

Alpine ships an official **minirootfs** tarball — a tiny, ready userland, so the backend never builds from source.

Given `<recipe_dir>` and `<out>` it:

1. Derives the mirror path from the recipe: `$mirror/v<major.minor>/releases/$arch/$minirootfs` (e.g. `.../v3.20/releases/x86/alpine-minirootfs-3.20.3-x86.tar.gz`). The branch `v3.20` is computed from `rootfs.version` (`${ver%.*}`).
2. `curl`s the tarball and untars it into `rootfs.dir/`.
3. **Packages** (`rootfs.packages`): copies the host `/etc/resolv.conf` in, then runs `chroot rootfs.dir /sbin/apk --no-cache add <pkgs>`. On x86_64 hosts this works for i686 guests (32-bit ELF runs under WSL2/most Linux). If the chroot can't execute the guest arch, it prints a warning and continues (add those packages at first boot instead).
4. **Overlay**: `cp -a overlay/. rootfs.dir/` (see below).
5. **setup.sh**, when the recipe has one: run inside the rootfs with `chroot` (the full recipe enables its OpenRC services there).
6. `mke2fs -q -t ext2 -d rootfs.dir rootfs.ext2 <size_mb>M` then `tune2fs -c0 -i0` — build the ext2 with no mount, disable forced fsck.

The kernel is then produced by the shared `kernel.sh` step, not the backend. The Alpine recipe defaults to `kernel.source: build` (compile Linux 6.12 LTS from source); You may set `kernel.source: prebuilt` for a faster build using a prebuild kernel. See [kernels.md](kernels.md).

Then `build.sh` chunks + renders the config (see [pipeline.md](pipeline.md)).

## Build it

```bash
# (run-once) Prepare the builder docker image
docker compose build builder
# Pick your flavour
export RECIPE=alpine-3.20-x86
# Build your image
docker compose run --rm build
# Check the image available under build/alpine-3.20-x86/
```

## Customizing

### Packages

Edit `rootfs.packages` in the recipe:

```yaml
rootfs:
  packages:
    - python3
    - nano
    - tcpdump # add what you need
```

They're installed at build time via chroot'd `apk`. If the build host can't run the guest arch, they're skipped (warning) and the guest can `apk add` them later once/if networking is up.

### Files in the image (`overlay/`)

Anything under `recipes/<name>/overlay/` is copied onto the rootfs, preserving paths. The lite recipe ships only an MOTD; the full one also sets up the console and the network:

```
recipes/alpine-3.20-x86/overlay/
├── etc/
│   ├── fstab                 / on /dev/vda
│   ├── hostname, hosts       tinyemu-alpine
│   ├── inittab               OpenRC + a getty on hvc0
│   ├── modules               empty: the kernel is monolithic
│   ├── motd
│   └── network/interfaces    lo + eth0 by DHCP
└── usr/local/sbin/autologin  what that getty runs: login -f root
```

Use it for `/etc/motd`, `/etc/hostname`, a profile script, seed files, a custom init script, etc. Example, add a login banner and a hostname:

```bash
mkdir -p recipes/alpine-3.20-x86/overlay/etc
echo "tinyemu-alpine" > recipes/alpine-3.20-x86/overlay/etc/hostname
nano recipes/alpine-3.20-x86/overlay/etc/motd
```

### Image size

`rootfs.size_mb` is the ext2 size. It must comfortably exceed the unpacked tree plus installed packages plus headroom for guest writes. 128 MB fits a minimal Alpine + a couple of packages; bump it if `mke2fs -d` complains it can't fit the tree, or if the guest needs to have more space.

### init: the full recipe vs. lite

The minirootfs has no init system, so the lite recipe boots with `init=/bin/sh`. The full recipe boots a real Alpine:

1. `alpine-base` in `packages` brings OpenRC and busybox's init.
2. `overlay/etc/inittab` runs OpenRC and puts the only getty on `hvc0` (the minirootfs one names `tty1`..`tty6`, which TinyEMU doesn't have), logging root in at once.
3. `setup.sh` adds the services to their runlevels (`devfs`, `dmesg`; `hostname`, `bootmisc`, `syslog`; `networking`) and takes `modules` and `mdev` out: the kernel is monolithic and devtmpfs already fills `/dev`. It also clears root's password.
4. `vm.cmdline` has no `init=`, so the kernel runs `/sbin/init`.

`networking` brings eth0 up with `udhcpc`, which goes to the background when no DHCP server answers, so boot doesn't wait for a network.

## New Alpine version / arch

- Bump `rootfs.version` **and** `rootfs.minirootfs` (the filename embeds the version). Confirm the tarball exists under the derived mirror path.
- The kernel is independent of the Alpine version — the recipe builds Linux 6.12 LTS from source by default (`kernel.source: build`). See [kernels.md](kernels.md).

## Boot & ship

See [hosting-and-boot.md](hosting-and-boot.md) for native + browser boot and for publishing. Common gotchas (glibc base mismatch, absolute URLs, stale `.o`) are in [troubleshooting.md](troubleshooting.md).
