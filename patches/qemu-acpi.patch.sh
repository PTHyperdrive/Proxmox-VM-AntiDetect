#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU ACPI Anti-Detection
#  Patches ACPI tables, FADT revision, vmgenid, fw_cfg, DSDT
#
#  Usage: source patches/qemu-acpi.patch.sh
#         patch_qemu_acpi <qemu_src_dir> <config_file>
# ---------------------------------------------------------------

patch_qemu_acpi() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching QEMU ACPI Tables"

    local fadt_rev
    fadt_rev="$(atd_config_get "${cfg}" acpi fadt_revision)"
    fadt_rev="${fadt_rev:-4}"
    local ssdt_rev
    ssdt_rev="$(atd_config_get "${cfg}" acpi ssdt_revision)"
    ssdt_rev="${ssdt_rev:-3}"
    local c_lat
    c_lat="$(atd_config_get "${cfg}" acpi c_state_latency)"
    c_lat="${c_lat:-0x1fff}"

    local count=0
    local total=8

    # -- vmgenid: disable SSDT generation --
    (( count++ )); atd_step ${count} ${total} "hw/acpi/vmgenid.c (disable vmgenid SSDT)"
    if ! atd_already_patched "${src}/hw/acpi/vmgenid.c" "do this once"; then
        atd_sed "${src}/hw/acpi/vmgenid.c" \
            's/    Aml \*ssdt/       \/\/PATCHED by proxmox-atd\n       return;\/\/do this once\n    Aml \*ssdt/g' \
            "Disable vmgenid SSDT generation"
    else
        atd_skip "vmgenid.c already patched"
    fi

    # -- acpi-build: disable debug AML + fw_cfg ACPI --
    (( count++ )); atd_step ${count} ${total} "hw/i386/acpi-build.c (debug AML)"
    if ! atd_already_patched "${src}/hw/i386/acpi-build.c" "do this once"; then
        atd_sed "${src}/hw/i386/acpi-build.c" \
            '/static void build_dbg_aml(Aml \*table)/,/ /s/{/{\n     return;\/\/do this once/g' \
            "Disable debug AML builder"
        atd_sed "${src}/hw/i386/acpi-build.c" \
            '/create fw_cfg node/,/}/s/}/}*\//g' \
            "Comment out fw_cfg ACPI node (close)"
        atd_sed "${src}/hw/i386/acpi-build.c" \
            '/create fw_cfg node/,/}/s/{/\/*{/g' \
            "Comment out fw_cfg ACPI node (open)"
    else
        atd_skip "acpi-build.c debug+fw_cfg already patched"
    fi

    # -- FADT revision upgrade --
    (( count++ )); atd_step ${count} ${total} "hw/i386/acpi-build.c (FADT rev ${fadt_rev})"
    atd_sed "${src}/hw/i386/acpi-build.c" \
        "s/rev = 3/rev = ${fadt_rev}/g" \
        "FADT revision 3 -> ${fadt_rev}"
    atd_sed "${src}/hw/i386/acpi-build.c" \
        "s/fadt.rev = 1/fadt.rev = ${fadt_rev}/g" \
        "FADT inner revision -> ${fadt_rev}"

    # -- FADT sleep control/status registers --
    # NOTE: uses single-quoted sed to avoid bash/sed & backreference issues.
    # Only replace FIRST occurrence (no /g flag) to prevent cascading corruption.
    (( count++ )); atd_step ${count} ${total} "hw/acpi/aml-build.c (FADT sleep regs)"
    if ! atd_already_patched "${src}/hw/acpi/aml-build.c" "rev <= 6"; then
        if (( ATD_DRY_RUN )); then
            atd_dry "sed -i 's/if (f->rev <= 4) {/...add sleep_ctl+sleep_sts.../' ${src}/hw/acpi/aml-build.c"
        else
            sed -i '0,/if (f->rev <= 4) {/{s/if (f->rev <= 4) {/if (f->rev <= 6) {\n\t\tbuild_append_gas_from_struct(tbl, \&f->sleep_ctl);\n\t\tbuild_append_gas_from_struct(tbl, \&f->sleep_sts);/}' "${src}/hw/acpi/aml-build.c"
            atd_debug "Patched: FADT sleep control/status registers"
        fi
    else
        atd_skip "FADT sleep registers already patched"
    fi

    # -- C-state latency --
    (( count++ )); atd_step ${count} ${total} "hw/i386/acpi-build.c (C-state latency)"
    atd_sed "${src}/hw/i386/acpi-build.c" \
        "s/lat = 0xfff/lat = ${c_lat}/g" \
        "C-state latency -> ${c_lat}"

    # -- WAET table signature --
    (( count++ )); atd_step ${count} ${total} "hw/i386/acpi-build.c (WAET -> WWWT)"
    atd_sed "${src}/hw/i386/acpi-build.c" \
        "s/\"WAET\"/\"WWWT\"/g" \
        "WAET table rename"

    # -- SSDT/DSDT revision --
    (( count++ )); atd_step ${count} ${total} "hw/i386/acpi-build.c (SSDT rev ${ssdt_rev})"
    atd_sed "${src}/hw/i386/acpi-build.c" \
        "s/rev = 1/rev = ${ssdt_rev}/g" \
        "SSDT/DSDT minimum revision -> ${ssdt_rev}"

    # -- DSDT _OSI + _TZ + _PTS (Windows 2012/2013 compatibility) --
    (( count++ )); atd_step ${count} ${total} "hw/i386/acpi-build.c (DSDT _OSI/_TZ/_PTS)"
    atd_sed "${src}/hw/i386/acpi-build.c" \
        's/dev = aml_device("PCI0");/aml_append(sb_scope, aml_name_decl("OSYS", aml_int(0x03E8)));\n\tAml *osi = aml_if(aml_equal(aml_call1("_OSI", aml_string("Windows 2012")), aml_int(1)));\n\taml_append(osi, aml_store(aml_int(0x07DC), aml_name("OSYS")));\n\taml_append(sb_scope, osi);\n\tosi = aml_if(aml_equal(aml_call1("_OSI",aml_string("Windows 2013")), aml_int(1)));\n\taml_append(osi, aml_store(aml_int(0x07DD), aml_name("OSYS")));\n\taml_append(sb_scope, osi);\n\taml_append(sb_scope, aml_name_decl("_TZ", aml_int(0x03E8)));\n\taml_append(sb_scope, aml_name_decl("_PTS", aml_int(0x03E8)));\n\tdev = aml_device("PCI0");/g' \
        "Add _OSI Windows 2012/2013, _TZ, _PTS to DSDT"

    atd_ok "QEMU ACPI patching complete"
    return 0
}
