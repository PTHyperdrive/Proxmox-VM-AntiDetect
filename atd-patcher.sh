#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Custom Patcher Engine
#  Config-driven patching for QEMU, EDK2, and Kernel sources
#
#  Self-contained: clones repos, installs deps, patches, builds,
#  and collects artifacts -- all from its own folder.
#
#  Usage: ./atd-patcher.sh [options]
#    --profile <file>    Config profile (.conf or .json)
#    --target <t>        qemu|edk2|kernel|all (default: all)
#    --qemu-dir <path>   Override QEMU source directory
#    --edk2-dir <path>   Override EDK2 source directory
#    --kernel-dir <path> Override Kernel source directory
#    --build-dir <path>  Where to clone/build (default: <script-dir>)
#    --jobs <n>           Parallel make jobs (default: nproc)
#    --skip-deps         Skip apt dependency installation
#    --skip-clone        Skip git clone (use existing sources)
#    --skip-build        Only patch, do not build .deb packages
#    --skip-cleanup      Keep patched sources after build
#    --dry-run           Show commands without executing
#    --rollback <dir>    Rollback from backup directory
#    --no-backup         Skip pre-patch backup
#    --verbose           Enable debug output
#    --help              Show this help
#
#  REMOTE EXECUTION ONLY -- run on your Proxmox build server
#  Part of: https://github.com/proxmox-atd
# ---------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/atd-styles.sh"

# ===== Defaults =====
PROFILE=""
TARGET="all"
QEMU_DIR=""
EDK2_DIR=""
KERNEL_DIR=""
BUILD_DIR="${SCRIPT_DIR}"
JOBS="$(nproc 2>/dev/null || echo 4)"
NO_BACKUP=0
DO_ROLLBACK=""
SKIP_DEPS=0
SKIP_CLONE=0
SKIP_BUILD=0
SKIP_CLEANUP=0

# ===== Resource Directories (resolved from SCRIPT_DIR) =====
RESOURCE_QEMU="${SCRIPT_DIR}/pve-emu-realpc-main"
RESOURCE_EDK2="${SCRIPT_DIR}/pve-emu-realpc_edk2-firmware-ovmf-main"
RESOURCE_KERNEL="${SCRIPT_DIR}/pve-emu-realpc_kernel-main"
RESOURCE_DEPLOY="${SCRIPT_DIR}/VM-Deployscripts"
PROFILES_DIR="${SCRIPT_DIR}/profiles"
PATCHES_DIR="${SCRIPT_DIR}/patches"

# ===== Build timestamp =====
BUILD_TS="$(date +%Y%m%d-%H%M%S)"
ATD_LOG_FILE="${SCRIPT_DIR}/atd-patcher-${BUILD_TS}.log"

# ===== Usage =====
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --profile <file>      Config profile (.conf or .json)
                        Default: auto-detects from profiles/
  --target <target>     qemu|edk2|kernel|deploy|all (default: all)
  --qemu-dir <path>     Override QEMU source dir (skip clone for QEMU)
  --edk2-dir <path>     Override EDK2 source dir (skip clone for EDK2)
  --kernel-dir <path>   Override kernel source dir (skip clone for kernel)
  --build-dir <path>    Where to clone and build (default: script directory)
  --jobs <n>            Parallel make jobs (default: $(nproc 2>/dev/null || echo 4))
  --skip-deps           Skip apt dependency installation
  --skip-clone          Skip git clone (use existing sources)
  --skip-build          Only apply patches, do not compile
  --skip-cleanup        Keep patched sources after build
  --dry-run             Preview all changes without modifying files
  --rollback <dir>      Restore files from a backup directory
  --no-backup           Skip creating file backups before patching
  --verbose             Enable debug-level logging
  --help                Show this help message

Workflow (executed in order):
  1. DEPS      Install build dependencies via apt
  2. CLONE     Clone proxmox git repos + submodules
  3. PATCH     Apply anti-detection sed patches + copy resources
  4. BUILD     Compile .deb packages with make
  5. COLLECT   Gather .deb artifacts into build-dir/artifacts/
  6. CLEANUP   Reset git trees to pristine state

Examples:
  # Full workflow: clone, patch, build everything
  sudo ./atd-patcher.sh

  # Only QEMU, skip deps (already installed)
  sudo ./atd-patcher.sh --target qemu --skip-deps

  # Patch only, no build
  ./atd-patcher.sh --target qemu --skip-clone --qemu-dir ./pve-qemu/qemu --skip-build

  # Use custom profile
  sudo ./atd-patcher.sh --profile profiles/example-intel-desktop.conf
EOF
    exit 0
}

# ===== Parse Arguments =====
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)     PROFILE="$2"; shift 2 ;;
        --target)      TARGET="$2"; shift 2 ;;
        --qemu-dir)    QEMU_DIR="$2"; shift 2 ;;
        --edk2-dir)    EDK2_DIR="$2"; shift 2 ;;
        --kernel-dir)  KERNEL_DIR="$2"; shift 2 ;;
        --build-dir)   BUILD_DIR="$2"; shift 2 ;;
        --jobs)        JOBS="$2"; shift 2 ;;
        --skip-deps)   SKIP_DEPS=1; shift ;;
        --skip-clone)  SKIP_CLONE=1; shift ;;
        --skip-build)  SKIP_BUILD=1; shift ;;
        --skip-cleanup) SKIP_CLEANUP=1; shift ;;
        --dry-run)     ATD_DRY_RUN=1; shift ;;
        --rollback)    DO_ROLLBACK="$2"; shift 2 ;;
        --no-backup)   NO_BACKUP=1; shift ;;
        --verbose)     ATD_LOG_LEVEL=4; shift ;;
        --help)        usage ;;
        *)             atd_die "Unknown option: $1" 2 ;;
    esac
done

# ===== Dry-run command wrapper =====
run_cmd() {
    if (( ATD_DRY_RUN )); then
        atd_dry "$*"
    else
        eval "$@"
    fi
}

# ===== Rollback Mode =====
if [[ -n "${DO_ROLLBACK}" ]]; then
    atd_banner "ROLLBACK" "Restoring from backup"
    atd_rollback "${DO_ROLLBACK}"
    exit $?
fi

# ===== Auto-Discover Profile =====
if [[ -z "${PROFILE}" ]]; then
    if [[ -f "${PROFILES_DIR}/default.conf" ]]; then
        PROFILE="${PROFILES_DIR}/default.conf"
    elif [[ -f "${PROFILES_DIR}/default.json" ]]; then
        PROFILE="${PROFILES_DIR}/default.json"
    else
        PROFILE="$(find "${PROFILES_DIR}" -maxdepth 1 \( -name '*.conf' -o -name '*.json' \) 2>/dev/null | head -1)"
    fi
fi

if [[ -z "${PROFILE}" ]] || [[ ! -f "${PROFILE}" ]]; then
    atd_die "Profile not found. Searched in: ${PROFILES_DIR}/" 2
fi

# ===== Load Brand =====
BRAND="$(atd_config_get "${PROFILE}" brand name)"
BRAND="${BRAND:-ASUS}"

if [[ ${#BRAND} -ne 4 ]]; then
    atd_die "Brand must be exactly 4 characters, got '${BRAND}' (${#BRAND} chars)" 2
fi

# ===== Resolve Source Directories =====
# If not explicitly given, sources are cloned inside their resource directories
[[ -z "${QEMU_DIR}" ]]   && QEMU_DIR="${RESOURCE_QEMU}/pve-qemu/qemu"
[[ -z "${EDK2_DIR}" ]]   && EDK2_DIR="${RESOURCE_EDK2}/pve-edk2-firmware/edk2"
[[ -z "${KERNEL_DIR}" ]] && KERNEL_DIR="${RESOURCE_KERNEL}/pve-kernel/submodules/ubuntu-kernel"

# ===== Export resource paths for patch modules =====
export ATD_RESOURCE_QEMU="${RESOURCE_QEMU}"
export ATD_RESOURCE_EDK2="${RESOURCE_EDK2}"
export ATD_RESOURCE_KERNEL="${RESOURCE_KERNEL}"
export ATD_SCRIPT_DIR="${SCRIPT_DIR}"
export ATD_BRAND="${BRAND}"

# ===== Header =====
atd_banner "PATCHER" "proxmox-atd Custom Patcher Engine"
atd_summary "Patcher Configuration" \
    "Profile"       "${PROFILE}" \
    "Target"        "${TARGET}" \
    "Brand"         "${BRAND}" \
    "Build Dir"     "${BUILD_DIR}" \
    "QEMU Dir"      "${QEMU_DIR}" \
    "EDK2 Dir"      "${EDK2_DIR}" \
    "Kernel Dir"    "${KERNEL_DIR}" \
    "Jobs"          "${JOBS}" \
    "Dry Run"       "$( (( ATD_DRY_RUN )) && echo 'YES' || echo 'no')" \
    "Log Level"     "${ATD_LOG_LEVEL}"

# ===== Source Patch Modules =====
for module in "${PATCHES_DIR}/"*.patch.sh; do
    if [[ -f "${module}" ]]; then
        source "${module}"
        atd_debug "Loaded module: $(basename "${module}")"
    fi
done

# =============================================================
#  PHASE 1: DEPENDENCIES
# =============================================================
phase_deps() {
    atd_banner "PHASE 1" "Installing Build Dependencies"

    if (( SKIP_DEPS )); then
        atd_skip "Dependency installation skipped (--skip-deps)"
        return 0
    fi

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
    )

    # PVE-specific
    if command -v pveversion &>/dev/null; then
        DEPS+=(libproxmox-backup-qemu0-dev)
    fi

    # EDK2-specific
    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        DEPS+=(gcc-aarch64-linux-gnu gcc-riscv64-linux-gnu)
    fi

    # Kernel-specific
    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        DEPS+=(
            dh-python asciidoc-base bison dwarves flex
            libdw-dev libelf-dev libiberty-dev libslang2-dev
            lz4 python3-dev xmlto rsync gawk
        )
    fi

    atd_info "Installing ${#DEPS[@]} packages ..."
    run_cmd "apt-get update -qq"
    run_cmd "apt-get install -y -qq ${DEPS[*]}"
    run_cmd "apt-get install -y devscripts"

    atd_ok "Dependencies installed"
}

# =============================================================
#  PHASE 2: CLONE
# =============================================================
phase_clone() {
    atd_banner "PHASE 2" "Cloning Upstream Repositories"

    if (( SKIP_CLONE )); then
        atd_skip "Clone skipped (--skip-clone)"
        return 0
    fi

    # --- QEMU ---
    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        if [[ ! -d "${RESOURCE_QEMU}/pve-qemu" ]]; then
            atd_step 1 3 "Cloning pve-qemu ..."
            run_cmd "git clone git://git.proxmox.com/git/pve-qemu.git ${RESOURCE_QEMU}/pve-qemu"
        else
            atd_skip "pve-qemu already exists"
        fi
        atd_info "Setting up pve-qemu submodules + build-deps ..."
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu && yes | mk-build-deps --install 2>/dev/null || true"
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu && git submodule update --init --recursive"
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu/qemu && meson subprojects download 2>/dev/null || true"
    fi

    # --- EDK2 ---
    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        if [[ ! -d "${RESOURCE_EDK2}/pve-edk2-firmware" ]]; then
            atd_step 2 3 "Cloning pve-edk2-firmware ..."
            run_cmd "git clone git://git.proxmox.com/git/pve-edk2-firmware.git ${RESOURCE_EDK2}/pve-edk2-firmware"
        else
            atd_skip "pve-edk2-firmware already exists"
        fi
        atd_info "Setting up pve-edk2-firmware submodules + build-deps ..."
        run_cmd "cd ${RESOURCE_EDK2}/pve-edk2-firmware && yes | mk-build-deps --install 2>/dev/null || true"
        run_cmd "cd ${RESOURCE_EDK2}/pve-edk2-firmware && git submodule update --init --recursive"
        run_cmd "cd ${RESOURCE_EDK2}/pve-edk2-firmware/edk2 && meson subprojects download 2>/dev/null || true"
    fi

    # --- Kernel ---
    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        # Read kernel branch from profile (default: trixie-6.17 for PVE 9)
        local kernel_branch
        kernel_branch="$(atd_config_get "${PROFILE}" kvm kernel_branch)"
        kernel_branch="${kernel_branch:-trixie-6.17}"

        if [[ ! -d "${RESOURCE_KERNEL}/pve-kernel" ]]; then
            atd_step 3 3 "Cloning pve-kernel (branch: ${kernel_branch}) ..."
            run_cmd "git clone -b ${kernel_branch} git://git.proxmox.com/git/pve-kernel.git ${RESOURCE_KERNEL}/pve-kernel"
        else
            atd_skip "pve-kernel already exists"
            # Ensure correct branch if already cloned
            local current_branch
            current_branch="$(cd "${RESOURCE_KERNEL}/pve-kernel" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
            if [[ -n "${current_branch}" ]] && [[ "${current_branch}" != "${kernel_branch}" ]]; then
                atd_warn "pve-kernel is on branch '${current_branch}', expected '${kernel_branch}'"
                atd_info "Switching to ${kernel_branch} ..."
                run_cmd "cd ${RESOURCE_KERNEL}/pve-kernel && git checkout ${kernel_branch} 2>/dev/null || git fetch origin ${kernel_branch} && git checkout ${kernel_branch}"
            fi
        fi
        atd_info "Setting up pve-kernel submodules ..."
        run_cmd "cd ${RESOURCE_KERNEL}/pve-kernel && git submodule update --init --recursive --force"

        # Newer pve-kernel branches (trixie+) use debian/control.in — generate debian/control
        local _kdir="${RESOURCE_KERNEL}/pve-kernel"
        if [[ ! -f "${_kdir}/debian/control" ]] && [[ -f "${_kdir}/debian/control.in" ]]; then
            atd_info "Generating debian/control from debian/control.in ..."
            run_cmd "cd ${_kdir} && make debian/control 2>/dev/null || cp debian/control.in debian/control"
        fi

        atd_info "Installing pve-kernel build-deps ..."
        run_cmd "cd ${_kdir} && yes | mk-build-deps --install 2>/dev/null || true"
        if [[ -d "${_kdir}/submodules/zfsonlinux" ]]; then
            run_cmd "cd ${_kdir}/submodules/zfsonlinux && mk-build-deps --install 2>/dev/null || true"
        fi

        # Fix upstream Makefile bug: grouped target rule (&:) is missing
        # $(LINUX_TOOLS_DBG_DEB) and $(SIGNED_TEMPLATE_DEB).
        local _mk="${_kdir}/Makefile"
        if [[ -f "${_mk}" ]] && grep -q 'LINUX_TOOLS_DEB) $(HDR_DEB) $(DST_DEB) &:' "${_mk}"; then
            atd_info "Patching Makefile grouped target rule (upstream bug) ..."
            sed -i 's/\$(LINUX_TOOLS_DEB) \$(HDR_DEB) \$(DST_DEB) &:/$(LINUX_TOOLS_DEB) $(LINUX_TOOLS_DBG_DEB) $(HDR_DEB) $(DST_DEB) $(SIGNED_TEMPLATE_DEB) \&:/' "${_mk}"
        fi
    fi

    atd_ok "Repositories ready"
}

# =============================================================
#  PHASE 3: PATCH
# =============================================================
phase_patch() {
    atd_banner "PHASE 3" "Applying Anti-Detection Patches"

    local PATCH_ERRORS=0

    # --- QEMU ---
    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        if [[ ! -d "${QEMU_DIR}" ]]; then
            atd_die "QEMU source directory not found: ${QEMU_DIR}" 2
        fi

        atd_banner "QEMU" "Patching QEMU Source"

        if (( ! NO_BACKUP )) && (( ! ATD_DRY_RUN )); then
            atd_backup_init "${SCRIPT_DIR}"
        fi

        patch_qemu_brand "${QEMU_DIR}" "${BRAND}" "${PROFILE}" || (( PATCH_ERRORS++ ))
        patch_qemu_acpi "${QEMU_DIR}" "${PROFILE}"       || (( PATCH_ERRORS++ ))
        patch_qemu_smbios "${QEMU_DIR}" "${PROFILE}"     || (( PATCH_ERRORS++ ))
        patch_qemu_ide_sata "${QEMU_DIR}" "${PROFILE}"   || (( PATCH_ERRORS++ ))
        patch_qemu_usb_scsi "${QEMU_DIR}" "${PROFILE}"   || (( PATCH_ERRORS++ ))
        patch_qemu_pci_ids "${QEMU_DIR}" "${PROFILE}"    || (( PATCH_ERRORS++ ))
        patch_qemu_kvm_cpuid "${QEMU_DIR}" "${PROFILE}"  || (( PATCH_ERRORS++ ))
        patch_qemu_misc "${QEMU_DIR}" "${PROFILE}"       || (( PATCH_ERRORS++ ))

        # Generate diff for reference
        if (( ! ATD_DRY_RUN )); then
            local _qemu_patch_dir
            _qemu_patch_dir="$(dirname "${QEMU_DIR}")"
            mkdir -p "${_qemu_patch_dir}"
            pushd "${QEMU_DIR}" > /dev/null
            git diff --submodule=diff > "${_qemu_patch_dir}/qemu-autoGenPatch.patch" 2>/dev/null || true
            popd > /dev/null
            atd_info "Generated qemu-autoGenPatch.patch"
        fi
    fi

    # --- EDK2 ---
    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        if [[ ! -d "${EDK2_DIR}" ]]; then
            atd_die "EDK2 source directory not found: ${EDK2_DIR}" 2
        fi

        atd_banner "EDK2" "Patching EDK2/OVMF Firmware"

        if (( ! NO_BACKUP )) && (( ! ATD_DRY_RUN )); then
            atd_backup_init "${SCRIPT_DIR}"
        fi

        # Copy Logo.bmp to debian/ (replaces boot logo)
        local logo_src="${RESOURCE_EDK2}/Logo.bmp"
        if [[ -f "${logo_src}" ]]; then
            local edk2_parent
            edk2_parent="$(dirname "${EDK2_DIR}")"
            if (( ATD_DRY_RUN )); then
                atd_dry "cp ${logo_src} -> ${edk2_parent}/debian/Logo.bmp"
            else
                cp "${logo_src}" "${edk2_parent}/debian/" 2>/dev/null || true
                atd_debug "Copied Logo.bmp to debian/"
            fi
        fi

        patch_edk2_brand "${EDK2_DIR}" "${BRAND}" || (( PATCH_ERRORS++ ))

        # Fix EDK2 BaseTools GenMake.py for Python 3.13 compatibility (CmdSumDict KeyError)
        local genmake="${EDK2_DIR}/BaseTools/Source/Python/AutoGen/GenMake.py"
        if [[ -f "${genmake}" ]]; then
            if ! grep -q 'CmdSumDict\.get(' "${genmake}" 2>/dev/null; then
                atd_info "Patching GenMake.py for Python 3.13 compatibility ..."
                if (( ATD_DRY_RUN )); then
                    atd_dry "Fix CmdSumDict KeyError in ${genmake}"
                else
                    python3 -c "
import sys
f = sys.argv[1]
c = open(f).read()
c = c.replace(
    'CmdSumDict[CmdSign[3:].rsplit(TAB_SLASH, 1)[0]]',
    'CmdSumDict.get(CmdSign[3:].rsplit(TAB_SLASH, 1)[0], \"\")'
)
open(f, 'w').write(c)
" "${genmake}"
                    atd_debug "Patched GenMake.py CmdSumDict KeyError fix"
                fi
            else
                atd_skip "GenMake.py already patched for Python 3.13"
            fi
        else
            atd_warn "GenMake.py not found at ${genmake}, skipping Python 3.13 fix"
        fi

        # Generate diff for reference
        if (( ! ATD_DRY_RUN )); then
            local _edk2_patch_dir
            _edk2_patch_dir="$(dirname "${EDK2_DIR}")"
            mkdir -p "${_edk2_patch_dir}"
            pushd "${EDK2_DIR}" > /dev/null
            git diff > "${_edk2_patch_dir}/edk2-autoGenPatch.patch" 2>/dev/null || true
            popd > /dev/null
            atd_info "Generated edk2-autoGenPatch.patch"
        fi
    fi

    # --- Kernel ---
    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        if [[ ! -d "${KERNEL_DIR}" ]]; then
            atd_die "Kernel source directory not found: ${KERNEL_DIR}" 2
        fi

        atd_banner "KERNEL" "Patching PVE Kernel KVM Modules"

        if (( ! NO_BACKUP )) && (( ! ATD_DRY_RUN )); then
            atd_backup_init "${SCRIPT_DIR}"
        fi

        patch_kernel_rdtsc "${KERNEL_DIR}" "${PROFILE}" || (( PATCH_ERRORS++ ))

        # Generate diff for reference
        if (( ! ATD_DRY_RUN )); then
            local _kernel_patch_dir
            _kernel_patch_dir="$(dirname "$(dirname "${KERNEL_DIR}")")"
            mkdir -p "${_kernel_patch_dir}"
            pushd "${KERNEL_DIR}" > /dev/null
            git diff > "${_kernel_patch_dir}/kernel-autoGenPatch.patch" 2>/dev/null || true
            popd > /dev/null
            atd_info "Generated kernel-autoGenPatch.patch"
        fi
    fi

    if (( PATCH_ERRORS > 0 )); then
        atd_err "Patching completed with ${PATCH_ERRORS} error(s)"
        return 4
    fi

    atd_ok "All patches applied successfully"
}

# =============================================================
#  PHASE 4: BUILD
# =============================================================
phase_build() {
    atd_banner "PHASE 4" "Compiling Packages"

    if (( SKIP_BUILD )); then
        atd_skip "Build skipped (--skip-build)"
        return 0
    fi

    atd_timer_start

    # Build logs directory
    local build_log_dir="${BUILD_DIR}/build-logs"
    mkdir -p "${build_log_dir}"

    # Helper: extract meaningful errors from a build log (disk-safe: no temp files)
    _build_fail_report() {
        local label="$1" log="$2"
        atd_err "${label} build FAILED"

        # Check if log exists and has content
        if [[ ! -f "${log}" ]]; then
            atd_err "Build log not found: ${log}"
            atd_err "The build may have failed before producing any output."
            atd_err "Check that the source directory exists and is accessible."
        elif [[ ! -s "${log}" ]]; then
            atd_err "Build log is empty: ${log}"
            atd_err "The build may have failed immediately (bad path or missing source)."
        else
            # Try to find actual error lines first (use printf, avoid here-strings)
            local error_lines
            error_lines=$(grep -n -i -E '(^FAILED:|: error:|: fatal error:|Error [0-9]+$|No space left on device|Cannot allocate memory|make\[[0-9]+\]: \*\*\*|ninja: build stopped|dpkg-buildapi: error)' "${log}" 2>/dev/null | tail -20) || true

            if [[ -n "${error_lines}" ]]; then
                atd_err "Error lines from ${log}:"
                printf '%s\n' "${error_lines}" | while IFS= read -r _l; do atd_err "  ${_l}"; done
            else
                atd_err "No obvious errors found. Last 50 lines of ${log}:"
                tail -50 "${log}" 2>/dev/null | while IFS= read -r _l; do atd_err "  ${_l}"; done
            fi
        fi

        # Report disk space (common CI failure cause)
        atd_err "Disk usage at failure:"
        atd_err "  $(df -h / 2>/dev/null | tail -1)"
    }

    # Helper: collect .deb files from a build dir and purge build artifacts to free disk
    _collect_and_clean() {
        local label="$1" src_dir="$2" artifacts="$3"
        shift 3
        # Collect .deb files matching patterns
        for pattern in "$@"; do
            find "${src_dir}" -maxdepth 2 -name "${pattern}" ! -name "*dbgsym*" -exec cp {} "${artifacts}/" \; 2>/dev/null || true
        done
        # When building all targets, clean build tree to free disk for next target
        if [[ "${TARGET}" == "all" ]]; then
            local freed
            freed=$(du -sh "${src_dir}" 2>/dev/null | cut -f1)
            atd_info "Cleaning ${label} build tree to free ~${freed:-??} ..."
            ( cd "${src_dir}" && make clean 2>/dev/null || true ) &>/dev/null
            # Remove unpacked source dirs (massive for kernel/QEMU)
            find "${src_dir}" -maxdepth 1 -type d -name "*.orig" -exec rm -rf {} \; 2>/dev/null || true
            atd_info "Disk after cleanup: $(df -h / 2>/dev/null | tail -1)"
        fi
    }

    # --- QEMU ---
    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_separator "Building pve-qemu-kvm"
        local qemu_log="${build_log_dir}/qemu-build.log"
        if (( ATD_DRY_RUN )); then
            atd_dry "cd ${RESOURCE_QEMU}/pve-qemu && make -j${JOBS}"
        else
            ( cd "${RESOURCE_QEMU}/pve-qemu" && make clean 2>/dev/null || true ) &>/dev/null
            if ( cd "${RESOURCE_QEMU}/pve-qemu" && make -j${JOBS} ) &>"${qemu_log}"; then
                atd_ok "QEMU build complete (log: ${qemu_log})"
                # Collect QEMU .debs immediately, then clean if building more targets
                local artifacts="${BUILD_DIR}/artifacts"
                mkdir -p "${artifacts}"
                _collect_and_clean "QEMU" "${RESOURCE_QEMU}/pve-qemu" "${artifacts}" "pve-qemu-kvm_*.deb"
            else
                _build_fail_report "QEMU" "${qemu_log}"
                atd_die "QEMU build failed — see ${qemu_log} for details" 1
            fi
        fi
    fi

    # --- EDK2 ---
    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_separator "Building pve-edk2-firmware-ovmf"
        local edk2_log="${build_log_dir}/edk2-build.log"
        if (( ATD_DRY_RUN )); then
            atd_dry "cd ${RESOURCE_EDK2}/pve-edk2-firmware && make"
        else
            if ( cd "${RESOURCE_EDK2}/pve-edk2-firmware" && make ) &>"${edk2_log}"; then
                atd_ok "EDK2 build complete (log: ${edk2_log})"
                # Collect EDK2 .debs immediately, then clean if building more targets
                local artifacts="${BUILD_DIR}/artifacts"
                mkdir -p "${artifacts}"
                _collect_and_clean "EDK2" "${RESOURCE_EDK2}/pve-edk2-firmware" "${artifacts}" \
                    "pve-edk2-firmware-ovmf_*.deb" "pve-edk2-firmware_*.deb"
            else
                _build_fail_report "EDK2" "${edk2_log}"
                atd_die "EDK2 build failed — see ${edk2_log} for details" 1
            fi
        fi
    fi

    # --- Kernel ---
    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_separator "Building pve-kernel"
        local kernel_log="${build_log_dir}/kernel-build.log"
        atd_info "Disk before kernel build: $(df -h / 2>/dev/null | tail -1)"
        if (( ATD_DRY_RUN )); then
            atd_dry "cd ${RESOURCE_KERNEL}/pve-kernel && make -j${JOBS}"
        else
            if ( cd "${RESOURCE_KERNEL}/pve-kernel" && make -j${JOBS} ) &>"${kernel_log}"; then
                atd_ok "Kernel build complete (log: ${kernel_log})"
            else
                _build_fail_report "Kernel" "${kernel_log}"
                atd_die "Kernel build failed — see ${kernel_log} for details" 1
            fi
        fi
    fi

    atd_timer_stop "Build phase"
}

# =============================================================
#  PHASE 5: COLLECT ARTIFACTS
# =============================================================
phase_collect() {
    atd_banner "PHASE 5" "Collecting Build Artifacts"

    if (( SKIP_BUILD )); then
        atd_skip "Artifact collection skipped (no build was performed)"
        return 0
    fi

    local artifacts="${BUILD_DIR}/artifacts"
    run_cmd "mkdir -p ${artifacts}"

    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        run_cmd "find ${RESOURCE_QEMU}/pve-qemu -maxdepth 1 -name '*.deb' ! -name '*dbgsym*' -exec cp {} ${artifacts}/ \\;"
        run_cmd "cp ${RESOURCE_QEMU}/pve-qemu/qemu-autoGenPatch.patch ${artifacts}/ 2>/dev/null || true"
    fi

    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        run_cmd "find ${RESOURCE_EDK2}/pve-edk2-firmware -maxdepth 1 -name '*.deb' ! -name '*legacy*' ! -name '*aarch64*' ! -name '*deps*' ! -name '*riscv*' -exec cp {} ${artifacts}/ \\;"
        run_cmd "cp ${RESOURCE_EDK2}/pve-edk2-firmware/edk2-autoGenPatch.patch ${artifacts}/ 2>/dev/null || true"
    fi

    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        run_cmd "find ${RESOURCE_KERNEL}/pve-kernel -maxdepth 1 -name '*.deb' -exec cp {} ${artifacts}/ \\;"
        run_cmd "find ${RESOURCE_KERNEL}/pve-kernel -name 'kvm*.ko' -exec cp {} ${artifacts}/ \\; 2>/dev/null || true"
        run_cmd "cp ${RESOURCE_KERNEL}/pve-kernel/kernel-autoGenPatch.patch ${artifacts}/ 2>/dev/null || true"
    fi

    # Copy ACPI tables from resources
    run_cmd "cp ${RESOURCE_QEMU}/*.aml ${artifacts}/ 2>/dev/null || true"

    # Copy deploy scripts and Windows guest tools
    if [[ -d "${RESOURCE_DEPLOY}" ]]; then
        run_cmd "cp ${RESOURCE_DEPLOY}/pve-realpc-setup.sh ${artifacts}/ 2>/dev/null || true"
        run_cmd "cp ${RESOURCE_DEPLOY}/pve-realpc-deploy-vm.sh ${artifacts}/ 2>/dev/null || true"
        if [[ -d "${RESOURCE_DEPLOY}/windows" ]] && command -v zip &>/dev/null; then
            ( cd "${RESOURCE_DEPLOY}" && zip -qr "${artifacts}/windows-guest-tools.zip" windows/ ) 2>/dev/null || true
            atd_debug "Packed Windows guest tools"
        fi
    fi

    if (( ! ATD_DRY_RUN )); then
        atd_info "Artifacts in ${artifacts}/:"
        ls -lh "${artifacts}/" 2>/dev/null | while read -r line; do
            atd_info "  ${line}"
        done
    fi

    atd_ok "Artifacts collected"
}

# =============================================================
#  PHASE 6: CLEANUP
# =============================================================
phase_cleanup() {
    atd_banner "PHASE 6" "Restoring Source Trees"

    if (( SKIP_CLEANUP )); then
        atd_skip "Cleanup skipped (--skip-cleanup)"
        return 0
    fi

    if (( SKIP_BUILD )); then
        atd_skip "Cleanup skipped (no build was performed)"
        return 0
    fi

    if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Resetting pve-qemu ..."
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu/qemu && git checkout . 2>/dev/null || true"
        run_cmd "rm -rf ${RESOURCE_QEMU}/pve-qemu/qemu/pc-bios 2>/dev/null || true"
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu && git reset --hard master 2>/dev/null || true"
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu && git submodule update --init --recursive --force 2>/dev/null || true"
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu && git checkout . 2>/dev/null || true"
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu/qemu && git checkout . 2>/dev/null || true"
        run_cmd "cd ${RESOURCE_QEMU}/pve-qemu/qemu && git submodule update --init --recursive --force 2>/dev/null || true"
    fi

    if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Resetting pve-edk2-firmware ..."
        run_cmd "cd ${RESOURCE_EDK2}/pve-edk2-firmware/edk2 && git checkout . 2>/dev/null || true"
    fi

    if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
        atd_info "Resetting pve-kernel ..."
        run_cmd "cd ${RESOURCE_KERNEL}/pve-kernel/submodules/ubuntu-kernel && git checkout . 2>/dev/null || true"
    fi

    atd_ok "Cleanup complete"
}

# =============================================================
#  PHASE 7: DEPLOY (Host Setup using locally-built artifacts)
# =============================================================
phase_deploy() {
    atd_banner "PHASE 7" "Deploying Anti-Detection Packages"

    local deploy_script="${RESOURCE_DEPLOY}/pve-realpc-setup.sh"
    if [[ ! -f "${deploy_script}" ]]; then
        atd_die "Deploy script not found: ${deploy_script}" 2
    fi

    local artifacts="${BUILD_DIR}/artifacts"
    local deploy_work="/root/pve-realpc"

    # Copy locally-built .deb files to the deploy script's expected location
    atd_info "Staging locally-built artifacts for deployment ..."
    run_cmd "mkdir -p ${deploy_work}"

    # QEMU .deb
    if ls "${artifacts}"/pve-qemu-kvm_*.deb 1>/dev/null 2>&1; then
        run_cmd "cp ${artifacts}/pve-qemu-kvm_*.deb ${deploy_work}/"
        atd_debug "Staged QEMU .deb"
    fi

    # EDK2/OVMF .deb
    if ls "${artifacts}"/pve-edk2-firmware-ovmf_*.deb 1>/dev/null 2>&1; then
        run_cmd "cp ${artifacts}/pve-edk2-firmware-ovmf_*.deb ${deploy_work}/"
        atd_debug "Staged OVMF .deb"
    fi

    # ACPI tables
    run_cmd "cp ${artifacts}/*.aml ${deploy_work}/ 2>/dev/null || true"

    # Run the setup script with --skip-download (use our local artifacts)
    atd_info "Running pve-realpc-setup.sh --skip-download ..."
    if (( ATD_DRY_RUN )); then
        atd_dry "bash ${deploy_script} --skip-download"
    else
        bash "${deploy_script}" --skip-download
    fi

    atd_ok "Host deployment complete"
}

# =============================================================
#  MAIN EXECUTION
# =============================================================
atd_timer_start

# Trap for error reporting
CURRENT_PHASE=""
cleanup_on_error() {
    local exit_code=$?
    if (( exit_code != 0 )) && [[ -n "${CURRENT_PHASE}" ]]; then
        atd_err "Failed during: ${CURRENT_PHASE}"
        atd_err "Log file: ${ATD_LOG_FILE}"
    fi
}
trap cleanup_on_error EXIT

# Execute phases
CURRENT_PHASE="deps";    phase_deps
CURRENT_PHASE="clone";   phase_clone
CURRENT_PHASE="patch";   phase_patch
CURRENT_PHASE="build";   phase_build
CURRENT_PHASE="collect"; phase_collect
CURRENT_PHASE="cleanup"; phase_cleanup
CURRENT_PHASE=""

# ===== Final Summary =====
atd_timer_stop "Full pipeline"

atd_banner "COMPLETE" "Build finished"
if (( ! SKIP_BUILD )); then
    artifacts="${BUILD_DIR}/artifacts"
    atd_ok "Artifacts ready in: ${artifacts}/"

    # List .deb files
    if (( ! ATD_DRY_RUN )) && [[ -d "${artifacts}" ]]; then
        echo ""
        atd_info "Built packages:"
        find "${artifacts}" -name '*.deb' -printf '  %f\n' 2>/dev/null | sort

        echo ""
        atd_separator "Installation Commands"
        echo ""

        if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
            qemu_deb=""
            qemu_deb="$(find "${artifacts}" -name 'pve-qemu-kvm_*.deb' 2>/dev/null | head -1)"
            if [[ -n "${qemu_deb}" ]]; then
                atd_info "QEMU:   dpkg -i ${qemu_deb}"
            fi
        fi

        if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
            edk2_deb=""
            edk2_deb="$(find "${artifacts}" -name 'pve-edk2-firmware-ovmf_*.deb' 2>/dev/null | head -1)"
            if [[ -n "${edk2_deb}" ]]; then
                atd_info "EDK2:   dpkg -i ${edk2_deb}"
            fi
        fi

        if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
            kernel_debs=""
            kernel_debs="$(find "${artifacts}" -name 'pve-kernel-*.deb' 2>/dev/null | tr '\n' ' ')"
            if [[ -n "${kernel_debs}" ]]; then
                atd_info "Kernel: dpkg -i ${kernel_debs}"
            fi
        fi

        # ACPI tables
        if ls "${artifacts}"/*.aml 1>/dev/null 2>&1; then
            echo ""
            atd_info "ACPI tables: cp ${artifacts}/*.aml /usr/share/kvm/"
        fi

        echo ""
        atd_info "Or install everything at once:"
        atd_info "  dpkg -i ${artifacts}/*.deb"

        # Offer deploy if running interactively (not CI)
        if [[ -z "${CI:-}" ]] && [[ -z "${GITHUB_ACTIONS:-}" ]] && [[ -t 0 ]]; then
            if [[ -f "${RESOURCE_DEPLOY}/pve-realpc-setup.sh" ]]; then
                echo ""
                atd_separator "Deploy Available"
                atd_info "Deploy scripts are available to install packages and configure your host."
                atd_info "This will run pve-realpc-setup.sh using the locally-built artifacts."
                echo ""
                if atd_confirm "Would you like to deploy now?"; then
                    CURRENT_PHASE="deploy"; phase_deploy
                    CURRENT_PHASE=""
                else
                    atd_skip "Deploy skipped. You can run it later with:"
                    atd_info "  ./atd-patcher.sh --target deploy"
                fi
            fi
        fi
    fi
else
    atd_ok "Patches applied. Sources ready for manual build."
fi

trap - EXIT
exit 0
