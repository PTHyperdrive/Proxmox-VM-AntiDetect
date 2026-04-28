#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Custom Patcher Engine
#  Config-driven patching for QEMU, EDK2, and Kernel sources
#
#  Usage: ./atd-patcher.sh [options]
#    --profile <file>    Config profile (.conf or .json)
#    --target <t>        qemu|edk2|kernel|all (default: all)
#    --qemu-dir <path>   QEMU source directory
#    --edk2-dir <path>   EDK2 source directory
#    --kernel-dir <path> Kernel source directory
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
PROFILE="${SCRIPT_DIR}/profiles/default.conf"
TARGET="all"
QEMU_DIR=""
EDK2_DIR=""
KERNEL_DIR=""
NO_BACKUP=0
DO_ROLLBACK=""

# ===== Usage =====
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --profile <file>      Config profile (.conf or .json)
  --target <target>     qemu|edk2|kernel|all (default: all)
  --qemu-dir <path>     Path to QEMU source (e.g., pve-qemu/qemu)
  --edk2-dir <path>     Path to EDK2 source (e.g., pve-edk2-firmware/edk2)
  --kernel-dir <path>   Path to kernel source (e.g., pve-kernel/submodules/ubuntu-kernel)
  --dry-run             Preview all changes without modifying files
  --rollback <dir>      Restore files from a backup directory
  --no-backup           Skip creating file backups before patching
  --verbose             Enable debug-level logging
  --help                Show this help message

Examples:
  # Dry run with default profile
  ./atd-patcher.sh --dry-run --target qemu --qemu-dir ./pve-qemu/qemu

  # Full patch with custom profile
  ./atd-patcher.sh --profile profiles/example-intel-desktop.conf \\
                   --target all --qemu-dir ./pve-qemu/qemu \\
                   --edk2-dir ./pve-edk2-firmware/edk2 \\
                   --kernel-dir ./pve-kernel/submodules/ubuntu-kernel

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

# ===== Validate Profile =====
if [[ ! -f "${PROFILE}" ]]; then
    atd_die "Profile not found: ${PROFILE}" 2
fi

# ===== Load Brand =====
BRAND="$(atd_config_get "${PROFILE}" brand name)"
BRAND="${BRAND:-ASUS}"

if [[ ${#BRAND} -ne 4 ]]; then
    atd_die "Brand must be exactly 4 characters, got '${BRAND}' (${#BRAND} chars)" 2
fi

# ===== Header =====
atd_banner "PATCHER" "proxmox-atd Custom Patcher Engine"
atd_summary "Patcher Configuration" \
    "Profile"    "${PROFILE}" \
    "Target"     "${TARGET}" \
    "Brand"      "${BRAND}" \
    "Dry Run"    "$( (( ATD_DRY_RUN )) && echo 'YES' || echo 'no')" \
    "Log Level"  "${ATD_LOG_LEVEL}"

# ===== Source Patch Modules =====
for module in "${SCRIPT_DIR}/patches/"*.patch.sh; do
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
        atd_warn "No --qemu-dir specified, skipping QEMU patches"
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
        atd_warn "No --edk2-dir specified, skipping EDK2 patches"
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
        atd_warn "No --kernel-dir specified, skipping Kernel patches"
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
