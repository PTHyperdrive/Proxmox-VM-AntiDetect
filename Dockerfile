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

# ── APT timeout & retry hardening (prevents 10min+ hangs) ──
RUN echo 'Acquire::http::Timeout "30";' > /etc/apt/apt.conf.d/99timeout && \
    echo 'Acquire::https::Timeout "30";' >> /etc/apt/apt.conf.d/99timeout && \
    echo 'Acquire::Retries "3";' >> /etc/apt/apt.conf.d/99timeout && \
    echo 'APT::Update::Post-Invoke-Success { "true"; };' >> /etc/apt/apt.conf.d/99timeout

# ── Add Proxmox no-subscription repository ──
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
    ca-certificates curl gnupg wget procps && \
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
    build-essential git devscripts meson quilt debhelper lintian \
    # QEMU dev libs
    libacl1-dev libaio-dev libattr1-dev libcap-ng-dev \
    libcurl4-gnutls-dev libepoxy-dev libfdt-dev libgbm-dev \
    libgnutls28-dev libiscsi-dev libjpeg-dev libnuma-dev \
    libpci-dev libpixman-1-dev librbd-dev libsdl1.2-dev \
    libseccomp-dev libslirp-dev libspice-protocol-dev \
    libspice-server-dev libsystemd-dev liburing-dev \
    libusb-1.0-0-dev libusbredirparser-dev libvirglrenderer-dev \
    libfuse3-dev \
    python3-sphinx python3-sphinx-rtd-theme xfslibs-dev \
    # Common tools
    bc dosfstools iasl mtools nasm python3 python3-pexpect \
    python3-venv python3-wheel \
    uuid-dev xorriso curl jq zip check \
    # Kernel deps (6.17+ requires Rust toolchain)
    dh-python asciidoc-base bison dwarves flex \
    libdw-dev libelf-dev libiberty-dev libslang2-dev \
    lz4 python3-dev xmlto rsync gawk \
    cpio kmod zstd \
    bindgen rustc rust-src rustfmt rust-clippy \
    # EDK2 cross-compilers + runtime deps
    gcc-aarch64-linux-gnu gcc-riscv64-linux-gnu \
    python3-virt-firmware \
    # PVE-specific (pve-qemu-kvm needed by EDK2 build to test-run firmware)
    libproxmox-backup-qemu0-dev pve-qemu-kvm \
    && rm -rf /var/lib/apt/lists/*

# ── Working directory ──
WORKDIR /build

# ── Copy source tree ──
COPY . /build/

# ── Make scripts executable ──
RUN chmod +x pve-build-orchestrator.sh atd-patcher.sh lib/atd-styles.sh \
    docker-entrypoint.sh && \
    chmod +x patches/*.patch.sh 2>/dev/null || true

# ── Entrypoint: builds in container-internal dir, copies artifacts to mount ──
ENTRYPOINT ["bash", "docker-entrypoint.sh"]

# Default target (override with: docker run ... atd-builder --target qemu)
CMD ["--target", "all"]
