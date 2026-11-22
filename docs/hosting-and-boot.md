# Hosting & booting an image

Once `build/<name>/` exists (see [pipeline.md](pipeline.md)), here's how to boot
it locally and how to ship it so others can.

## The deliverable

```
build/<name>/
├── kernel.bin
├── bios.bin             RISC-V only: the OpenSBI firmware
├── rootfs.ext2          full image — needed only for a RAW native boot
├── blk.txt              chunk manifest
├── blk*.bin[.gz]        chunks (the hostable disk; .gz with disk.compression: gzip)
└── config.cfg           has a literal ${ASSET_BASE} placeholder
```

Everything the guest needs is `kernel.bin` (+ `bios.bin` for RISC-V) + `blk.txt` +
`blk*.bin` + `config.cfg`. Keep `rootfs.ext2` only if you want to boot the raw image directly
(native); it isn't needed for chunked hosting and isn't in the published tarball.

## `${ASSET_BASE}` — the one thing to resolve

`config.cfg` ships with `kernel:` and `drive0.file:` pointing at
`${ASSET_BASE}/…`. `${ASSET_BASE}` is wherever `kernel.bin`, `blk.txt`, and the
chunks live. Resolve it differently per target:

| Target | `${ASSET_BASE}` should be | Set by |
|--------|---------------------------|--------|
| Native, files local | an **absolute local path** to `build/<name>/` (or `.`) | `mkconfig.py --asset-base`, or a `sed` |
| Browser, local dev | an **absolute URL** to the staged dir | `stage-web.sh` |
| Browser, hosted | an **absolute URL** to your static host / release | `publish.sh` + a `sed` |

The chunks must sit **in the same directory as `blk.txt`** — the engine derives
the chunk location by stripping `blk.txt` back to its last `/` (native) or `/`
(URL). There is no need for a `distro/` subfolder; a flat directory is expected.

## Boot it natively (`temu` / `temu-soft`)

Native TinyEMU (the engine repo's `dist/linux/temu-soft`, or a `make temu`
build) can boot either the raw image or the chunked manifest.

### Raw `drive0` (simplest)

Point `drive0.file` at `rootfs.ext2`. Render a config with an absolute asset base:

```bash
# from the repo root
python3 scripts/mkconfig.py recipes/<name> \
    --asset-base "$(pwd)/build/<name>" -o build/<name>/local.cfg
# edit build/<name>/local.cfg: change drive0 file to rootfs.ext2 for a raw boot
#   drive0: { file: "…/build/<name>/rootfs.ext2" }
temu build/<name>/local.cfg
```

### Chunked `drive0` (same files the browser uses)

You can also boot the **chunked** `blk.txt` natively — the native block layer
now recognizes a local `splitimg` manifest and serves sectors from the sibling
`blk%09u.bin` files (the same layout the browser fetches over HTTP). Just render
the config with a local asset base and boot it:

```bash
python3 scripts/mkconfig.py recipes/<name> \
    --asset-base "$(pwd)/build/<name>" -o build/<name>/local.cfg
temu build/<name>/local.cfg          # drive0 file = …/build/<name>/blk.txt
```

Or run `temu` from inside `build/<name>/` against a config that uses bare
relative names (`kernel: "kernel.bin"`, `drive0: { file: "blk.txt" }`) — relative
paths resolve against the config's own directory.

> **History.** Older engine builds only routed `blk.txt` to the chunk reader for
> `http:`/`file:` URLs; a *local* `blk.txt` was mistaken for a raw image and
> segfaulted the host. That's fixed — a flat local chunked dir boots natively.
> Point `drive0.file` at `blk.txt` (not a nonexistent `distro/blk.txt`).

Fast, network-free loop for testing: WSL-native `make temu`, an absolute-path
config, `cmdline: "... console=hvc0 root=/dev/vda rw init=/bin/sh"` — boots in
seconds. (Windows `temu.exe` lacks the FS-net/SLIRP/SDL bits; boot under
Linux/WSL.)

## Boot it in the browser

### Local dev — `stage-web.sh`

Stages a build into a [jsLab](https://github.com/gramthanos/jsLab) checkout and
registers it in its demos' dropdown:

```bash
# in WSL / the builder — NOT Git Bash (it mangles POSIX paths to python.exe)
bash scripts/stage-web.sh <name> /path/to/jsLab http://localhost:8000
# copies assets to jsLab/_distro/<name>/, writes jsLab/_distro/manifest.json,
# renders config.cfg with ABSOLUTE URLs against the origin
```

Then serve jsLab (`npm run fetch-engine && npm run serve` there) and open:

- `demos/linux-distro.html` — single-VM, dependency-free boot page, or
- `demos/demo.html` — multi-VM; your distro is in the dropdown (inline + worker).

### Why URLs must be absolute

In the browser the engine resolves the **kernel** URL relative to the `.cfg`'s
directory but the **drive** URL relative to the document root. Only
fully-absolute URLs satisfy both — a relative or root-relative base boots the
kernel but 404s the drive (or vice-versa), and the guest exits. `stage-web.sh`
and `publish.sh` bake absolute URLs for this reason. Real browser boot to
`/bin/sh` takes ~20–25 s — don't mistake the pre-shell wait for a hang.

`eth0` is fine in the browser: the WASM build ignores the `driver` field and
bridges the NIC to the JS `VirtualNetwork` (the guest still needs `udhcpc` to
bring it up).

## Publish it — `publish.sh`

Packages the hostable files and (by default) uploads to a GitHub Release:

```bash
bash scripts/publish.sh <name>
# tars kernel.bin + blk.txt + the chunks + config.cfg  (NOT rootfs.ext2)
# gh release create/upload distro-<name>
```

No `gh`? It just leaves the tarball at `build/<name>.tar` for you to upload
anywhere. Then point `${ASSET_BASE}` at wherever the extracted files live:

```bash
sed -i 's#${ASSET_BASE}#https://cdn.example.com/tinyemu/<name>#g' config.cfg
```

The host is deliberately your choice — the pipeline is host-agnostic; swapping
hosts is a one-line change to the upload step / the `sed`.

## 9p mode (alternative disk)

If a recipe uses `disk.mode: 9p`, there are no chunks — the rootfs is served over
9p (`fs0`) instead of virtio-block. Chunked `drive0` is the default and the
recommended path (self-hostable static files, overlay-capable); 9p is the older
mechanism kept for compatibility.

## Next

- Something didn't boot → [troubleshooting.md](troubleshooting.md).
- Change what's in the image → the flavour guide + [recipe-reference.md](recipe-reference.md).
