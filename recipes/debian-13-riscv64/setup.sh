#!/bin/sh
# Runs inside the rootfs (chroot) after packages and overlay/ are in place.
# The packages' own scripts already enabled their init scripts (sysv-rc).
set -e

# Two things sysvinit warns about at every boot when they are missing.
ln -sf /proc/mounts /etc/mtab       # the exact target initscripts checks for
mkdir -p /etc/inittab.d

# Empty root password: the console autologs in as root anyway, and this lets
# `login` on a second console or `su` work too.
passwd -d root
