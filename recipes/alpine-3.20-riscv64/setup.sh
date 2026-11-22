#!/bin/sh
# Runs inside the rootfs (chroot) after packages and overlay/ are in place.
# Enables the OpenRC services a TinyEMU guest needs and unlocks root.
set -e

chmod 755 /usr/local/sbin/autologin   # overlay modes do not survive every checkout

for s in devfs dmesg;                  do rc-update add "$s" sysinit;  done
for s in hostname bootmisc syslog;     do rc-update add "$s" boot;     done
# TinyEMU's riscv machine has no RTC, so hwclock (which syslog would pull in
# for "clock") fails there. swclock provides "clock" from the time of the last
# shutdown instead.
rc-update add swclock boot
for s in networking;                   do rc-update add "$s" default;  done
for s in killprocs savecache mount-ro; do rc-update add "$s" shutdown; done

# The kernel is monolithic and devtmpfs fills /dev, so modules (no /lib/modules;
# overlay/etc/modules is empty in case something pulls it in) and mdev (no
# uevent helper) would only print errors at boot.
rc-update del modules boot 2>/dev/null || true
rc-update del mdev sysinit 2>/dev/null || true

# Empty root password: the console autologs in as root anyway, and this lets
# `login` on a second console or `su` work too.
passwd -d root
