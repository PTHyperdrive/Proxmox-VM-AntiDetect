#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Custom Patcher Engine
#  Config-driven patching for QEMU, EDK2, and Kernel sources
#
#  All configs, patches, and resource files are resolved relative
#  to this script's own directory. No external paths required.
#
#  Usage: ./atd-patcher.sh [options]
#    --profile <file>    Config profile (.conf or .json)
#    --target <t>        qemu|edk2|kernel|all (default: all)
#    --qemu-dir <path>   Override QEMU source directory
#    --edk2-dir <path>   Override EDK2 source directory
#    --kernel-dir <path> Override Kernel source directory
#    --build-dir <path>  Override build output root (probed automatically)
#    --dry-run           Show commands without executing
#    --rollback <dir>    Rollback from backup directory
#    --no-backup         Skip pre-patch backup
#    --verbose           Enable debug output
#    --help              Show this help
#
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
BUILD_DIR=""
NO_BACKUP=0
DO_ROLLBACK=""

# ===== Resource Directories (resolved from SCRIPT_DIR) =====
RESOURCE_QEMU="${SCRIPT_DIR}/pve-emu-realpc-main"
RESOURCE_EDK2="${SCRIPT_DIR}/pve-emu-realpc_edk2-firmware-ovmf-main"
RESOURCE_KERNEL="${SCRIPT_DIR}/pve-emu-realpc_kernel-main"
PROFILES_DIR="${SCRIPT_DIR}/profiles"
PATCHES_DIR="${SCRIPT_DIR}/patches"

# ===== Usage =====
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --profile <file>      Config profile (.conf or .json)
                        Default: auto-detects from ${PROFILES_DIR}/
  --target <target>     qemu|edk2|kernel|all (default: all)
  --qemu-dir <path>     Override QEMU source directory
  --edk2-dir <path>     Override EDK2 source directory
  --kernel-dir <path>   Override kernel source directory
  --build-dir <path>    Override build output root (for auto-discovery)
  --dry-run             Preview all changes without modifying files
  --rollback <dir>      Restore files from a backup directory
  --no-backup           Skip creating file backups before patching
  --verbose             Enable debug-level logging
  --help                Show this help message

Auto-Discovery:
  The patcher automatically resolves all paths relative to its own directory.
  Source directories are probed in this order:
    1. Explicit --qemu-dir / --edk2-dir / --kernel-dir flags
    2. <build-dir>/pve-qemu/qemu , <build-dir>/pve-edk2-firmware/edk2, etc.
    3. <script-dir>/build-output/pve-qemu/qemu, etc.
    4. <script-dir>/pve-qemu/qemu, etc.

  Resource files (smbios.c/.h, bootsplash.jpg, kernel.patch, Logo.bmp,
  ACPI .aml files) are resolved from the repo's bundled directories:
    ${RESOURCE_QEMU}/
    ${RESOURCE_EDK2}/
    ${RESOURCE_KERNEL}/

Examples:
  # Auto-discover everything from the repo folder
  ./atd-patcher.sh --target all

  # Dry run with default profile
  ./atd-patcher.sh --dry-run --target qemu

  # Use a specific build output dir
  ./atd-patcher.sh --build-dir /root/build-output --target all

  # Full patch with custom profile
  ./atd-patcher.sh --profile profiles/example-intel-desktop.conf --target all

  # Rollback
  ./atd-patcher.sh --rollback .atd-backup/20260428-153341
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
        --dry-run)     ATD_DRY_RUN=1; shift ;;
        --rollback)    DO_ROLLBACK="$2"; shift 2 ;;
        --no-backup)   NO_BACKUP=1; shift ;;
        --verbose)     ATD_LOG_LEVEL=4; shift ;;
        --help)        usage ;;
        *)             atd_die "Unknown option: $1" 2 ;;
    esac
done

# ===== Rollback Mode =====
if [[ -n "${DO_ROLLBACK}" ]]; then
    atd_banner "ROLLBACK" "Restoring from backup"
    atd_rollback "${DO_ROLLBACK}"
    exit $?
fi

# ===== Auto-Discover Profile =====
if [[ -z "${PROFILE}" ]]; then
    # Default profile: prefer .conf, fall back to .json
    if [[ -f "${PROFILES_DIR}/default.conf" ]]; then
        PROFILE="${PROFILES_DIR}/default.conf"
    elif [[ -f "${PROFILES_DIR}/default.json" ]]; then
        PROFILE="${PROFILES_DIR}/default.json"
    else
        # Use first available profile
        PROFILE="$(find "${PROFILES_DIR}" -maxdepth 1 \( -name '*.conf' -o -name '*.json' \) 2>/dev/null | head -1)"
    fi
fi

# ===== Validate Profile =====
if [[ -z "${PROFILE}" ]] || [[ ! -f "${PROFILE}" ]]; then
    atd_die "Profile not found. Searched in: ${PROFILES_DIR}/" 2
fi

# ===== Load Brand =====
BRAND="$(atd_config_get "${PROFILE}" brand name)"
BRAND="${BRAND:-ASUS}"

if [[ ${#BRAND} -ne 4 ]]; then
    atd_die "Brand must be exactly 4 characters, got '${BRAND}' (${#BRAND} chars)" 2
fi

# ===== Auto-Discover Source Directories =====
# Probe common locations relative to SCRIPT_DIR for each source tree.
# Priority: explicit flag > build-dir > build-output > script-dir root
_probe_source_dir() {
    local label="$1"
    shift
    local candidates=("$@")

    for dir in "${candidates[@]}"; do
        if [[ -d "${dir}" ]]; then
            atd_debug "Auto-discovered ${label} at: ${dir}"
            echo "${dir}"
            return 0
        fi
    done
    echo ""
    return 0
}

# Resolve build-dir (explicit or auto-probed)
if [[ -z "${BUILD_DIR}" ]]; then
    if [[ -d "${SCRIPT_DIR}/build-output" ]]; then
        BUILD_DIR="${SCRIPT_DIR}/build-output"
    else
        BUILD_DIR="${SCRIPT_DIR}"
    fi
fi

# Auto-discover QEMU source
if [[ -z "${QEMU_DIR}" ]]; then
    QEMU_DIR="$(_probe_source_dir "QEMU" \
        "${BUILD_DIR}/pve-qemu/qemu" \
        "${SCRIPT_DIR}/build-output/pve-qemu/qemu" \
        "${SCRIPT_DIR}/pve-qemu/qemu" \
    )"
fi

# Auto-discover EDK2 source
if [[ -z "${EDK2_DIR}" ]]; then
    EDK2_DIR="$(_probe_source_dir "EDK2" \
        "${BUILD_DIR}/pve-edk2-firmware/edk2" \
        "${SCRIPT_DIR}/build-output/pve-edk2-firmware/edk2" \
        "${SCRIPT_DIR}/pve-edk2-firmware/edk2" \
    )"
fi

# Auto-discover Kernel source
if [[ -z "${KERNEL_DIR}" ]]; then
    KERNEL_DIR="$(_probe_source_dir "Kernel" \
        "${BUILD_DIR}/pve-kernel/submodules/ubuntu-kernel" \
        "${SCRIPT_DIR}/build-output/pve-kernel/submodules/ubuntu-kernel" \
        "${SCRIPT_DIR}/pve-kernel/submodules/ubuntu-kernel" \
    )"
fi

# ===== Header =====
atd_banner "PATCHER" "proxmox-atd Custom Patcher Engine"
atd_summary "Patcher Configuration" \
    "Profile"       "${PROFILE}" \
    "Target"        "${TARGET}" \
    "Brand"         "${BRAND}" \
    "QEMU Dir"      "${QEMU_DIR:-<not found>}" \
    "EDK2 Dir"      "${EDK2_DIR:-<not found>}" \
    "Kernel Dir"    "${KERNEL_DIR:-<not found>}" \
    "Resources"     "${SCRIPT_DIR}/" \
    "Dry Run"       "$( (( ATD_DRY_RUN )) && echo 'YES' || echo 'no')" \
    "Log Level"     "${ATD_LOG_LEVEL}"

# ===== Export resource paths for patch modules =====
# Patch modules can reference these instead of computing paths themselves
export ATD_RESOURCE_QEMU="${RESOURCE_QEMU}"
export ATD_RESOURCE_EDK2="${RESOURCE_EDK2}"
export ATD_RESOURCE_KERNEL="${RESOURCE_KERNEL}"
export ATD_SCRIPT_DIR="${SCRIPT_DIR}"

# ===== Source Patch Modules =====
for module in "${PATCHES_DIR}/"*.patch.sh; do
    if [[ -f "${module}" ]]; then
        source "${module}"
        atd_debug "Loaded module: $(basename "${module}")"
    fi
done

# ===== Patch Execution =====
PATCH_ERRORS=0
atd_timer_start

# --- QEMU ---
if [[ "${TARGET}" == "qemu" ]] || [[ "${TARGET}" == "all" ]]; then
    if [[ -z "${QEMU_DIR}" ]]; then
        atd_warn "QEMU source not found -- searched:"
        atd_warn "  ${BUILD_DIR}/pve-qemu/qemu"
        atd_warn "  ${SCRIPT_DIR}/build-output/pve-qemu/qemu"
        atd_warn "  ${SCRIPT_DIR}/pve-qemu/qemu"
        atd_warn "Use --qemu-dir to specify manually, or --build-dir to set root"
    elif [[ ! -d "${QEMU_DIR}" ]]; then
        atd_die "QEMU source directory not found: ${QEMU_DIR}" 2
    else
        atd_banner "QEMU" "Patching QEMU Source"

        # Backup
        if (( ! NO_BACKUP )) && (( ! ATD_DRY_RUN )); then
            atd_backup_init "${SCRIPT_DIR}"
        fi

        patch_qemu_brand "${QEMU_DIR}" "${BRAND}"       || (( PATCH_ERRORS++ ))
        patch_qemu_acpi "${QEMU_DIR}" "${PROFILE}"       || (( PATCH_ERRORS++ ))
        patch_qemu_smbios "${QEMU_DIR}" "${PROFILE}"     || (( PATCH_ERRORS++ ))
        patch_qemu_ide_sata "${QEMU_DIR}" "${PROFILE}"   || (( PATCH_ERRORS++ ))
        patch_qemu_usb_scsi "${QEMU_DIR}" "${PROFILE}"   || (( PATCH_ERRORS++ ))
        patch_qemu_pci_ids "${QEMU_DIR}" "${PROFILE}"    || (( PATCH_ERRORS++ ))
        patch_qemu_kvm_cpuid "${QEMU_DIR}" "${PROFILE}"  || (( PATCH_ERRORS++ ))
        patch_qemu_misc "${QEMU_DIR}" "${PROFILE}"       || (( PATCH_ERRORS++ ))
    fi
fi

# --- EDK2 ---
if [[ "${TARGET}" == "edk2" ]] || [[ "${TARGET}" == "all" ]]; then
    if [[ -z "${EDK2_DIR}" ]]; then
        atd_warn "EDK2 source not found -- searched:"
        atd_warn "  ${BUILD_DIR}/pve-edk2-firmware/edk2"
        atd_warn "  ${SCRIPT_DIR}/build-output/pve-edk2-firmware/edk2"
        atd_warn "  ${SCRIPT_DIR}/pve-edk2-firmware/edk2"
        atd_warn "Use --edk2-dir to specify manually, or --build-dir to set root"
    elif [[ ! -d "${EDK2_DIR}" ]]; then
        atd_die "EDK2 source directory not found: ${EDK2_DIR}" 2
    else
        atd_banner "EDK2" "Patching EDK2/OVMF Firmware"

        if (( ! NO_BACKUP )) && (( ! ATD_DRY_RUN )); then
            atd_backup_init "${SCRIPT_DIR}"
        fi

        patch_edk2_brand "${EDK2_DIR}" "${BRAND}" || (( PATCH_ERRORS++ ))
    fi
fi

# --- Kernel ---
if [[ "${TARGET}" == "kernel" ]] || [[ "${TARGET}" == "all" ]]; then
    if [[ -z "${KERNEL_DIR}" ]]; then
        atd_warn "Kernel source not found -- searched:"
        atd_warn "  ${BUILD_DIR}/pve-kernel/submodules/ubuntu-kernel"
        atd_warn "  ${SCRIPT_DIR}/build-output/pve-kernel/submodules/ubuntu-kernel"
        atd_warn "  ${SCRIPT_DIR}/pve-kernel/submodules/ubuntu-kernel"
        atd_warn "Use --kernel-dir to specify manually, or --build-dir to set root"
    elif [[ ! -d "${KERNEL_DIR}" ]]; then
        atd_die "Kernel source directory not found: ${KERNEL_DIR}" 2
    else
        atd_banner "KERNEL" "Patching PVE Kernel KVM Modules"

        if (( ! NO_BACKUP )) && (( ! ATD_DRY_RUN )); then
            atd_backup_init "${SCRIPT_DIR}"
        fi

        patch_kernel_rdtsc "${KERNEL_DIR}" "${PROFILE}" || (( PATCH_ERRORS++ ))
    fi
fi

# ===== Summary =====
atd_timer_stop "Patcher"

if (( PATCH_ERRORS > 0 )); then
    atd_err "Completed with ${PATCH_ERRORS} error(s)"
    exit 4
else
    atd_ok "All patches applied successfully"
    exit 0
fi
