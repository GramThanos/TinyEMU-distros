# Flavour: Alpine Linux

The `build.sh alpine-3.20-x86` produces a clean image that boots to a root shell natively (raw `drive0`) and in-browser (chunked HTTP).
This is the reference flavour, you may copy it when starting a new tarball-based distro.

Backend: [`scripts/backends/alpine.sh`](../scripts/backends/alpine.sh) ·
Recipe: [`recipes/alpine-3.20-x86/`](../recipes/alpine-3.20-x86)

## How the backend works

Alpine ships an official **minirootfs** tarball — a tiny, ready userland, so the backend never builds from source.

Given `<recipe_dir>` and `<out>` it:

1. Derives the mirror path from the recipe: `$mirror/v<major.minor>/releases/$arch/$minirootfs` (e.g. `.../v3.20/releases/x86/alpine-minirootfs-3.20.3-x86.tar.gz`). The branch `v3.20` is computed from `rootfs.version` (`${ver%.*}`).
2. `curl`s the tarball and untars it into `rootfs.dir/`.
3. **Packages** (`rootfs.packages`): copies the host `/etc/resolv.conf` in, then runs `chroot rootfs.dir /sbin/apk --no-cache add <pkgs>`. On x86_64 hosts this works for i686 guests (32-bit ELF runs under WSL2/most Linux). If the chroot can't execute the guest arch, it prints a warning and continues (add those packages at first boot instead).
4. **Overlay**: `cp -a overlay/. rootfs.dir/` (see below).
5. `mke2fs -q -t ext2 -d rootfs.dir rootfs.ext2 <size_mb>M` then `tune2fs -c0 -i0` — build the ext2 with no mount, disable forced fsck.

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

Anything under `recipes/<name>/overlay/` is copied onto the rootfs, preserving paths. The seed ships an MOTD:

```
recipes/alpine-3.20-x86/overlay/
└── etc/
    └── motd
```

Use it for `/etc/motd`, `/etc/hostname`, a profile script, seed files, a custom init script, etc. Example, add a login banner and a hostname:

```bash
mkdir -p recipes/alpine-3.20-x86/overlay/etc
echo "tinyemu-alpine" > recipes/alpine-3.20-x86/overlay/etc/hostname
nano recipes/alpine-3.20-x86/overlay/etc/motd
```

### Image size

`rootfs.size_mb` is the ext2 size. It must comfortably exceed the unpacked tree plus installed packages plus headroom for guest writes. 128 MB fits a minimal Alpine + a couple of packages; bump it if `mke2fs -d` complains it can't fit the tree, or if the guest needs to have more space.

### Real init instead of `init=/bin/sh`

The minirootfs has no init configured, so the recipe uses `init=/bin/sh`. To boot a full Alpine:

1. `apk add openrc` (and configure services) in the overlay or at first boot.
2. Set up the console in `/etc/inittab` (a getty on `hvc0`).
3. Drop `init=/bin/sh` from `vm.cmdline`.

## New Alpine version / arch

- Bump `rootfs.version` **and** `rootfs.minirootfs` (the filename embeds the version). Confirm the tarball exists under the derived mirror path.
- The kernel is independent of the Alpine version — the recipe builds Linux 6.12 LTS from source by default (`kernel.source: build`). See [kernels.md](kernels.md).

## Boot & ship

See [hosting-and-boot.md](hosting-and-boot.md) for native + browser boot and for publishing. Common gotchas (glibc base mismatch, absolute URLs, stale `.o`) are in [troubleshooting.md](troubleshooting.md).
