# Flavour: Debian

**Status: builds.** Debian 12 "bookworm" i386, from the official
`i386/debian:bookworm-slim` image, in two recipes:

| Recipe | Boots into | Packages | Disk |
|--------|-----------|----------|------|
| [`debian-12-x86`](../recipes/debian-12-x86) | sysvinit, DHCP on eth0, root autologin on `hvc0` | sysvinit-core, ifupdown, udhcpc, iproute2, iputils-ping, curl, procps, htop, less, nano, python3 | 384 MB |
| [`debian-12-x86-lite`](../recipes/debian-12-x86-lite) | a root shell as PID 1 (`init=/bin/sh`) | python3, nano, procps, less | 256 MB |

(`debian-13-riscv64` and `debian-13-riscv64-lite` are the same for trixie on RISC-V, see [riscv.md](riscv.md).)

Backend: [`scripts/backends/debian.sh`](../scripts/backends/debian.sh)

## Where the rootfs comes from

The design decision is **reproducibility**: a
fixed, prebuilt rootfs, not `debootstrap`. The official Debian container images
are exactly that: [debuerreotype](https://github.com/debuerreotype/docker-debian-artifacts)
builds them reproducibly, and each is **one layer**, a plain rootfs tarball. Its
git branches (`dist-i386`, ...) hold the metadata, not the tarball itself (the
`oci/blobs` there are symlinks to files that aren't committed); the layer lives on
Docker Hub. So the recipe pins the layer by digest:

```yaml
rootfs:
  image: i386/debian
  digest: sha256:cf916cd2...   # the layer of bookworm/slim, from oci/index.json
```

`debian.sh` gets an anonymous pull token, downloads that blob from
`registry-1.docker.io`, and checks its sha256 against the digest. To move to a
newer point release, take the layer digest from the `dist-i386` branch's
`bookworm/slim/oci/index.json` (its manifest, base64 in `data`, names the layer).

A plain tarball URL also works (`rootfs.tarball_url`, with `rootfs.sha256` to check
it), for a rootfs hosted anywhere else.

## How the backend works

1. Fetches and verifies the rootfs (above) and untars it into `rootfs.dir/`.
2. Installs `rootfs.packages` with `apt-get` in a chroot (i386 runs on the x86_64
   builder). It makes the few device nodes maintainer scripts need (Docker grants
   CAP_MKNOD) and a `policy-rc.d` that stops them starting services in the
   chroot, and afterwards drops those, the apt lists and `resolv.conf`. This step
   uses the network, so it is the one part that isn't byte-for-byte reproducible.
3. Applies `overlay/` (`cp -a overlay/. rootfs.dir/`).
4. Runs the recipe's `setup.sh`, when it has one, inside the rootfs (`chroot`).
5. `mke2fs -q -t ext2 -d rootfs.dir rootfs.ext2 <size_mb>M` + `tune2fs -c0 -i0`.

The kernel comes from `scripts/kernel.sh`: the recipe builds the same 6.12 LTS
kernel as `alpine-3.20-x86`.

## Build it

```bash
RECIPE=debian-12-x86 docker compose run --rm build        # -> build/debian-12-x86/
RECIPE=debian-12-x86-lite docker compose run --rm build   # -> build/debian-12-x86-lite/
```

## init & console

The slim image is a container base, so it has **no init system**.

**Lite** boots straight into a root shell on the virtio console, as the Alpine lite
image does:

```yaml
vm:
  cmdline: "loglevel=1 console=hvc0 root=/dev/vda rw init=/bin/sh"
```

`/bin/sh` is dash. The kernel mounts devtmpfs on `/dev`; `/proc` is not mounted
until something mounts it (the TinyEMU agent page does).

**Full** installs `sysvinit-core` and boots it (no `init=`). systemd would work
too, but on a software CPU its start-up costs far more than sysvinit's shell
scripts. The pieces:

- `overlay/etc/inittab`: runlevel 2, and the only getty, an `agetty --autologin root`
  on `hvc0` (sysvinit's default one names `tty1`..`tty6`, which TinyEMU doesn't have);
- `overlay/etc/fstab`: `/` on `/dev/vda`, no fsck at boot;
- `overlay/etc/network/interfaces`: `lo`, and `eth0` by DHCP. `ifupdown` runs
  `udhcpc -n`, which gives up after a few tries when no server answers;
- `setup.sh`: clears root's password. The packages enabled their own init
  scripts when they were installed.

## Kernel note

The recipe builds the kernel from source (`kernel.source: build`, 6.12 LTS with
the tinyemu fragment), like Alpine's. Bookworm's glibc needs 3.2 or later, so
Bellard's older prebuilt kernel would also boot it, but it lacks newer features.

## Boot & ship

Same as every flavour — [hosting-and-boot.md](hosting-and-boot.md).
