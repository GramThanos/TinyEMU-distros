# Flavour: Debian

**Status: builds.** `recipes/debian-12-x86` is Debian 12 "bookworm" i386, from the
official `i386/debian:bookworm-slim` image, with python3, nano, procps and less.

Backend: [`scripts/backends/debian.sh`](../scripts/backends/debian.sh) ·
Recipe: [`recipes/debian-12-x86/`](../recipes/debian-12-x86)

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
   CAP_MKNOD), and afterwards drops them, the apt lists and `resolv.conf`. This step
   uses the network, so it is the one part that isn't byte-for-byte reproducible.
3. Applies `overlay/` (`cp -a overlay/. rootfs.dir/`).
4. `mke2fs -q -t ext2 -d rootfs.dir rootfs.ext2 <size_mb>M` + `tune2fs -c0 -i0`.

The kernel comes from `scripts/kernel.sh`: the recipe builds the same 6.12 LTS
kernel as `alpine-3.20-x86`.

## Build it

```bash
RECIPE=debian-12-x86 docker compose run --rm build   # -> build/debian-12-x86/
```

## init & console

The slim image is a container base, so it has **no init system**. The recipe boots
straight into a root shell on the virtio console, as the Alpine image does:

```yaml
vm:
  cmdline: "loglevel=1 console=hvc0 root=/dev/vda rw init=/bin/sh"
```

`/bin/sh` is dash. The kernel mounts devtmpfs on `/dev`; `/proc` is not mounted
until something mounts it (the TinyEMU agent page does). For a full init, install
`systemd-sysv` or `sysvinit-core` through `packages`, drop `init=`, and enable a
getty on `hvc0` in the overlay.

## Kernel note

The recipe builds the kernel from source (`kernel.source: build`, 6.12 LTS with
the tinyemu fragment), like Alpine's. Bookworm's glibc needs 3.2 or later, so
Bellard's older prebuilt kernel would also boot it, but it lacks newer features.

## Boot & ship

Same as every flavour — [hosting-and-boot.md](hosting-and-boot.md).
