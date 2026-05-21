# ---------------------------------------------------------------
#  proxmox-atd :: Build Container
#  Reproducible build environment for QEMU, EDK2, and Kernel
#
#  Usage:
#    docker build -t atd-builder .
#    docker run --rm -v ./build-output:/build/build-output atd-builder --target qemu
#
#  Or use the convenience script:
#    ./docker-build.sh --target qemu
#
#  Part of: https://github.com/proxmox-atd
# ---------------------------------------------------------------

FROM debian:trixie-slim

LABEL maintainer="PTHyperdrive"
LABEL description="Proxmox Anti-Detection build environment (PVE 9 / Trixie)"

# ── Prevent interactive prompts ──
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Ho_Chi_Minh
ENV CI=1

# ── Add Proxmox no-subscription repository ──
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        ca-certificates curl gnupg wget && \
    # Import Proxmox GPG key
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg \
        -o /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg && \
    # Add PVE no-subscription repo
    echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
        > /etc/apt/sources.list.d/pve-no-subscription.list && \
    apt-get update -qq && \
    rm -rf /var/lib/apt/lists/*

# ── Install ALL build dependencies in one layer ──
# This is the union of QEMU + EDK2 + Kernel deps from the orchestrator.
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        # Core build tools
        build-essential git devscripts meson quilt \
        # QEMU dev libs
        libacl1-dev libaio-dev libattr1-dev libcap-ng-dev \
        libcurl4-gnutls-dev libepoxy-dev libfdt-dev libgbm-dev \
        libgnutls28-dev libiscsi-dev libjpeg-dev libnuma-dev \
        libpci-dev libpixman-1-dev librbd-dev libsdl1.2-dev \
        libseccomp-dev libslirp-dev libspice-protocol-dev \
        libspice-server-dev libsystemd-dev liburing-dev \
        libusb-1.0-0-dev libusbredirparser-dev libvirglrenderer-dev \
        python3-sphinx python3-sphinx-rtd-theme xfslibs-dev \
        # Common tools
        bc dosfstools iasl mtools nasm python3 python3-pexpect \
        qemu-utils uuid-dev xorriso curl jq zip \
        # Kernel deps
        dh-python asciidoc-base bison dwarves flex \
        libdw-dev libelf-dev libiberty-dev libslang2-dev \
        lz4 python3-dev xmlto rsync gawk \
        # EDK2 cross-compilers
        gcc-aarch64-linux-gnu gcc-riscv64-linux-gnu \
        # PVE-specific
        libproxmox-backup-qemu0-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Working directory ──
WORKDIR /build

# ── Copy source tree ──
COPY . /build/

# ── Make scripts executable ──
RUN chmod +x pve-build-orchestrator.sh atd-patcher.sh lib/atd-styles.sh && \
    chmod +x patches/*.patch.sh 2>/dev/null || true

# ── Default: run orchestrator with --skip-deps (already installed above) ──
ENTRYPOINT ["bash", "pve-build-orchestrator.sh", "--skip-deps"]

# Default target (override with: docker run ... atd-builder --target qemu)
CMD ["--target", "all"]
