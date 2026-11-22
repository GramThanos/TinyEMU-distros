# Build environment for the TinyEMU distro image pipeline.
# Produces ext2 rootfs images WITHOUT root/loop mounts (mke2fs -d), and can
# compile a guest kernel from source (kernel.source: build).
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        e2fsprogs \
        curl \
        ca-certificates \
        python3 \
        python3-yaml \
        tar \
        xz-utils \
        # --- kernel-from-source build (scripts/kernel.sh) ---
        build-essential \
        gcc-multilib \
        bc \
        bison \
        flex \
        cpio \
        perl \
        libelf-dev \
        libssl-dev \
        # --- RISC-V guests: clang/LLVM cross-compiles the kernel and OpenSBI
        #     (scripts/kernel.sh, scripts/firmware.sh; Debian's
        #     gcc-riscv64-linux-gnu conflicts with gcc-multilib above), and
        #     user-mode QEMU lets the rootfs backends run the guest's apk /
        #     apt-get (scripts/binfmt.sh) ---
        clang \
        lld \
        llvm \
        qemu-user-static \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
ENTRYPOINT ["/bin/bash"]
