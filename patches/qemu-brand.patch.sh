#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU Brand Identifiers
#  Replaces all QEMU/Bochs/KVM brand strings with configured brand
#
#  Usage: source patches/qemu-brand.patch.sh
#         patch_qemu_brand <qemu_src_dir> <brand>
# ---------------------------------------------------------------

patch_qemu_brand() {
    local src="$1"
    local brand="$2"

    atd_separator "Patching QEMU Brand Identifiers [brand=${brand}]"

    # Validate brand length
    if [[ ${#brand} -ne 4 ]]; then
        atd_err "Brand must be exactly 4 characters, got '${brand}' (${#brand} chars)"
        return 2
    fi

    local count=0
    local total=47

    # -- Block storage --
    (( count++ )); atd_step ${count} ${total} "block/vhdx.c"
    atd_sed "${src}/block/vhdx.c" \
        "s/QEMU v\" QEMU_VERSION/${brand} v\" QEMU_VERSION/g" \
        "VHDX creator tag"

    (( count++ )); atd_step ${count} ${total} "block/vvfat.c"
    atd_sed "${src}/block/vvfat.c" \
        "s/QEMU VVFAT\", 10/${brand} VVFAT\", 10/g" \
        "VVFAT OEM name"

    # -- Character devices --
    (( count++ )); atd_step ${count} ${total} "chardev/msmouse.c"
    atd_sed "${src}/chardev/msmouse.c" \
        "s/QEMU Microsoft Mouse/${brand} Microsoft Mouse/g" \
        "MS Mouse name"

    (( count++ )); atd_step ${count} ${total} "chardev/wctablet.c"
    atd_sed "${src}/chardev/wctablet.c" \
        "s/QEMU Wacom Pen Tablet/${brand} Wacom Pen Tablet/g" \
        "Wacom tablet name"

    # -- Contrib --
    (( count++ )); atd_step ${count} ${total} "contrib/vhost-user-gpu"
    atd_sed "${src}/contrib/vhost-user-gpu/vhost-user-gpu.c" \
        "s/QEMU vhost-user-gpu/${brand} vhost-user-gpu/g" \
        "vhost-user-gpu name"

    # -- ACPI identifiers --
    (( count++ )); atd_step ${count} ${total} "hw/acpi/aml-build.c (OEM IDs)"
    atd_sed "${src}/hw/acpi/aml-build.c" \
        "s/desc->oem_id/ACPI_BUILD_APPNAME6/g" \
        "ACPI OEM ID"
    atd_sed "${src}/hw/acpi/aml-build.c" \
        "s/desc->oem_table_id/ACPI_BUILD_APPNAME8/g" \
        "ACPI OEM table ID"
    atd_sed "${src}/hw/acpi/aml-build.c" \
        "s/array, ACPI_BUILD_APPNAME8/array, \"PTL \"/g" \
        "ACPI appname"
    atd_sed "${src}/hw/acpi/aml-build.c" \
        "s/\"QEMU/\"Intel/g" \
        "ACPI QEMU->Intel"

    (( count++ )); atd_step ${count} ${total} "hw/acpi/core.c"
    atd_sed "${src}/hw/acpi/core.c" \
        "s/\"QEMUQEQEMUQEMU/\"ASUSASASUSASUS/g" \
        "ACPI RSDP signature"
    atd_sed "${src}/hw/acpi/core.c" \
        "s/\"QEMU/\"${brand}/g" \
        "ACPI core brand"

    # -- ARM (nseries removed in newer QEMU) --
    (( count++ )); atd_step ${count} ${total} "hw/arm/nseries.c"
    atd_sed "${src}/hw/arm/nseries.c" \
        "s/QEMU N800/${brand} N800/g" \
        "N800 name" --allow-missing
    atd_sed "${src}/hw/arm/nseries.c" \
        "s/QEMU LCD panel/${brand} LCD panel/g" \
        "LCD panel name" --allow-missing
    atd_sed "${src}/hw/arm/nseries.c" \
        "s/strcpy((void *) w, \"QEMU \")/strcpy((void *) w, \"${brand} \")/g" \
        "nseries OEM" --allow-missing
    atd_sed "${src}/hw/arm/nseries.c" \
        "s/\"1.1.10-qemu\" : \"1.1.6-qemu\"/\"1.1.10-asus\" : \"1.1.6-asus\"/g" \
        "nseries version" --allow-missing

    (( count++ )); atd_step ${count} ${total} "hw/arm/sbsa-ref.c"
    atd_sed "${src}/hw/arm/sbsa-ref.c" \
        "s/QEMU 'SBSA Reference' ARM Virtual Machine/${brand} 'SBSA Reference' ARM Real Machine/g" \
        "SBSA machine name"

    # -- Display --
    (( count++ )); atd_step ${count} ${total} "hw/display/edid-generate.c"
    atd_sed "${src}/hw/display/edid-generate.c" \
        "s/info->vendor = \"RHT\"/info->vendor = \"DEL\"/g" \
        "EDID vendor"
    atd_sed "${src}/hw/display/edid-generate.c" \
        "s/QEMU Monitor/${brand} Monitor/g" \
        "EDID monitor name"
    atd_sed "${src}/hw/display/edid-generate.c" \
        "s/uint16_t model_nr = 0x1234;/uint16_t model_nr = 0xA05F;/g" \
        "EDID model number"

    # -- Character/Input --
    (( count++ )); atd_step ${count} ${total} "hw/char/escc.c"
    atd_sed "${src}/hw/char/escc.c" \
        "s/QEMU Sun Mouse/${brand} Sun Mouse/g" \
        "Sun Mouse name"

    # -- i386 platform --
    (( count++ )); atd_step ${count} ${total} "hw/i386/fw_cfg.c"
    atd_sed "${src}/hw/i386/fw_cfg.c" \
        "s/\"QEMU/\"${brand}/g" \
        "fw_cfg brand"

    (( count++ )); atd_step ${count} ${total} "hw/i386/pc.c"
    atd_sed "${src}/hw/i386/pc.c" \
        "s/\"QEMU Virtual CPU/\"CPU/g" \
        "Virtual CPU name"

    (( count++ )); atd_step ${count} ${total} "hw/i386/pc_piix.c"
    atd_sed "${src}/hw/i386/pc_piix.c" \
        "s/\"QEMU/\"${brand}/g" \
        "PIIX brand"
    atd_sed "${src}/hw/i386/pc_piix.c" \
        "s/Standard PC (i440FX + PIIX, 1996)/${brand} M4A88TD-Mi440fx/g" \
        "i440FX machine name"

    (( count++ )); atd_step ${count} ${total} "hw/i386/pc_q35.c"
    atd_sed "${src}/hw/i386/pc_q35.c" \
        "s/\"QEMU/\"${brand}/g" \
        "Q35 brand"
    atd_sed "${src}/hw/i386/pc_q35.c" \
        "s/Standard PC (Q35 + ICH9, 2009)/${brand} M4A88TD-Mq35/g" \
        "Q35 machine name"
    atd_sed "${src}/hw/i386/pc_q35.c" \
        "s/mc->name, pcmc->smbios_legacy_mode,/\"${brand}-PC\", pcmc->smbios_legacy_mode,/g" \
        "Q35 legacy SMBIOS name"

    # -- IDE --
    (( count++ )); atd_step ${count} ${total} "hw/ide/atapi.c"
    atd_sed "${src}/hw/ide/atapi.c" \
        "s/\"QEMU/\"${brand}/g" \
        "ATAPI brand"

    (( count++ )); atd_step ${count} ${total} "hw/ide/core.c"
    atd_sed "${src}/hw/ide/core.c" \
        "s/\"QEMU/\"${brand}/g" \
        "IDE core brand"

    # -- Input devices --
    local input_files=(
        "hw/input/adb-kbd.c"
        "hw/input/adb-mouse.c"
        "hw/input/ads7846.c"
        "hw/input/hid.c"
        "hw/input/ps2.c"
        "hw/input/tsc2005.c"
        "hw/input/tsc210x.c"
    )
    (( count++ )); atd_step ${count} ${total} "hw/input/*.c (${#input_files[@]} files)"
    for f in "${input_files[@]}"; do
        atd_sed "${src}/${f}" \
            "s/\"QEMU/\"${brand}/g" \
            "Input device brand in $(basename "${f}")" --allow-missing
    done
    atd_sed "${src}/hw/input/virtio-input-hid.c" \
        "s/\"QEMU Virtio/\"${brand}/g" \
        "Virtio input name"

    # -- M68K --
    (( count++ )); atd_step ${count} ${total} "hw/m68k/virt.c"
    atd_sed "${src}/hw/m68k/virt.c" \
        "s/QEMU M68K Virtual Machine/${brand} M68K Real Machine/g" \
        "M68K machine name"

    # -- Misc --
    (( count++ )); atd_step ${count} ${total} "hw/misc/pvpanic-isa.c"
    atd_sed "${src}/hw/misc/pvpanic-isa.c" \
        "s/\"QEMU/\"${brand}/g" \
        "pvpanic brand"

    # -- NVMe --
    (( count++ )); atd_step ${count} ${total} "hw/nvme/ctrl.c"
    atd_sed "${src}/hw/nvme/ctrl.c" \
        "s/\"QEMU/\"${brand}/g" \
        "NVMe brand"

    # -- Firmware config --
    (( count++ )); atd_step ${count} ${total} "hw/nvram/fw_cfg.c"
    atd_sed "${src}/hw/nvram/fw_cfg.c" \
        "s/0x51454d5520434647ULL/0x4155535520434647ULL/g" \
        "fw_cfg magic (QEMU CFG -> ASUS CFG)"
    (( count++ )); atd_step ${count} ${total} "hw/nvram/fw_cfg-acpi.c"
    atd_sed "${src}/hw/nvram/fw_cfg-acpi.c" \
        "s/\"QEMU/\"${brand}/g" \
        "fw_cfg ACPI brand"

    # -- PCI --
    (( count++ )); atd_step ${count} ${total} "hw/pci-host/gpex.c"
    atd_sed "${src}/hw/pci-host/gpex.c" \
        "s/\"QEMU/\"${brand}/g" \
        "GPEX brand"

    # -- PPC --
    (( count++ )); atd_step ${count} ${total} "hw/ppc/prep.c"
    atd_sed "${src}/hw/ppc/prep.c" \
        "s/\"QEMU/\"${brand}/g" \
        "PPC PREP brand"
    (( count++ )); atd_step ${count} ${total} "hw/ppc/e500plat.c"
    atd_sed "${src}/hw/ppc/e500plat.c" \
        "s/\"QEMU/\"${brand}/g" \
        "e500 brand"
    atd_sed "${src}/hw/ppc/e500plat.c" \
        "s/qemu-e500/asus-e500/g" \
        "e500 machine name"

    # -- RISC-V --
    (( count++ )); atd_step ${count} ${total} "hw/riscv/virt.c"
    atd_sed "${src}/hw/riscv/virt.c" \
        "s/\"QEMU Virtual/\"${brand}/g" \
        "RISC-V virtual name"
    atd_sed "${src}/hw/riscv/virt.c" \
        "s/\"KVM Virtual/\"${brand}/g" \
        "RISC-V KVM name"
    atd_sed "${src}/hw/riscv/virt.c" \
        "s/\"QEMU/\"${brand}/g" \
        "RISC-V brand"

    # -- SCSI --
    (( count++ )); atd_step ${count} ${total} "hw/scsi/*.c"
    atd_sed "${src}/hw/scsi/mptconfig.c" \
        "s/s16s8s16s16s16/s11s4s51s41s91/g" \
        "MPT serial format"
    atd_sed "${src}/hw/scsi/mptconfig.c" \
        "s/QEMU MPT Fusion/${brand} MPT Fusion/g" \
        "MPT product name"
    atd_sed "${src}/hw/scsi/mptconfig.c" \
        "s/\"QEMU\"/\"${brand}\"/g" \
        "MPT vendor"
    atd_sed "${src}/hw/scsi/mptconfig.c" \
        "s/0000111122223333/1145141919810000/g" \
        "MPT serial number"
    atd_sed "${src}/hw/scsi/scsi-bus.c" \
        "s/\"QEMU/\"${brand}/g" \
        "SCSI bus brand"
    atd_sed "${src}/hw/scsi/scsi-bus.c" \
        "s/qemu_hw_version()/\"666\"/g" \
        "SCSI bus version"
    atd_sed "${src}/hw/scsi/megasas.c" \
        "s/\"QEMU/\"${brand}/g" \
        "MegaSAS brand"
    atd_sed "${src}/hw/scsi/scsi-disk.c" \
        "s/\"QEMU/\"${brand}/g" \
        "SCSI disk brand"
    atd_sed "${src}/hw/scsi/scsi-disk.c" \
        "s/qemu_hw_version()/\"666\"/g" \
        "SCSI disk firmware version"
    atd_sed "${src}/hw/scsi/spapr_vscsi.c" \
        "s/\"QEMU/\"${brand}/g" \
        "sPAPR SCSI brand"

    # -- SD --
    (( count++ )); atd_step ${count} ${total} "hw/sd/sd.c"
    atd_sed "${src}/hw/sd/sd.c" \
        "s/\"QEMU/\"${brand}/g" \
        "SD card brand"

    # -- UFS --
    (( count++ )); atd_step ${count} ${total} "hw/ufs/lu.c"
    atd_sed "${src}/hw/ufs/lu.c" \
        "s/\"QEMU/\"${brand}/g" \
        "UFS brand"

    # -- USB devices --
    local usb_files=(
        "hw/usb/dev-audio.c"
        "hw/usb/dev-hid.c"
        "hw/usb/dev-hub.c"
        "hw/usb/dev-mtp.c"
        "hw/usb/dev-serial.c"
        "hw/usb/dev-smartcard-reader.c"
        "hw/usb/dev-storage.c"
        "hw/usb/dev-uas.c"
        "hw/usb/dev-wacom.c"
        "hw/usb/u2f-emulated.c"
        "hw/usb/u2f-passthru.c"
        "hw/usb/u2f.c"
    )
    (( count++ )); atd_step ${count} ${total} "hw/usb/*.c (${#usb_files[@]} files)"
    for f in "${usb_files[@]}"; do
        atd_sed "${src}/${f}" \
            "s/\"QEMU/\"${brand}/g" \
            "USB brand in $(basename "${f}")"
    done

    # USB-specific fixups
    (( count++ )); atd_step ${count} ${total} "hw/usb/dev-hub.c (serial)"
    atd_sed "${src}/hw/usb/dev-hub.c" \
        "s/314159/114514/g" \
        "USB hub serial"

    (( count++ )); atd_step ${count} ${total} "hw/usb/dev-network.c"
    atd_sed "${src}/hw/usb/dev-network.c" \
        "s/\"QEMU/\"${brand}/g" \
        "USB net brand"
    atd_sed "${src}/hw/usb/dev-network.c" \
        "s/\"RNDIS\\/QEMU/\"RNDIS\\/${brand}/g" \
        "USB RNDIS brand"
    atd_sed "${src}/hw/usb/dev-network.c" \
        "s/400102030405/400114514405/g" \
        "USB net MAC"
    atd_sed "${src}/hw/usb/dev-network.c" \
        "s/s->vendorid = 0x1234/s->vendorid = 0x8086/g" \
        "USB net vendor ID"

    (( count++ )); atd_step ${count} ${total} "hw/usb/dev-uas.c (serial)"
    atd_sed "${src}/hw/usb/dev-uas.c" \
        "s/27842/33121/g" \
        "UAS serial"

    # -- Include headers --
    (( count++ )); atd_step ${count} ${total} "include/hw/acpi/aml-build.h"
    atd_sed "${src}/include/hw/acpi/aml-build.h" \
        "s/\"BOCHS/\"INTEL/g" \
        "AML build appname BOCHS->INTEL"
    atd_sed "${src}/include/hw/acpi/aml-build.h" \
        "s/\"BXPC/\"PC8086/g" \
        "AML build table ID"

    (( count++ )); atd_step ${count} ${total} "include/standard-headers fw_cfg"
    atd_sed "${src}/include/standard-headers/linux/qemu_fw_cfg.h" \
        "s/\"QEMU0002/\"${brand}0002/g" \
        "fw_cfg device name"
    atd_sed "${src}/include/standard-headers/linux/qemu_fw_cfg.h" \
        "s/0x51454d5520434647ULL/0x4155535520434647ULL/g" \
        "fw_cfg signature"

    # -- Migration --
    (( count++ )); atd_step ${count} ${total} "migration/*.c"
    atd_sed "${src}/migration/migration.c" \
        "s/\"QEMU/\"${brand}/g" \
        "Migration brand"
    atd_sed "${src}/migration/rdma.c" \
        "s/\"QEMU/\"${brand}/g" \
        "RDMA brand"

    # -- Option ROM --
    (( count++ )); atd_step ${count} ${total} "pc-bios/optionrom"
    atd_sed "${src}/pc-bios/optionrom/optionrom.h" \
        "s/0x51454d5520434647ULL/0x4155535520434647ULL/g" \
        "Option ROM signature"

    # -- S390 --
    (( count++ )); atd_step ${count} ${total} "pc-bios/s390-ccw"
    atd_sed "${src}/pc-bios/s390-ccw/virtio-scsi.h" \
        "s/\"QEMU/\"${brand}/g" \
        "S390 SCSI brand"

    # -- SeaBIOS --
    (( count++ )); atd_step ${count} ${total} "roms/seabios"
    atd_sed "${src}/roms/seabios/src/fw/ssdt-misc.dsl" \
        "s/\"QEMU/\"${brand}/g" \
        "SeaBIOS SSDT brand" --allow-missing
    atd_sed "${src}/roms/seabios-hppa/src/fw/ssdt-misc.dsl" \
        "s/\"QEMU/\"${brand}/g" \
        "SeaBIOS HPPA SSDT brand" --allow-missing

    # -- Target architectures --
    (( count++ )); atd_step ${count} ${total} "target/i386/cpu.c"
    atd_sed "${src}/target/i386/cpu.c" \
        "s/\"QEMU TCG CPU version/\"TCG CPU version/g" \
        "TCG CPU version string"
    atd_sed "${src}/target/i386/cpu.c" \
        "s/\"Microsoft Hv/\"GenuineIntel/g" \
        "Hyper-V CPUID -> GenuineIntel (fixes nVidia code 43)"

    (( count++ )); atd_step ${count} ${total} "target/i386/kvm/kvm.c"
    atd_sed "${src}/target/i386/kvm/kvm.c" \
        "s/KVMKVMKVM\\\\\\\\0\\\\\\\\0\\\\\\\\0/\\\\\\\\1\\\\\\\\0\\\\\\\\0\\\\\\\\0\\\\\\\\0\\\\\\\\0\\\\\\\\0\\\\\\\\0\\\\\\\\0\\\\\\\\0\\\\\\\\0\\\\\\\\0/g" \
        "KVM hypervisor signature nullification"

    (( count++ )); atd_step ${count} ${total} "target/s390x"
    atd_sed "${src}/target/s390x/tcg/misc_helper.c" \
        "s/QEMUQEMUQEMUQEMU/ASUSASUSASUSASUS/g" \
        "S390X STSI brand"
    atd_sed "${src}/target/s390x/tcg/misc_helper.c" \
        "s/\"QEMU/\"${brand}/g" \
        "S390X misc brand"
    atd_sed "${src}/target/s390x/tcg/misc_helper.c" \
        "s/\"KVM/\"ATX/g" \
        "S390X KVM->ATX"

    atd_ok "QEMU brand patching complete (${brand})"
    return 0
}
