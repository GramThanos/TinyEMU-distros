# Prebuilt kernels

Drop-in reference kernels for recipes whose `kernel.source: prebuilt`.

A recipe can point at a kernel two ways:

- `kernel.url:` — fetched at build time (what the seed recipes use, e.g.
  Bellard's `https://bellard.org/jslinux/kernel-x86.bin`).
- a local file here — reference it from the backend instead of a URL when you
  want a pinned, checked-in kernel (large binaries stay out of git per the repo
  policy; use this dir for a locally-staged kernel, not for committing 4 MB blobs).

The recipes build their kernel from source (`kernel.source: build`, see
[docs/kernels.md](../../docs/kernels.md)) with virtio-console, virtio-blk, e1000
and 9p enabled, so they don't depend on prebuilt binaries.
