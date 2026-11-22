# Troubleshooting

The problems that actually bit us building and booting these images, with fixes.
Grouped by where they show up.

## Build environment

### `docker compose run build` fails with glibc / library version errors
**Cause:** the engine's Docker base is `fedora:40` (glibc 2.39); a `run`/builder
image built earlier from an older base mismatches.
**Fix:** rebuild the image — `docker compose build builder` (or add `--build`).

### `make dist` skips the in-container rebuild (stale binary)
**Cause:** stale host `.o` files make `make` think everything is up to date, so
the in-container rebuild is a no-op and you run an old binary.
**Fix:** `make clean` first, then rebuild.

### Scripts misbehave when run from Git Bash on Windows
**Symptom:** `stage-web.sh` / `docker … -e TEMU_CONFIG=/workspace/…` get wrong
paths; python gets a mangled absolute path.
**Cause:** Git Bash (MSYS) rewrites absolute POSIX paths before passing them to
native `python.exe` / docker.
**Fix:** run the build/stage scripts in **WSL** or the **builder container**, not
Git Bash. If you must, prefix docker calls with `MSYS_NO_PATHCONV=1`.

### `apk-in-chroot failed … — add at first boot`
**Cause:** the build host can't execute the guest arch under chroot (needs 32-bit
ELF support for i686 guests).
**Fix:** it's a warning, not fatal — the rootfs still builds without those
packages. Either run the build on a host that can run i686 (WSL2 can), or `apk
add` the packages in the guest once networking is up.

### `mke2fs -d` can't fit the tree / out-of-space in the guest
**Cause:** `rootfs.size_mb` is smaller than the unpacked rootfs + packages (+
headroom for guest writes).
**Fix:** raise `rootfs.size_mb` in the recipe and rebuild.

## Kernel build (`kernel.source: build`)

### Build errors: missing `bison`/`flex`/`libelf`/`bc`, or 32-bit link failures
**Cause:** the kernel toolchain isn't installed, or lacks 32-bit (i386) support.
**Fix:** build in the repo's Docker container — its `Dockerfile` installs
`build-essential`, `gcc-multilib`, `bc`, `bison`, `flex`, `cpio`, `perl`,
`libelf-dev`, `libssl-dev`. If you rebuilt the image, make sure it picked up the
new deps (`docker compose build builder`).

### The kernel build is painfully slow (or seems stuck extracting)
**Cause:** unpacking/compiling the kernel tree (tens of thousands of small files)
**on a Docker Desktop bind mount** is extremely slow.
**Fix:** `kernel.sh` already builds on a container-local `/tmp` path and copies
only `kernel.bin` back to `build/<name>/` — don't change it to build under the
mounted output dir. First compile still takes a few minutes.

### The self-built kernel boots but hangs or panics on the engine
**Cause:** a kernel newer than the engine supports, or a missing driver.
**Fix:** stick to a verified LTS (**6.12** default, or 5.15) unless you've tested
newer; confirm the config fragment still enables virtio-console/blk (see below).
Build against a **current engine** (the `verr`/`verw` + PAE fixes).

## Chunking

### `block_net.c` asserts on fetched size / boot aborts reading the disk
**Cause:** a chunk isn't exactly `block_size * 1024` bytes — a short trailing
chunk. (The old `blk-split.py` only worked when the image divided evenly.)
**Fix:** use `scripts/chunk.py` — it zero-pads the final chunk. Ensure
`disk.block_size_kb` (recipe) == `chunk.py -b` == `block_size` in `blk.txt`, and
that it's a power of two.

### `Could not load block N` / `unsupported block device compression`
**Cause:** gzip chunks (`blk*.bin.gz`, `"compression": "gzip"` in `blk.txt`) on an
engine older than 2026-11, which only fetches raw `blk*.bin`.
**Fix:** update the engine, or rebuild with `disk.compression: none`.

## Native boot

### Booting a local `blk.txt` segfaults / core-dumps
**Cause (old engines):** the native block layer only routed the `splitimg`
manifest to the chunk reader for `http:`/`file:` URLs; a *local* `blk.txt` was
opened as a raw image (`nb_sectors = 0`) and the read path walked off its sector
table.
**Fix:** use an engine that recognizes a local split manifest (the current
engine does — it serves chunks from the sibling `blk*.bin`). See
[hosting-and-boot.md](hosting-and-boot.md).

### `perror: No such file or directory` on the drive at startup
**Cause:** `drive0.file` points somewhere that doesn't exist — classically a
stale `distro/blk.txt` when the chunks are flat next to the config.
**Fix:** the chunks/manifest sit **flat** beside `config.cfg`; point
`drive0.file` at `blk.txt` (no `distro/` subfolder). Or render the config with a
correct `--asset-base`.

### Kernel boots but no console / no prompt
**Cause:** the kernel lacks virtio-console (`hvc0`) or the rootfs runs no
getty/init on the console.
**Fix:** use a kernel with `CONFIG_VIRTIO_CONSOLE` ([kernels.md](kernels.md));
either run a getty on `hvc0` in the rootfs (as the full recipes' `overlay/etc/inittab`
does) or boot with `init=/bin/sh` (as the `-lite` recipes do).

### Kernel panics: can't mount root / `/dev/vda` missing
**Cause:** the kernel lacks virtio-blk, or `root=`/filesystem type is wrong.
**Fix:** kernel needs `CONFIG_VIRTIO_BLK` + `CONFIG_EXT2_FS`; keep
`root=/dev/vda` and an ext2 image.

### Windows `temu.exe` can't fetch or boot
**Cause:** the Windows build lacks `CONFIG_FS_NET`/SLIRP/SDL.
**Fix:** boot under the Linux/WSL build; use Windows only for offline/local runs.

## Browser boot

### Kernel loads but the drive 404s (or vice-versa); guest exits(1)
**Cause:** relative or root-relative `${ASSET_BASE}` — the browser resolves the
kernel URL relative to the `.cfg` dir but the drive URL relative to the document
root.
**Fix:** use **fully-absolute** URLs. `stage-web.sh` and `publish.sh` bake them;
if editing by hand, make `${ASSET_BASE}` a complete `http(s)://…` URL.

### "It hangs" before the shell
**Cause:** real browser boot to `/bin/sh` takes ~20–25 s.
**Fix:** wait — it's not a hang. If nothing after ~1 min, check the console for a
404 (see above) or a kernel panic.

### `eth0` — is it a problem in the browser?
**No.** The WASM build ignores the `eth0` `driver` field and bridges the NIC to
the JS `VirtualNetwork`; the same config works natively (SLIRP) and in-browser.
The guest still has to bring the interface up (`udhcpc`) to use it. (An earlier
"multi-VM aborts" report was a misdiagnosis — root-relative drive URLs + boot
time, not `eth0`.)

## Still stuck?

- Re-read the stage that failed in [pipeline.md](pipeline.md).
- Check the recipe against [recipe-reference.md](recipe-reference.md).
