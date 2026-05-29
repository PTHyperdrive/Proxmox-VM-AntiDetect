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

# ===== Environment Detection =====
# Detect where we're running: GitHub Actions, Docker container, PVE host, or generic Debian.
# This MUST happen before any phase logic so every function can branch on ATD_ENV.
#   ci      = GitHub Actions (GITHUB_ACTIONS env var set)
#   docker  = Docker container (/.dockerenv exists, but not GH Actions)
#   pve     = Live Proxmox VE host (pveversion binary exists)
#   debian  = Generic Debian / unknown
_detect_environment() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        ATD_ENV="ci"
    elif [[ -f /.dockerenv ]] || grep -q 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then
        ATD_ENV="docker"
    elif command -v pveversion &>/dev/null; then
        ATD_ENV="pve"
    else
        ATD_ENV="debian"
    fi
    export ATD_ENV
}
_detect_environment

# ===== Defaults =====
TARGET="all"
PROFILE="${SCRIPT_DIR}/profiles/default.conf"
OUTPUT_DIR="${SCRIPT_DIR}/build-output"
JOBS="$(nproc 2>/dev/null || echo 4)"
RESUME_FROM=""
SKIP_DEPS=0
SKIP_CLEANUP=0
SKIP_KERNEL=0
ATD_DEBUG=0

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
  --debug               Force -j1 builds + raw output to debug log
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
        --skip-kernel)  SKIP_KERNEL=1; shift ;;
        --verbose)      ATD_LOG_LEVEL=4; shift ;;
        --debug)        ATD_DEBUG=1; JOBS=1; ATD_LOG_LEVEL=4; shift ;;
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

# ===== Helper: should we build this target? =====
# Respects --skip-kernel flag when TARGET=all
should_build_target() {
    local t="$1"
    if [[ "${TARGET}" == "${t}" ]]; then
        return 0
    fi
    if [[ "${TARGET}" == "all" ]]; then
        if [[ "${t}" == "kernel" ]] && (( SKIP_KERNEL )); then
            return 1
        fi
        return 0
    fi
    return 1
}

# ===== Inject ATD Signature into .deb package =====
# Creates a signature file + debhelper hook so the .deb installs
# /usr/share/proxmox-atd/<pkg>.sig on the target PVE host.
# This allows deploy scripts to detect patched packages.
inject_atd_signature() {
    local pkg_dir="$1"    # e.g. /tmp/atd-build/pve-qemu
    local pkg_name="$2"   # e.g. pve-qemu-kvm
    local sig_name="$3"   # e.g. qemu.sig

    local brand
    brand="$(atd_config_get "${PROFILE}" brand name)"
    brand="${brand:-ASUS}"

    local version="unknown"
    if [[ -f "${pkg_dir}/Makefile" ]]; then
        version=$(grep -oP '(?<=PACKAGE_VERSION\s=\s).*' "${pkg_dir}/Makefile" 2>/dev/null | head -1) || true
        [[ -z "${version}" ]] && version=$(grep -oP '(?<=PKGVER\s?=\s?).*' "${pkg_dir}/Makefile" 2>/dev/null | head -1) || true
    fi

    atd_info "Injecting ATD signature into ${pkg_name} ..."

    # 1) Create signature file
    cat > "${pkg_dir}/debian/atd-signature" <<SIGEOF
ATD_PACKAGE=${pkg_name}
ATD_VERSION=${version:-unknown}
ATD_BRAND=${brand}
ATD_BUILD_TS=${BUILD_TS}
ATD_BUILD_ID=atd-v1.0
ATD_BUILD_ENV=${ATD_ENV}
SIGEOF

    # 2) Append debhelper hook to debian/rules (execute_after_dh_install)
    #    This copies the sig file into the package tree during build.
    if ! grep -q 'proxmox-atd signature' "${pkg_dir}/debian/rules" 2>/dev/null; then
        cat >> "${pkg_dir}/debian/rules" <<RULEEOF

# --- proxmox-atd signature injection ---
execute_after_dh_install:
	mkdir -p debian/${pkg_name}/usr/share/proxmox-atd
	install -m 644 debian/atd-signature debian/${pkg_name}/usr/share/proxmox-atd/${sig_name}
RULEEOF
        atd_debug "Added execute_after_dh_install hook to debian/rules"
    else
        atd_skip "ATD signature hook already present in debian/rules"
    fi

    atd_ok "Signature injected: ${sig_name} (brand=${brand})"
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

    # -- Environment mode --
    case "${ATD_ENV}" in
        ci)
            atd_info "Environment: ${C_GREEN}GitHub Actions CI${C_RESET}"
            [[ -n "${GITHUB_RUN_ID:-}" ]] && atd_info "Run ID: ${GITHUB_RUN_ID}"
            [[ -n "${GITHUB_SHA:-}" ]]    && atd_info "Commit: ${GITHUB_SHA:0:8}"
            ;;
        docker)
            atd_info "Environment: ${C_GREEN}Docker Container${C_RESET}"
            ;;
        pve)
            atd_info "Environment: ${C_GREEN}Proxmox VE Host${C_RESET}"
            atd_info "PVE: $(pveversion 2>/dev/null || echo 'detected')"
            ;;
        debian)
            atd_info "Environment: ${C_YELLOW}Generic Debian${C_RESET}"
            atd_warn "PVE not detected -- building in generic Debian mode"
            ;;
    esac

    # -- Root check --
    # CI containers typically run as root already; PVE/Debian require sudo.
    if [[ "${EUID:-$(id -u)}" -ne 0 ]] && (( ! ATD_DRY_RUN )); then
        if [[ "${ATD_ENV}" == "ci" ]] || [[ "${ATD_ENV}" == "docker" ]]; then
            atd_warn "Running as non-root in ${ATD_ENV} -- some steps may fail"
        else
            atd_die "This script must be run as root (sudo)" 2
        fi
    fi

    # -- OS info --
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        atd_info "OS: ${PRETTY_NAME:-${ID} ${VERSION_ID}}"
    fi

    # -- Disk space (need ~30GB for full build, ~15GB minimum) --
    local avail_kb avail_gb
    avail_kb=$(df --output=avail "${SCRIPT_DIR}" 2>/dev/null | tail -1 | tr -d ' ')
    avail_gb=$(( avail_kb / 1024 / 1024 ))
    atd_info "Available disk: ${avail_gb}GB"
    if (( avail_gb < 15 )); then
        if [[ "${ATD_ENV}" == "ci" ]] || [[ "${ATD_ENV}" == "docker" ]]; then
            atd_warn "Low disk space in ${ATD_ENV} (${avail_gb}GB). Build may fail."
        else
            atd_die "Insufficient disk space. Need 15GB+, have ${avail_gb}GB" 3
        fi
    fi

    # -- RAM --
    local total_mb="unknown"
    if command -v free &>/dev/null; then
        total_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $2}') || true
    elif [[ -f /proc/meminfo ]]; then
        local mem_kb
        mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null) || true
        [[ -n "${mem_kb}" ]] && total_mb=$(( mem_kb / 1024 ))
    fi
    atd_info "RAM: ${total_mb}MB"

    # -- Validate profile --
    if [[ ! -f "${PROFILE}" ]]; then
        atd_die "Profile not found: ${PROFILE}" 2
    fi

    local brand
    brand="$(atd_config_get "${PROFILE}" brand name)"
    atd_info "Brand: ${brand:-ASUS}"

    atd_summary "Build Configuration" \
        "Environment" "${ATD_ENV}" \
        "Target"      "${TARGET}" \
        "Profile"     "$(basename "${PROFILE}")" \
        "Output"      "${OUTPUT_DIR}" \
        "Jobs"        "${JOBS}" \
        "Build ID"    "${BUILD_TS}" \
        "Log File"    "${ATD_LOG_FILE}"

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

    # ── Core dependency list (shared across all targets) ──
    local DEPS=(
        build-essential git devscripts meson quilt debhelper
        libacl1-dev libaio-dev libattr1-dev libcap-ng-dev
        libcurl4-gnutls-dev libepoxy-dev libfdt-dev libgbm-dev
        libgnutls28-dev libiscsi-dev libjpeg-dev libnuma-dev
        libpci-dev libpixman-1-dev librbd-dev libsdl1.2-dev
        libseccomp-dev libslirp-dev libspice-protocol-dev
        libspice-server-dev libsystemd-dev liburing-dev
        libusb-1.0-0-dev libusbredirparser-dev libvirglrenderer-dev
        libfuse3-dev
        python3-sphinx python3-sphinx-rtd-theme xfslibs-dev
        bc dosfstools iasl mtools nasm python3 python3-pexpect
        python3-venv python3-wheel check
        qemu-utils uuid-dev xorriso curl
    )

    # ── Environment-specific deps ──
    case "${ATD_ENV}" in
        pve)
            DEPS+=(libproxmox-backup-qemu0-dev)
            ;;
        ci)
            # CI container (ghcr.io/pthyperdrive/pve-docker9) already has PVE
            # repos configured -- install the PVE dev lib + jq for release logic
            DEPS+=(libproxmox-backup-qemu0-dev pve-qemu-kvm jq)
            ;;
        docker)
            # Docker build image has PVE repos; include PVE dev lib
            DEPS+=(libproxmox-backup-qemu0-dev jq)
            ;;
        debian)
            atd_info "Generic Debian: skipping PVE-specific packages"
            ;;
    esac

    # ── Target-specific deps ──
    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        DEPS+=(
            dh-python asciidoc-base bison dwarves flex
            libdw-dev libelf-dev libiberty-dev libslang2-dev
            lz4 python3-dev xmlto rsync gawk
        )
    fi
    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        DEPS+=(gcc-aarch64-linux-gnu gcc-riscv64-linux-gnu)
    fi

    atd_info "Installing ${#DEPS[@]} packages ..."
    run_cmd "apt-get update -qq"

    # ── Install strategy depends on environment ──
    case "${ATD_ENV}" in
        pve)
            # On a live PVE host the pve-apt-hook blocks any apt operation that
            # would transitively remove the proxmox-ve meta-package.  Dev libs
            # can trigger this as a false positive.  Temporarily divert the hook.
            local pve_hook="/usr/share/proxmox-ve/pve-apt-hook"
            local hook_diverted=0
            if [[ -f "${pve_hook}" ]]; then
                atd_info "Temporarily diverting pve-apt-hook ..."
                run_cmd "dpkg-divert --local --divert ${pve_hook}.disabled --rename ${pve_hook}"
                hook_diverted=1
            fi

            # Safety: restore hook even on failure
            _restore_pve_hook() {
                if (( hook_diverted )); then
                    dpkg-divert --local --rename --remove "${pve_hook}" 2>/dev/null || true
                fi
            }
            trap '_restore_pve_hook; cleanup_on_error' EXIT

            run_cmd "apt-get install -y -qq --no-remove ${DEPS[*]}"

            # Restore hook immediately after install
            if (( hook_diverted )); then
                atd_info "Restoring pve-apt-hook ..."
                run_cmd "dpkg-divert --local --rename --remove ${pve_hook}"
                hook_diverted=0
            fi
            trap cleanup_on_error EXIT
            ;;

        ci)
            # CI container -- no pve-apt-hook, no interactive prompts.
            # Use --allow-downgrades because the PVE Docker image may have
            # slightly newer/older versions pinned than the repo provides.
            run_cmd "apt-get install -y -qq --allow-downgrades ${DEPS[*]}"
            ;;

        docker)
            # Docker container -- clean environment, no hooks.
            run_cmd "apt-get install -y -qq ${DEPS[*]}"
            ;;

        debian)
            # Plain Debian -- straightforward install.
            run_cmd "apt-get install -y -qq ${DEPS[*]}"
            ;;
    esac

    atd_ok "Dependencies installed (env=${ATD_ENV})"
}

# ===== PHASE 3: CLONE =====
phase_clone() {
    CURRENT_PHASE="clone"
    atd_banner "PHASE 3/8" "CLONE -- Cloning Upstream Repositories"

    mkdir -p "${OUTPUT_DIR}"

    # QEMU
    if should_build_target qemu; then
        if [[ ! -d "${OUTPUT_DIR}/pve-qemu" ]]; then
            atd_step 1 3 "Cloning pve-qemu ..."
            run_cmd "git clone git://git.proxmox.com/git/pve-qemu.git ${OUTPUT_DIR}/pve-qemu"
            run_cmd "cd ${OUTPUT_DIR}/pve-qemu && git submodule update --init --recursive"
        else
            atd_skip "pve-qemu already cloned"
        fi
        # QEMU configure uses --disable-download; meson subprojects must be pre-fetched.
        atd_info "Downloading QEMU meson subprojects ..."
        local _meson_ok=0
        for _try in 1 2 3; do
            if (cd "${OUTPUT_DIR}/pve-qemu/qemu" && meson subprojects download 2>&1); then
                _meson_ok=1; break
            fi
            atd_warn "meson subprojects download attempt ${_try}/3 had errors, retrying ..."
            sleep 2
        done
        if (( ! _meson_ok )); then
            atd_warn "meson subprojects download failed after 3 attempts, trying direct git clone ..."
            if [[ ! -d "${OUTPUT_DIR}/pve-qemu/qemu/subprojects/keycodemapdb" ]] || \
               [[ ! -f "${OUTPUT_DIR}/pve-qemu/qemu/subprojects/keycodemapdb/data/keymaps.csv" ]]; then
                run_cmd "rm -rf ${OUTPUT_DIR}/pve-qemu/qemu/subprojects/keycodemapdb"
                run_cmd "git clone https://gitlab.com/qemu-project/keycodemapdb.git ${OUTPUT_DIR}/pve-qemu/qemu/subprojects/keycodemapdb || true"
            fi
            run_cmd "cd ${OUTPUT_DIR}/pve-qemu/qemu && meson subprojects download 2>&1 || true"
        fi
        # Inject ATD signature into QEMU package
        inject_atd_signature "${OUTPUT_DIR}/pve-qemu" "pve-qemu-kvm" "qemu.sig"
    fi

    # EDK2
    if should_build_target edk2; then
        if [[ ! -d "${OUTPUT_DIR}/pve-edk2-firmware" ]]; then
            atd_step 2 3 "Cloning pve-edk2-firmware ..."
            run_cmd "git clone git://git.proxmox.com/git/pve-edk2-firmware.git ${OUTPUT_DIR}/pve-edk2-firmware"
            run_cmd "cd ${OUTPUT_DIR}/pve-edk2-firmware && git submodule update --init --recursive"
        else
            atd_skip "pve-edk2-firmware already cloned"
        fi
        # Inject ATD signature into EDK2 package
        inject_atd_signature "${OUTPUT_DIR}/pve-edk2-firmware" "pve-edk2-firmware-ovmf" "edk2.sig"
    fi

    # Kernel
    if should_build_target kernel; then
        # Read kernel branch from profile (default: trixie-6.17 for PVE 9)
        local kernel_branch
        kernel_branch="$(atd_config_get "${PROFILE}" kvm kernel_branch 2>/dev/null)"
        kernel_branch="${kernel_branch:-trixie-6.17}"

        if [[ ! -d "${OUTPUT_DIR}/pve-kernel" ]]; then
            atd_step 3 3 "Cloning pve-kernel (branch: ${kernel_branch}) ..."
            run_cmd "git clone -b ${kernel_branch} git://git.proxmox.com/git/pve-kernel.git ${OUTPUT_DIR}/pve-kernel"
            run_cmd "cd ${OUTPUT_DIR}/pve-kernel && git submodule update --init --recursive --force"
        else
            atd_skip "pve-kernel already cloned"
        fi

        # Newer pve-kernel branches (trixie+) use debian/control.in with template
        # variables (@KVNAME@, @KVMAJMIN@, @ARCH@). The Makefile generates the
        # real debian/control inside its BUILD_DIR, but we need a valid one at
        # the top level for mk-build-deps to work.
        if [[ ! -f "${OUTPUT_DIR}/pve-kernel/debian/control" ]] && \
           [[ -f "${OUTPUT_DIR}/pve-kernel/debian/control.in" ]]; then
            atd_info "Generating debian/control from control.in ..."
            local _kdir="${OUTPUT_DIR}/pve-kernel"
            local _kmaj _kmin _kpatch _krel _kvmajmin _kvname _extraversion _arch
            _kmaj=$(grep -oP '(?<=^KERNEL_MAJ=)\S+' "${_kdir}/Makefile" | head -1)
            _kmin=$(grep -oP '(?<=^KERNEL_MIN=)\S+' "${_kdir}/Makefile" | head -1)
            _kpatch=$(grep -oP '(?<=^KERNEL_PATCHLEVEL=)\S+' "${_kdir}/Makefile" | head -1)
            _krel=$(grep -oP '(?<=^KREL=)\S+' "${_kdir}/Makefile" | head -1)
            _kvmajmin="${_kmaj}.${_kmin}"
            _extraversion="-${_krel}-pve"
            _kvname="${_kmaj}.${_kmin}.${_kpatch}${_extraversion}"
            _arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
            atd_debug "Kernel vars: KVMAJMIN=${_kvmajmin} KVNAME=${_kvname} ARCH=${_arch}"
            sed -e "s/@KVNAME@/${_kvname}/g" \
                -e "s/@KVMAJMIN@/${_kvmajmin}/g" \
                -e "s/@ARCH@/${_arch}/g" \
                -e "s/@GRUB_RECOMMENDS@/grub-pc | grub-efi-amd64 | grub-efi-ia32 | grub-efi-arm64/g" \
                "${_kdir}/debian/control.in" > "${_kdir}/debian/control"
            atd_ok "Generated debian/control (kernel ${_kvname})"
        fi

        # Fix upstream Makefile bug: the grouped target rule (&:) is missing
        # $(LINUX_TOOLS_DBG_DEB) and $(SIGNED_TEMPLATE_DEB) from the recipe list,
        # even though they're in $(DEBS). dpkg-buildpackage produces them but Make
        # doesn't know, causing "No rule to make target" errors.
        local _mk="${OUTPUT_DIR}/pve-kernel/Makefile"
        if [[ -f "${_mk}" ]] && grep -q 'LINUX_TOOLS_DEB) $(HDR_DEB) $(DST_DEB) &:' "${_mk}"; then
            atd_info "Patching Makefile grouped target rule (upstream bug) ..."
            sed -i 's/\$(LINUX_TOOLS_DEB) \$(HDR_DEB) \$(DST_DEB) &:/$(LINUX_TOOLS_DEB) $(LINUX_TOOLS_DBG_DEB) $(HDR_DEB) $(DST_DEB) $(SIGNED_TEMPLATE_DEB) \&:/' "${_mk}"
            atd_debug "Added LINUX_TOOLS_DBG_DEB and SIGNED_TEMPLATE_DEB to grouped target"
        fi

        # Fix missing signing-template stubs (needed by debian/rules install phase).
        # The trixie-6.14 branch expects debian/signing-template/ with several files
        # for secure-boot signing. We don't sign, so create minimal stubs.
        local _st="${OUTPUT_DIR}/pve-kernel/debian/signing-template"
        if [[ -d "${OUTPUT_DIR}/pve-kernel/debian" ]] && [[ ! -f "${_st}/rules" ]]; then
            atd_info "Creating signing-template stubs (not signing) ..."
            mkdir -p "${_st}/source"
            # Minimal debian/rules for the signing template
            cat > "${_st}/rules" <<'STRULES'
#!/usr/bin/make -f
%:
	dh $@
STRULES
            chmod +x "${_st}/rules"
            # Minimal control file
            cat > "${_st}/control" <<'STCONTROL'
Source: proxmox-kernel-signed
Section: kernel
Priority: optional
Maintainer: Proxmox Support Team <support@proxmox.com>
Build-Depends: debhelper-compat (= 13)
Standards-Version: 4.6.2

Package: proxmox-kernel-signed
Architecture: amd64
Description: Proxmox kernel (signed stub)
STCONTROL
            # Minimal changelog
            cat > "${_st}/changelog" <<STCLOG
proxmox-kernel-signed (1.0) stable; urgency=low

  * Stub package for unsigned build

 -- ATD Builder <atd@localhost>  $(date -R)
STCLOG
            # Empty maintainer scripts
            for _script in prerm postrm postinst; do
                cat > "${_st}/${_script}" <<STSCRIPT
#!/bin/sh
exit 0
STSCRIPT
                chmod +x "${_st}/${_script}"
            done
            # SOURCE file
            echo "proxmox-kernel" > "${_st}/SOURCE"
            # source/format
            echo "3.0 (native)" > "${_st}/source/format"
            # files.json (lists files to sign — empty for unsigned builds)
            echo '[]' > "${_st}/files.json"
            atd_debug "Created signing-template stubs"
        fi
    fi

    # Install mk-build-deps for each
    if should_build_target qemu; then
        atd_info "Installing QEMU build-deps ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu && yes | mk-build-deps --install 2>/dev/null || true"
    fi
    if should_build_target edk2; then
        atd_info "Installing EDK2 build-deps ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-edk2-firmware && yes | mk-build-deps --install 2>/dev/null || true"
    fi
    if should_build_target kernel; then
        atd_info "Installing Kernel build-deps ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-kernel && yes | mk-build-deps --install 2>/dev/null || true"
        if [[ -d "${OUTPUT_DIR}/pve-kernel/submodules/zfsonlinux" ]]; then
            run_cmd "cd ${OUTPUT_DIR}/pve-kernel/submodules/zfsonlinux && mk-build-deps --install 2>/dev/null || true"
        fi
    fi

    atd_ok "Repositories cloned and build-deps installed"
}

# ===== PHASE 4: PATCH =====
phase_patch() {
    CURRENT_PHASE="patch"
    atd_banner "PHASE 4/8" "PATCH -- Applying Anti-Detection Modifications"

    # Build common patcher arguments
    local common_args=(
        --profile "${PROFILE}"
        --build-dir "${OUTPUT_DIR}"
        --no-backup
        --skip-deps
        --skip-clone
        --skip-build
        --skip-cleanup
    )
    if (( ATD_DRY_RUN )); then
        common_args+=(--dry-run)
    fi
    if (( ATD_LOG_LEVEL >= 4 )); then
        common_args+=(--verbose)
    fi

    # Always iterate individual targets instead of passing "all" to the patcher.
    # This avoids the patcher dying on missing dirs for targets we didn't clone,
    # and keeps source dir overrides clean (each invocation gets only its own).
    local targets_to_patch=()
    if [[ "${TARGET}" == "all" ]]; then
        should_build_target qemu   && targets_to_patch+=(qemu)
        should_build_target edk2   && targets_to_patch+=(edk2)
        should_build_target kernel && targets_to_patch+=(kernel)
    else
        targets_to_patch=("${TARGET}")
    fi

    for ptarget in "${targets_to_patch[@]}"; do
        local patcher_args=("${common_args[@]}" --target "${ptarget}")

        # Pass source dir overrides for the targets being patched
        if [[ "${ptarget}" == "qemu" ]]; then
            if [[ ! -d "${OUTPUT_DIR}/pve-qemu/qemu" ]]; then
                atd_err "QEMU source not found: ${OUTPUT_DIR}/pve-qemu/qemu"
                atd_die "Run the clone phase first (--resume-from clone)" 2
            fi
            patcher_args+=(--qemu-dir "${OUTPUT_DIR}/pve-qemu/qemu")
        fi
        if [[ "${ptarget}" == "edk2" ]]; then
            if [[ ! -d "${OUTPUT_DIR}/pve-edk2-firmware/edk2" ]]; then
                atd_err "EDK2 source not found: ${OUTPUT_DIR}/pve-edk2-firmware/edk2"
                atd_die "Run the clone phase first (--resume-from clone)" 2
            fi
            patcher_args+=(--edk2-dir "${OUTPUT_DIR}/pve-edk2-firmware/edk2")
        fi
        if [[ "${ptarget}" == "kernel" ]]; then
            # Auto-detect kernel source directory.
            # PVE kernel repos use submodules/ubuntu-kernel, but the name may
            # vary across branches. Fall back to the first directory under submodules/.
            local _kernel_src=""
            if [[ -d "${OUTPUT_DIR}/pve-kernel/submodules/ubuntu-kernel" ]]; then
                _kernel_src="${OUTPUT_DIR}/pve-kernel/submodules/ubuntu-kernel"
            else
                # Try to find any kernel source tree under submodules/
                _kernel_src="$(find "${OUTPUT_DIR}/pve-kernel/submodules" -maxdepth 1 -type d -name '*kernel*' 2>/dev/null | head -1)"
                if [[ -z "${_kernel_src}" ]]; then
                    _kernel_src="$(find "${OUTPUT_DIR}/pve-kernel/submodules" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
                fi
            fi
            if [[ -z "${_kernel_src}" ]] || [[ ! -d "${_kernel_src}" ]]; then
                atd_err "Kernel source submodule not found under: ${OUTPUT_DIR}/pve-kernel/submodules/"
                atd_err "Available contents:"
                ls -la "${OUTPUT_DIR}/pve-kernel/submodules/" 2>/dev/null | while read -r _l; do atd_err "  ${_l}"; done
                atd_die "Kernel submodule may not have been initialized. Re-run clone phase." 2
            fi
            atd_info "Kernel source directory: ${_kernel_src}"
            patcher_args+=(--kernel-dir "${_kernel_src}")
        fi

        bash "${SCRIPT_DIR}/atd-patcher.sh" "${patcher_args[@]}"
    done

    atd_ok "Patching phase complete"
}

# ===== PHASE 5: BUILD =====
phase_build() {
    CURRENT_PHASE="build"
    atd_banner "PHASE 5/8" "BUILD -- Compiling Packages"

    # Debug mode: raw output to a log file for easy error diagnosis
    local debug_log=""
    if (( ATD_DEBUG )); then
        debug_log="${OUTPUT_DIR}/atd-debug-build-${BUILD_TS}.log"
        atd_info "DEBUG MODE: -j1, raw output → ${debug_log}"
    fi

    atd_timer_start

    if should_build_target qemu; then
        atd_separator "Building pve-qemu-kvm"
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu && make clean 2>/dev/null || true"
        if (( ATD_DEBUG )); then
            ( cd "${OUTPUT_DIR}/pve-qemu" && make -j1 2>&1 ) | tee -a "${debug_log}"
            local rc=${PIPESTATUS[0]}
            if (( rc != 0 )); then
                atd_err "QEMU build failed (debug log: ${debug_log})"
                return ${rc}
            fi
        else
            run_cmd "cd ${OUTPUT_DIR}/pve-qemu && make -j${JOBS}"
        fi
        atd_ok "QEMU build complete"
    fi

    if should_build_target edk2; then
        atd_separator "Building pve-edk2-firmware-ovmf"

        # If we just built QEMU (target=all), install the freshly-built .deb
        # so EDK2's dpkg-checkbuilddeps finds pve-qemu-kvm and firmware tests
        # use the patched QEMU binary.
        if [[ "${TARGET}" == "all" ]] && ! (( SKIP_KERNEL )) || [[ "${TARGET}" == "all" ]]; then
            local qemu_deb
            qemu_deb="$(find "${OUTPUT_DIR}/pve-qemu" -maxdepth 1 -name 'pve-qemu-kvm_*.deb' ! -name '*dbgsym*' 2>/dev/null | head -1)"
            if [[ -n "${qemu_deb}" ]]; then
                atd_info "Installing freshly-built QEMU .deb for EDK2 build ..."
                run_cmd "dpkg -i '${qemu_deb}' 2>/dev/null || apt-get install -f -y -qq 2>/dev/null || true"
            fi
        fi

        # EDK2 debian/rules spawns multi-arch builds that share BaseTools.
        # Top-level -jN causes race conditions. Let each arch handle parallelism.
        run_cmd "cd ${OUTPUT_DIR}/pve-edk2-firmware && make"
        atd_ok "EDK2 build complete"
    fi

    if should_build_target kernel; then
        atd_separator "Building pve-kernel"
        if (( ATD_DEBUG )); then
            atd_info "Building kernel with make -j1 (debug mode) ..."
            ( cd "${OUTPUT_DIR}/pve-kernel" && make -j1 2>&1 ) | tee -a "${debug_log}"
            local rc=${PIPESTATUS[0]}
            if (( rc != 0 )); then
                atd_err "Kernel build failed. Last 50 error lines:"
                grep -iE 'error:|fatal:|undefined|implicit|undeclared|redefinition|conflict' "${debug_log}" | tail -50 | while read -r line; do
                    atd_err "  ${line}"
                done
                atd_err "Full debug log: ${debug_log}"
                return ${rc}
            fi
        else
            run_cmd "cd ${OUTPUT_DIR}/pve-kernel && make -j${JOBS}"
        fi
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

    if should_build_target qemu; then
        run_cmd "find ${OUTPUT_DIR}/pve-qemu -name '*.deb' ! -name '*dbgsym*' -exec cp {} ${artifacts}/ \\;"
        run_cmd "cp ${OUTPUT_DIR}/pve-qemu/qemu-autoGenPatch.patch ${artifacts}/ 2>/dev/null || true"
    fi

    if should_build_target edk2; then
        run_cmd "find ${OUTPUT_DIR}/pve-edk2-firmware -name '*.deb' ! -name '*legacy*' ! -name '*aarch64*' ! -name '*deps*' ! -name '*riscv*' -exec cp {} ${artifacts}/ \\;"
        run_cmd "cp ${OUTPUT_DIR}/pve-edk2-firmware/edk2-autoGenPatch.patch ${artifacts}/ 2>/dev/null || true"
    fi

    if should_build_target kernel; then
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

    if should_build_target qemu; then
        if ls "${artifacts}"/pve-qemu-kvm_*.deb 1>/dev/null 2>&1; then
            atd_ok "QEMU .deb package found"
        else
            atd_err "QEMU .deb package NOT found"
            (( errors++ ))
        fi
    fi

    if should_build_target edk2; then
        if ls "${artifacts}"/pve-edk2-firmware-ovmf_*.deb 1>/dev/null 2>&1; then
            atd_ok "EDK2 .deb package found"
        else
            atd_err "EDK2 .deb package NOT found"
            (( errors++ ))
        fi
    fi

    if should_build_target kernel; then
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

    if should_build_target qemu; then
        atd_info "Resetting pve-qemu ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu/qemu && git checkout . 2>/dev/null || true"
        run_cmd "cd ${OUTPUT_DIR}/pve-qemu && git checkout . 2>/dev/null || true"
    fi

    if should_build_target edk2; then
        atd_info "Resetting pve-edk2-firmware ..."
        run_cmd "cd ${OUTPUT_DIR}/pve-edk2-firmware/edk2 && git checkout . 2>/dev/null || true"
    fi

    if should_build_target kernel; then
        atd_info "Resetting pve-kernel ..."
        # Auto-detect kernel submodule dir (same logic as phase_patch)
        local _ksrc="${OUTPUT_DIR}/pve-kernel/submodules/ubuntu-kernel"
        if [[ ! -d "${_ksrc}" ]]; then
            _ksrc="$(find "${OUTPUT_DIR}/pve-kernel/submodules" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
        fi
        if [[ -n "${_ksrc}" ]] && [[ -d "${_ksrc}" ]]; then
            run_cmd "cd ${_ksrc} && git checkout . 2>/dev/null || true"
        fi
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
