#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU Miscellaneous Fixes
#  Catch-all for remaining anti-detection patches
#
#  Usage: source patches/qemu-misc.patch.sh
#         patch_qemu_misc <qemu_src_dir> <config_file>
# ---------------------------------------------------------------

patch_qemu_misc() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching QEMU Miscellaneous Anti-Detection"

    local count=0
    local total=2

    # -- Copy custom SMBIOS implementation --
    (( count++ )); atd_step ${count} ${total} "Custom smbios.h + smbios.c (extended types)"
    local resource_dir="${ATD_RESOURCE_QEMU:-${ATD_SCRIPT_DIR}/pve-emu-realpc-main}"
    local smbios_h_src="${resource_dir}/smbios.h"
    local smbios_c_src="${resource_dir}/smbios.c"

    if [[ -f "${smbios_h_src}" ]]; then
        if (( ATD_DRY_RUN )); then
            atd_dry "cp ${smbios_h_src} -> ${src}/include/hw/firmware/smbios.h"
            atd_dry "cp ${smbios_c_src} -> ${src}/hw/smbios/smbios.c"
        else
            cp "${smbios_h_src}" "${src}/include/hw/firmware/smbios.h"
            cp "${smbios_c_src}" "${src}/hw/smbios/smbios.c"
            atd_debug "Copied custom SMBIOS header + implementation"
        fi
    else
        atd_warn "Custom smbios.h not found at ${smbios_h_src}, skipping SMBIOS overlay"
    fi

    # -- Copy custom bootsplash --
    (( count++ )); atd_step ${count} ${total} "Custom bootsplash.jpg"
    local splash_src="${resource_dir}/bootsplash.jpg"
    if [[ -f "${splash_src}" ]]; then
        if (( ATD_DRY_RUN )); then
            atd_dry "cp ${splash_src} -> ${src}/pc-bios/bootsplash.jpg"
        else
            cp "${splash_src}" "${src}/pc-bios/bootsplash.jpg"
            atd_debug "Copied custom bootsplash"
        fi
    else
        atd_warn "Custom bootsplash.jpg not found, skipping"
    fi

    atd_ok "Miscellaneous patching complete"
    return 0
}
