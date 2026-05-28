#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU SMBIOS Hardware Values
#  Patches SMBIOS type 0/4/16/17 hardware-realistic values
#
#  Usage: source patches/qemu-smbios.patch.sh
#         patch_qemu_smbios <qemu_src_dir> <config_file>
# ---------------------------------------------------------------

patch_qemu_smbios() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching QEMU SMBIOS Hardware Values"

    # Read config values
    local proc_family proc_chars voltage ext_clock
    local l1_handle l2_handle l3_handle
    local mem_type total_w data_w min_v max_v cfg_v
    local mem_loc mem_err

    proc_family="$(atd_config_get "${cfg}" smbios_type4 processor_family)"
    proc_chars="$(atd_config_get "${cfg}" smbios_type4 processor_characteristics)"
    voltage="$(atd_config_get "${cfg}" smbios_type4 voltage)"
    ext_clock="$(atd_config_get "${cfg}" smbios_type4 external_clock)"
    l1_handle="$(atd_config_get "${cfg}" smbios_type4 l1_cache_handle)"
    l2_handle="$(atd_config_get "${cfg}" smbios_type4 l2_cache_handle)"
    l3_handle="$(atd_config_get "${cfg}" smbios_type4 l3_cache_handle)"

    mem_type="$(atd_config_get "${cfg}" smbios_type17 memory_type)"
    total_w="$(atd_config_get "${cfg}" smbios_type17 total_width)"
    data_w="$(atd_config_get "${cfg}" smbios_type17 data_width)"
    min_v="$(atd_config_get "${cfg}" smbios_type17 minimum_voltage)"
    max_v="$(atd_config_get "${cfg}" smbios_type17 maximum_voltage)"
    cfg_v="$(atd_config_get "${cfg}" smbios_type17 configured_voltage)"
    mem_loc="$(atd_config_get "${cfg}" smbios_type17 location)"
    mem_err="$(atd_config_get "${cfg}" smbios_type17 error_correction)"

    # Defaults
    proc_family="${proc_family:-0xC6}"; proc_chars="${proc_chars:-0x04}"
    voltage="${voltage:-0x8B}"; ext_clock="${ext_clock:-100}"
    l1_handle="${l1_handle:-0x0039}"; l2_handle="${l2_handle:-0x003A}"; l3_handle="${l3_handle:-0x003B}"
    mem_type="${mem_type:-0x1A}"; total_w="${total_w:-64}"; data_w="${data_w:-64}"
    min_v="${min_v:-1200}"; max_v="${max_v:-1200}"; cfg_v="${cfg_v:-1200}"
    mem_loc="${mem_loc:-0x03}"; mem_err="${mem_err:-0x03}"

    local smbios_c="${src}/hw/smbios/smbios.c"
    local count=0
    local total=14

    # -- BIOS characteristics extension --
    (( count++ )); atd_step ${count} ${total} "BIOS characteristics extension byte"
    atd_sed "${smbios_c}" \
        "s/t->bios_characteristics_extension_bytes\[1\] = 0x14;/t->bios_characteristics_extension_bytes[1] = 0x0F;/g" \
        "BIOS ext byte 0x14->0x0F (real hardware pattern)"

    # -- Processor voltage --
    (( count++ )); atd_step ${count} ${total} "Processor voltage -> ${voltage}"
    atd_sed "${smbios_c}" \
        "s/t->voltage = 0;/t->voltage = ${voltage};/g" \
        "Processor voltage"

    # -- External clock --
    (( count++ )); atd_step ${count} ${total} "External clock -> ${ext_clock}MHz"
    atd_sed "${smbios_c}" \
        "s/t->external_clock = cpu_to_le16(0);/t->external_clock = cpu_to_le16(${ext_clock});/g" \
        "External clock"

    # -- Cache handles --
    (( count++ )); atd_step ${count} ${total} "L1 cache handle -> ${l1_handle}"
    atd_sed "${smbios_c}" \
        "s/t->l1_cache_handle = cpu_to_le16(0xFFFF);/t->l1_cache_handle = cpu_to_le16(${l1_handle});/g" \
        "L1 cache handle"

    (( count++ )); atd_step ${count} ${total} "L2 cache handle -> ${l2_handle}"
    atd_sed "${smbios_c}" \
        "s/t->l2_cache_handle = cpu_to_le16(0xFFFF);/t->l2_cache_handle = cpu_to_le16(${l2_handle});/g" \
        "L2 cache handle"

    (( count++ )); atd_step ${count} ${total} "L3 cache handle -> ${l3_handle}"
    atd_sed "${smbios_c}" \
        "s/t->l3_cache_handle = cpu_to_le16(0xFFFF);/t->l3_cache_handle = cpu_to_le16(${l3_handle});/g" \
        "L3 cache handle"

    # -- Processor family --
    (( count++ )); atd_step ${count} ${total} "Processor family -> ${proc_family}"
    atd_sed "${smbios_c}" \
        "s/t->processor_family = 0x01;/t->processor_family = ${proc_family};/g" \
        "Processor family"

    # -- Processor characteristics --
    (( count++ )); atd_step ${count} ${total} "Processor characteristics -> ${proc_chars}"
    atd_sed "${smbios_c}" \
        "s/t->processor_characteristics = cpu_to_le16(0x02);/t->processor_characteristics = cpu_to_le16(${proc_chars});/g" \
        "Processor characteristics"

    # -- Memory type --
    (( count++ )); atd_step ${count} ${total} "Memory type -> ${mem_type}"
    atd_sed "${smbios_c}" \
        "s/t->memory_type = 0x07;/t->memory_type = ${mem_type};/g" \
        "Memory type"

    # -- Memory width --
    (( count++ )); atd_step ${count} ${total} "Memory width -> ${total_w}/${data_w}"
    atd_sed "${smbios_c}" \
        "s/t->total_width = cpu_to_le16(0xFFFF);/t->total_width = cpu_to_le16(${total_w});/g" \
        "Memory total width"
    atd_sed "${smbios_c}" \
        "s/t->data_width = cpu_to_le16(0xFFFF);/t->data_width = cpu_to_le16(${data_w});/g" \
        "Memory data width"

    # -- Memory voltages --
    (( count++ )); atd_step ${count} ${total} "Memory voltages -> ${min_v}/${max_v}/${cfg_v}mV"
    atd_sed "${smbios_c}" \
        "s/t->minimum_voltage = cpu_to_le16(0);/t->minimum_voltage = cpu_to_le16(${min_v});/g" \
        "Memory minimum voltage"
    atd_sed "${smbios_c}" \
        "s/t->maximum_voltage = cpu_to_le16(0);/t->maximum_voltage = cpu_to_le16(${max_v});/g" \
        "Memory maximum voltage"
    atd_sed "${smbios_c}" \
        "s/t->configured_voltage = cpu_to_le16(0);/t->configured_voltage = cpu_to_le16(${cfg_v});/g" \
        "Memory configured voltage"

    # -- Memory location --
    (( count++ )); atd_step ${count} ${total} "Physical memory array location -> ${mem_loc}"
    atd_sed "${smbios_c}" \
        "s/t->location = 0x01;/t->location = ${mem_loc};/g" \
        "Physical memory array location"

    # -- Memory error correction --
    (( count++ )); atd_step ${count} ${total} "Memory error correction -> ${mem_err}"
    atd_sed "${smbios_c}" \
        "s/t->error_correction = 0x06;/t->error_correction = ${mem_err};/g" \
        "Memory error correction type"

    atd_ok "QEMU SMBIOS hardware values patched"
    return 0
}
