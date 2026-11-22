#!/usr/bin/env bash
# scripts/binfmt.sh <arch>
#
# Make sure the build container can run <arch> binaries, so a backend can chroot
# into a foreign rootfs and run its package manager (apk, apt-get). Native and
# i386 (x86) need nothing. For riscv64 it registers the builder's
# qemu-riscv64-static with binfmt_misc, with the F flag, so the interpreter
# works inside the chroot without being copied into it.
#
# binfmt_misc belongs to the Docker host's kernel (the Docker Desktop VM): the
# registration needs a privileged container (docker-compose.yml's build service
# is one), and lasts until that VM restarts. Exits non-zero when <arch> can't be
# run; the backends then skip their package step with a warning.
set -euo pipefail
arch="$1"

case "$arch" in
  x86|i386|i686|x86_64) exit 0 ;;
  riscv64) qarch=riscv64; magic='\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xf3\x00'
           mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff' ;;
  riscv32) qarch=riscv32; magic='\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xf3\x00'
           mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff' ;;
  *) echo "!! binfmt.sh: no QEMU mapping for arch '$arch'"; exit 1 ;;
esac

bm=/proc/sys/fs/binfmt_misc
[ -f "$bm/status" ] || mount -t binfmt_misc binfmt_misc "$bm" 2>/dev/null || {
  echo "!! binfmt_misc is not available (the container is not privileged?)"; exit 1; }
if [ -f "$bm/qemu-$qarch" ] && grep -q '^enabled' "$bm/qemu-$qarch"; then
  echo "-- binfmt: qemu-$qarch already registered"
  exit 0
fi
interp="/usr/bin/qemu-$qarch-static"
[ -x "$interp" ] || { echo "!! $interp is missing from the builder image"; exit 1; }
echo ":qemu-$qarch:M::$magic:$mask:$interp:F" > "$bm/register" 2>/dev/null || {
  echo "!! could not register qemu-$qarch with binfmt_misc (not privileged?)"; exit 1; }
echo "-- binfmt: registered qemu-$qarch"
