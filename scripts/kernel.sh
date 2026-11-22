#!/usr/bin/env bash
# scripts/kernel.sh <recipe_dir> <out>
#
# Produce <out>/kernel.bin according to the recipe's kernel.source:
#
#   prebuilt   fetch kernel.url  (fast; the seed default)
#   build      compile a vanilla Linux kernel from source for the guest arch,
#              merging kernels/config/tinyemu-<x86|riscv>.fragment onto the
#              arch defconfig (virtio-console/blk/net, ext2/4, 9p). x86 gives a
#              bzImage; riscv32/riscv64 a raw Image, cross-compiled, which
#              TinyEMU loads after the OpenSBI firmware (scripts/firmware.sh)
#   buildroot  no-op here — the buildroot backend emits kernel.bin itself
#
# Called by build.sh after the rootfs backend runs, so kernel handling is the
# same for every rootfs flavour (alpine/debian).
set -euo pipefail
recipe_dir="$1"; out="$2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
yq() { python3 "$here/recipe.py" "$recipe_dir/recipe.yml" "$1"; }

ksrc="$(yq kernel.source)"
arch="$(yq arch)"

case "$ksrc" in
  prebuilt)
    kurl="$(yq kernel.url)"
    echo "-- kernel: fetching prebuilt $kurl"
    curl -fSL "$kurl" -o "$out/kernel.bin"
    ;;

  buildroot)
    # The buildroot backend builds the kernel alongside the rootfs.
    [ -f "$out/kernel.bin" ] || {
      echo "!! kernel.source=buildroot but the backend produced no kernel.bin"; exit 1; }
    echo "-- kernel: provided by the buildroot backend"
    ;;

  build)
    kver="$(yq kernel.version)"
    [ -n "$kver" ] || { echo "!! kernel.source=build needs kernel.version"; exit 1; }
    # kernel.url may override the download location; else derive from kernel.org.
    kurl="$(yq kernel.url 2>/dev/null || true)"
    series="v${kver%%.*}.x"                       # 5.15.220 -> v5.x
    [ -n "$kurl" ] || kurl="https://cdn.kernel.org/pub/linux/kernel/$series/linux-$kver.tar.xz"

    cross=""
    case "$arch" in
      x86|i386|i686) karch=i386; kdefconfig=i386_defconfig; ktarget=bzImage
                     kimage=arch/x86/boot/bzImage; frag=x86 ;;
      riscv64) karch=riscv; kdefconfig=defconfig; ktarget=Image
               kimage=arch/riscv/boot/Image; frag=riscv; cross=llvm ;;
      riscv32) karch=riscv; kdefconfig=rv32_defconfig; ktarget=Image
               kimage=arch/riscv/boot/Image; frag=riscv; cross=llvm ;;
      *) echo "!! kernel.source=build: arch '$arch' not wired yet"; exit 1 ;;
    esac
    frag="$root/kernels/config/tinyemu-$frag.fragment"
    [ -f "$frag" ] || { echo "!! missing config fragment: $frag"; exit 1; }

    # Build on a LOCAL path, never the (bind-mounted) output dir: the source tree
    # is tens of thousands of small files and unpacking/compiling it on a Docker
    # Desktop bind mount is punishingly slow. Only kernel.bin lands in $out.
    work="$(mktemp -d "${TMPDIR:-/tmp}/tinyemu-kbuild.XXXXXX")"
    trap 'rm -rf "$work"' EXIT
    echo "-- kernel: fetching source $kurl"
    curl -fSL "$kurl" -o "$work/linux-src.tar.xz"
    echo "-- kernel: extracting"
    mkdir -p "$work/src"
    tar -xf "$work/linux-src.tar.xz" -C "$work/src" --strip-components=1
    src="$work/src"

    # RISC-V is cross-compiled with clang/LLVM (LLVM=1); x86 uses the host gcc.
    kmake=(make -C "$src" ARCH=$karch)
    [ "$cross" != llvm ] || kmake+=(LLVM=1)

    echo "-- kernel: configuring ($kdefconfig + tinyemu fragment)"
    "${kmake[@]}" "$kdefconfig"
    # merge_config.sh runs make itself, so it needs the same toolchain choice.
    ARCH=$karch LLVM=$([ "$cross" = llvm ] && echo 1) \
      "$src/scripts/kconfig/merge_config.sh" -m -O "$src" "$src/.config" "$frag"
    "${kmake[@]}" olddefconfig

    echo "-- kernel: building (this takes a few minutes)"
    "${kmake[@]}" -j"$(nproc)" "$ktarget"

    cp "$src/$kimage" "$out/kernel.bin"
    echo "-- kernel: built $(du -h "$out/kernel.bin" | cut -f1) -> $out/kernel.bin"
    rm -rf "$work"; trap - EXIT
    ;;

  *)
    echo "!! unknown kernel.source '$ksrc' (want: prebuilt | build | buildroot)"; exit 1 ;;
esac
