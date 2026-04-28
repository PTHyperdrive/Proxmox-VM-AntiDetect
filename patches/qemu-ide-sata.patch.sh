#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU IDE/SATA Anti-Detection
#  Patches IDE/SATA serial numbers, firmware, SMART data
#
#  Usage: source patches/qemu-ide-sata.patch.sh
#         patch_qemu_ide_sata <qemu_src_dir> <config_file>
# ---------------------------------------------------------------

patch_qemu_ide_sata() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching QEMU IDE/SATA Identifiers"

    local brand
    brand="$(atd_config_get "${cfg}" brand name)"
    brand="${brand:-ASUS}"

    local poh pcc
    poh="$(atd_config_get "${cfg}" disk power_on_hours)"
    poh="${poh:-0x029a}"
    pcc="$(atd_config_get "${cfg}" disk power_cycle_count)"
    pcc="${pcc:-0x029a}"

    # Extract low/high bytes from power_on_hours hex (e.g., 0x029a -> 0x9a, 0x02)
    local poh_dec poh_lo poh_hi
    poh_dec=$(( poh ))
    poh_lo=$(printf '0x%02x' $(( poh_dec & 0xFF )))
    poh_hi=$(printf '0x%02x' $(( (poh_dec >> 8) & 0xFF )))

    local pcc_dec pcc_lo pcc_hi
    pcc_dec=$(( pcc ))
    pcc_lo=$(printf '0x%02x' $(( pcc_dec & 0xFF )))
    pcc_hi=$(printf '0x%02x' $(( (pcc_dec >> 8) & 0xFF )))

    local ide_core="${src}/hw/ide/core.c"
    local count=0
    local total=5

    # -- Add random serial number support --
    (( count++ )); atd_step ${count} ${total} "IDE core: add random header"
    if ! atd_already_patched "${ide_core}" "stdlib.h"; then
        atd_sed "${ide_core}" \
            "s/#include \"trace.h\"/#include \"trace.h\"\n#include <stdio.h>/g" \
            "Add stdio.h for random serial support"
    else
        atd_skip "stdio.h already included"
    fi

    # -- Random seed for serial numbers --
    (( count++ )); atd_step ${count} ${total} "IDE core: random serial seed"
    if ! atd_already_patched "${ide_core}" "srand(time(NULL))"; then
        atd_sed "${ide_core}" \
            "s/if (dev->serial)/srand(time(NULL));\n\tif (dev->serial)/g" \
            "Add srand() seed before serial check"
    else
        atd_skip "srand() already added"
    fi

    # -- Randomized serial format --
    (( count++ )); atd_step ${count} ${total} "IDE core: serial format ${brand}-XXXX"
    atd_sed "${ide_core}" \
        "s/QM%05d\", s->drive_serial/${brand}-%04d-aiiaicodo\", rand()%10000/g" \
        "Randomized IDE/SATA serial number format"

    # -- Firmware version from serial --
    (( count++ )); atd_step ${count} ${total} "IDE core: firmware version randomization"
    atd_sed "${ide_core}" \
        "s/qemu_hw_version()/s->drive_serial_str/g" \
        "IDE/SATA firmware version from serial string"

    # -- SMART power-on hours + cycle count --
    (( count++ )); atd_step ${count} ${total} "IDE core: SMART data (POH=${poh}, PCC=${pcc})"
    atd_sed "${ide_core}" \
        "s/0x09, 0x03, 0x00, 0x64, 0x64, 0x01, 0x00/0x09, 0x03, 0x00, 0x64, 0x64, ${poh_lo}, ${poh_hi}/g" \
        "SMART power-on hours -> ${poh}"
    atd_sed "${ide_core}" \
        "s/0x0c, 0x03, 0x00, 0x64, 0x64, 0x00, 0x00/0x0c, 0x03, 0x00, 0x64, 0x64, ${pcc_lo}, ${pcc_hi}/g" \
        "SMART power cycle count -> ${pcc}"

    atd_ok "IDE/SATA anti-detection patching complete"
    return 0
}
