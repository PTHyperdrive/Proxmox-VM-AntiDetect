#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Unified Build Orchestrator
#  Consolidated build pipeline for QEMU, EDK2, and Kernel
#
#  Usage: ./pve-build-orchestrator.sh [options]
#    --target <t>        qemu|edk2|kernel|all (default: all)
#    --profile <file>    Patcher config profile
#    --output <dir>      Output directory (default: ./build-output)
#    --jobs <n>          Parallel build jobs (default: nproc)
#    --dry-run           Print all commands without executing
#    --resume-from <ph>  Resume from: deps|clone|patch|build|package|verify
#    --skip-deps         Skip dependency installation
#    --skip-cleanup      Skip post-build git cleanup
#    --verbose           Debug-level logging
#    --help              Show this help
#
#  REMOTE EXECUTION ONLY -- run on your Proxmox server
#  Part of: https://github.com/proxmox-atd
# ---------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/atd-styles.sh"

# ===== Defaults =====
TARGET="all"
PROFILE="${SCRIPT_DIR}/profiles/default.conf"
OUTPUT_DIR="${SCRIPT_DIR}/build-output"
JOBS="$(nproc 2>/dev/null || echo 4)"
RESUME_FROM=""
SKIP_DEPS=0
SKIP_CLEANUP=0

# ===== Build timestamp =====
BUILD_TS="$(date +%Y%m%d-%H%M%S)"
ATD_LOG_FILE="${SCRIPT_DIR}/atd-build-${BUILD_TS}.log"

# ===== Phase tracking =====
PHASES=("preflight" "deps" "clone" "patch" "build" "package" "verify" "cleanup")
CURRENT_PHASE=""

# ===== Usage =====
usage() {
    cat <<EOF
proxmox-atd Unified Build Orchestrator

Usage: $(basename "$0") [options]

Targets:
  qemu       Build patched pve-qemu-kvm .deb package
  edk2       Build patched pve-edk2-firmware-ovmf .deb package
  kernel     Build patched pve-kernel .deb and .ko modules
  all        Build all targets (default)

Options:
  --target <target>     Build target (default: all)
  --profile <file>      Patcher config profile (default: profiles/default.conf)
  --output <dir>        Artifact output directory (default: ./build-output)
  --jobs <n>            Parallel make jobs (default: $(nproc))
  --dry-run             Preview all commands without executing
  --resume-from <phase> Skip phases before this one
  --skip-deps           Skip dependency installation
  --skip-cleanup        Keep build directories after completion
  --verbose             Enable debug logging
  --help                Show this help

Phases: ${PHASES[*]}

Examples:
  # Full build on PVE server
  sudo ./pve-build-orchestrator.sh --target all

  # QEMU-only with custom profile, 8 parallel jobs
  sudo ./pve-build-orchestrator.sh --target qemu \\
       --profile profiles/example-intel-desktop.conf --jobs 8

  # Resume a failed build from the build phase
  sudo ./pve-build-orchestrator.sh --target all --resume-from build
EOF
    exit 0
}

# ===== Parse Arguments =====
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)       TARGET="$2"; shift 2 ;;
        --profile)      PROFILE="$2"; shift 2 ;;
        --output)       OUTPUT_DIR="$2"; shift 2 ;;
        --jobs)         JOBS="$2"; shift 2 ;;
        --dry-run)      ATD_DRY_RUN=1; shift ;;
        --resume-from)  RESUME_FROM="$2"; shift 2 ;;
        --skip-deps)    SKIP_DEPS=1; shift ;;
        --skip-cleanup) SKIP_CLEANUP=1; shift ;;
        --verbose)      ATD_LOG_LEVEL=4; shift ;;
        --help)         usage ;;
        *)              atd_die "Unknown option: $1" 2 ;;
    esac
done

# ===== Should we run this phase? =====
should_run_phase() {
    local phase="$1"
    if [[ -z "${RESUME_FROM}" ]]; then
        return 0  # Run all phases
    fi
    local found=0
    for p in "${PHASES[@]}"; do
        if [[ "${p}" == "${RESUME_FROM}" ]]; then
            found=1
        fi
        if (( found )) && [[ "${p}" == "${phase}" ]]; then
            return 0
        fi
    done
    return 1
}

run_cmd() {
    if (( ATD_DRY_RUN )); then
        atd_dry "$*"
    else
        eval "$@"
    fi
}

# ===== Trap for cleanup on error =====
cleanup_on_error() {
    local exit_code=$?
    if (( exit_code != 0 )); then
        atd_err "Build failed during phase: ${CURRENT_PHASE}"
        atd_err "Log file: ${ATD_LOG_FILE}"
        atd_err "To resume: $(basename "$0") --target ${TARGET} --resume-from ${CURRENT_PHASE}"
    fi
}
trap cleanup_on_error EXIT

# ===== PHASE 1: PREFLIGHT =====
phase_preflight() {
    CURRENT_PHASE="preflight"
    atd_banner "PHASE 1/8" "PREFLIGHT -- Environment Validation"

    # Check root
    if [[ "${EUID:-$(id -u)}" -ne 0 ]] && (( ! ATD_DRY_RUN )); then
        atd_die "This script must be run as root (sudo)" 2
    fi

    # Check OS
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        atd_info "OS: ${PRETTY_NAME:-${ID} ${VERSION_ID}}"
    fi

    # Check for PVE
    if command -v pveversion &>/dev/null; then
        atd_info "PVE: $(pveversion 2>/dev/null || echo 'detected')"
    else
        atd_warn "PVE not detected -- building in generic Debian mode"
    fi

    # Check disk space (need ~30GB for full build)
    local avail_kb
    avail_kb=$(df --output=avail "${SCRIPT_DIR}" 2>/dev/null | tail -1 | tr -d ' ')
    local avail_gb=$(( avail_kb / 1024 / 1024 ))
    atd_info "Available disk: ${avail_gb}GB"
    if (( avail_gb < 15 )); then
        atd_die "Insufficient disk space. Need 15GB+, have ${avail_gb}GB" 3
    fi

    # Check RAM
    local total_mb
    total_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
    atd_info "RAM: ${total_mb:-unknown}MB"

    # Validate profile
    if [[ ! -f "${PROFILE}" ]]; then
        atd_die "Profile not found: ${PROFILE}" 2
    fi

    local brand
    brand="$(atd_config_get "${PROFILE}" brand name)"
    atd_info "Brand: ${brand:-ASUS}"

    atd_summary "Build Configuration" \
        "Target"     "${TARGET}" \
        "Profile"    "$(basename "${PROFILE}")" \
        "Output"     "${OUTPUT_DIR}" \
        "Jobs"       "${JOBS}" \
        "Build ID"   "${BUILD_TS}" \
        "Log File"   "${ATD_LOG_FILE}"

    atd_ok "Preflight checks passed"
}

# ===== PHASE 2: DEPENDENCIES =====
phase_deps() {
    CURRENT_PHASE="deps"
    atd_banner "PHASE 2/8" "DEPS -- Installing Build Dependencies"

    if (( SKIP_DEPS )); then
        atd_skip "Dependency installation skipped (--skip-deps)"
        return 0
    fi

    # Unified dependency list (deduped across all three build scripts)
    local DEPS=(
        build-essential git devscripts meson quilt
        libacl1-dev libaio-dev libattr1-dev libcap-ng-dev
        libcurl4-gnutls-dev libepoxy-dev libfdt-dev libgbm-dev
        libgnutls28-dev libiscsi-dev libjpeg-dev libnuma-dev
        libpci-dev libpixman-1-dev librbd-dev libsdl1.2-dev
        libseccomp-dev libslirp-dev libspice-protocol-dev
        libspice-server-dev libsystemd-dev liburing-dev
        libusb-1.0-0-dev libusbredirparser-dev libvirglrenderer-dev
        python3-sphinx python3-sphinx-rtd-theme xfslibs-dev
        bc dosfstools iasl mtools nasm python3 python3-pexpect
        qemu-utils uuid-dev xorriso curl
    )

    # PVE-specific deps
    if command -v pveversion &>/dev/null; then
        DEPS+=(libproxmox-backup-qemu0-dev)
    fi

    # Kernel-specific deps
    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        DEPS+=(
            dh-python asciidoc-base bison dwarves flex
            libdw-dev libelf-dev libiberty-dev libslang2-dev
            lz4 python3-dev xmlto rsync gawk
        )
    fi

    # EDK2-specific deps
    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        DEPS+=(gcc-aarch64-linux-gnu gcc-riscv64-linux-gnu)
    fi

    atd_info "Installing ${#DEPS[@]} packages ..."
    run_cmd "apt-get update -qq"
    run_cmd "apt-get install -y -qq ${DEPS[*]}"

    atd_ok "Dependencies installed"
}

# ===== PHASE 3: CLONE =====
phase_clone() {
    CURRENT_PHASE="clone"
    atd_banner "PHASE 3/8" "CLONE -- Cloning Upstream Repositories"

    mkdir -p "${OUTPUT_DIR}"

    # QEMU
    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        if [[ ! -d "${OUTPUT_DIR}/pve-qemu" ]]; then
            atd_step 1 3 "Cloning pve-qemu ..."
            run_cmd "git clone git://git.proxmox.com/git/pve-qemu.git ${OUTPUT_DIR}/pve-qemu"
            run_cmd "cd ${OUTPUT_DIR}/pve-qemu && git submodule update --init --recursive"
        else
            atd_skip "pve-qemu already cloned"
        fi
    fi

    # EDK2
    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        if [[ ! -d "${OUTPUT_DIR}/pve-edk2-firmware" ]]; then
            atd_step 2 3 "Cloning pve-edk2-firmware ..."
            run_cmd "git clone git://git.proxmox.com/git/pve-edk2-firmware.git ${OUTPUT_DIR}/pve-edk2-firmware"
            run_cmd "cd ${OUTPUT_DIR}/pve-edk2-firmware && git submodule update --init --recursive"
        else
            atd_skip "pve-edk2-firmware already cloned"
        fi
    fi

    # Kernel
    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        if [[ ! -d "${OUTPUT_DIR}/pve-kernel" ]]; then
            atd_step 3 3 "Cloning pve-kernel ..."
            run_cmd "git clone git://git.proxmox.com/git/pve-kernel.git ${OUTPUT_DIR}/pve-kernel"
            run_cmd "cd ${OUTPUT_DIR}/pve-kernel && git submodule update --init --recursive --force"
        else
            atd_skip "pve-kernel already cloned"
        fi
    fi

    # Install mk-build-deps for each
    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Installing QEMU build-deps ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu && yes | mk-build-deps --install 2>/dev/null || true"
    fi
    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Installing EDK2 build-deps ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-edk2-firmware && yes | mk-build-deps --install 2>/dev/null || true"
    fi
    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Installing Kernel build-deps ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-kernel && yes | mk-build-deps --install 2>/dev/null || true"
        run_cmd "cd ${OUTPUT_DIR}/pve-kernel/submodules/zfsonlinux && mk-build-deps --install 2>/dev/null || true"
    fi

    atd_ok "Repositories cloned and build-deps installed"
}

# ===== PHASE 4: PATCH =====
phase_patch() {
    CURRENT_PHASE="patch"
    atd_banner "PHASE 4/8" "PATCH -- Applying Anti-Detection Modifications"

    local patcher_args=(
        --profile "${PROFILE}"
        --target "${TARGET}"
        --build-dir "${OUTPUT_DIR}"
        --no-backup
        --skip-deps
        --skip-clone
        --skip-build
        --skip-cleanup
    )

    if (( ATD_DRY_RUN )); then
        patcher_args+=(--dry-run)
    fi
    if (( ATD_LOG_LEVEL >= 4 )); then
        patcher_args+=(--verbose)
    fi

    bash "${SCRIPT_DIR}/atd-patcher.sh" "${patcher_args[@]}"

    atd_ok "Patching phase complete"
}

# ===== PHASE 5: BUILD =====
phase_build() {
    CURRENT_PHASE="build"
    atd_banner "PHASE 5/8" "BUILD -- Compiling Packages"

    atd_timer_start

    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_separator "Building pve-qemu-kvm"
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu && make clean 2>/dev/null || true"
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu && make -j${JOBS}"
        atd_ok "QEMU build complete"
    fi

    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_separator "Building pve-edk2-firmware-ovmf"
        run_cmd "cd ${OUTPUT_DIR}/pve-edk2-firmware && make -j${JOBS}"
        atd_ok "EDK2 build complete"
    fi

    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_separator "Building pve-kernel"
        run_cmd "cd ${OUTPUT_DIR}/pve-kernel && make -j${JOBS}"
        atd_ok "Kernel build complete"
    fi

    atd_timer_stop "Build phase"
}

# ===== PHASE 6: PACKAGE =====
phase_package() {
    CURRENT_PHASE="package"
    atd_banner "PHASE 6/8" "PACKAGE -- Collecting Artifacts"

    local artifacts="${OUTPUT_DIR}/artifacts"
    run_cmd "mkdir -p ${artifacts}"

    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        run_cmd "find ${OUTPUT_DIR}/pve-qemu -name '*.deb' ! -name '*dbgsym*' -exec cp {} ${artifacts}/ \\;"
        run_cmd "cp ${OUTPUT_DIR}/qemu-autoGenPatch.patch ${artifacts}/ 2>/dev/null || true"
    fi

    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        run_cmd "find ${OUTPUT_DIR}/pve-edk2-firmware -name '*.deb' ! -name '*legacy*' ! -name '*aarch64*' ! -name '*deps*' ! -name '*riscv*' -exec cp {} ${artifacts}/ \\;"
        run_cmd "cp ${OUTPUT_DIR}/edk2-autoGenPatch.patch ${artifacts}/ 2>/dev/null || true"
    fi

    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        run_cmd "find ${OUTPUT_DIR}/pve-kernel -name '*.deb' -exec cp {} ${artifacts}/ \\;"
        run_cmd "find ${OUTPUT_DIR}/pve-kernel -name 'kvm*.ko' -exec cp {} ${artifacts}/ \\;"
    fi

    # Copy ACPI tables
    run_cmd "cp ${SCRIPT_DIR}/pve-emu-realpc-main/*.aml ${artifacts}/ 2>/dev/null || true"

    if (( ! ATD_DRY_RUN )); then
        atd_info "Artifacts:"
        ls -lh "${artifacts}/" 2>/dev/null | while read -r line; do
            atd_info "  ${line}"
        done
    fi

    atd_ok "Artifacts collected in ${artifacts}/"
}

# ===== PHASE 7: VERIFY =====
phase_verify() {
    CURRENT_PHASE="verify"
    atd_banner "PHASE 7/8" "VERIFY -- Post-Build Validation"

    local artifacts="${OUTPUT_DIR}/artifacts"
    local errors=0

    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        if ls "${artifacts}"/pve-qemu-kvm_*.deb 1>/dev/null 2>&1; then
            atd_ok "QEMU .deb package found"
        else
            atd_err "QEMU .deb package NOT found"
            (( errors++ ))
        fi
    fi

    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        if ls "${artifacts}"/pve-edk2-firmware-ovmf_*.deb 1>/dev/null 2>&1; then
            atd_ok "EDK2 .deb package found"
        else
            atd_err "EDK2 .deb package NOT found"
            (( errors++ ))
        fi
    fi

    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        if ls "${artifacts}"/pve-kernel-*.deb 1>/dev/null 2>&1 || \
           ls "${artifacts}"/kvm.ko 1>/dev/null 2>&1; then
            atd_ok "Kernel artifacts found"
        else
            atd_err "Kernel artifacts NOT found"
            (( errors++ ))
        fi
    fi

    if (( errors > 0 )); then
        atd_err "Verification failed with ${errors} missing artifact(s)"
        return 6
    fi

    atd_ok "All expected artifacts verified"
}

# ===== PHASE 8: CLEANUP =====
phase_cleanup() {
    CURRENT_PHASE="cleanup"
    atd_banner "PHASE 8/8" "CLEANUP -- Restoring Source Trees"

    if (( SKIP_CLEANUP )); then
        atd_skip "Cleanup skipped (--skip-cleanup)"
        return 0
    fi

    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Resetting pve-qemu ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu/qemu && git checkout . 2>/dev/null || true"
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu && git checkout . 2>/dev/null || true"
    fi

    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Resetting pve-edk2-firmware ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-edk2-firmware/edk2 && git checkout . 2>/dev/null || true"
    fi

    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Resetting pve-kernel ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-kernel/submodules/ubuntu-kernel && git checkout . 2>/dev/null || true"
    fi

    atd_ok "Cleanup complete"
}

# ===== MAIN EXECUTION =====
atd_banner "BUILD" "proxmox-atd Unified Build Orchestrator v1.0"
atd_timer_start

should_run_phase preflight && phase_preflight
should_run_phase deps      && phase_deps
should_run_phase clone     && phase_clone
should_run_phase patch     && phase_patch
should_run_phase build     && phase_build
should_run_phase package   && phase_package
should_run_phase verify    && phase_verify
should_run_phase cleanup   && phase_cleanup

atd_timer_stop "Full build pipeline"
atd_banner "COMPLETE" "Build finished -- artifacts in ${OUTPUT_DIR}/artifacts/"

trap - EXIT
exit 0
