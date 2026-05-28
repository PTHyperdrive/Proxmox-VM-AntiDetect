#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU USB/SCSI Anti-Detection
#  Patches USB device IDs and SCSI identifiers
#
#  Usage: source patches/qemu-usb-scsi.patch.sh
#         patch_qemu_usb_scsi <qemu_src_dir> <config_file>
# ---------------------------------------------------------------

patch_qemu_usb_scsi() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching QEMU USB/SCSI Device IDs"

    local count=0
    local total=3

    # -- SPD EEPROM (realistic DDR4-3200 16GB UDIMM SPD data) --
    (( count++ )); atd_step ${count} ${total} "hw/i2c/smbus_eeprom.c (memory SPD)"
    if ! atd_already_patched "${src}/hw/i2c/smbus_eeprom.c" "eeprom_buf\[0\]=0x23"; then
        atd_sed "${src}/hw/i2c/smbus_eeprom.c" \
            "s/for (i = 0; i < nb_eeprom/eeprom_buf[0]=0x23;\neeprom_buf[1]=0x12;\neeprom_buf[2]=0x0C;\neeprom_buf[3]=0x02;\neeprom_buf[4]=0x46;\neeprom_buf[5]=0x29;\neeprom_buf[6]=0x02;\neeprom_buf[7]=0x08;\neeprom_buf[8]=0x00;\neeprom_buf[9]=0x60;\neeprom_buf[0x0a]=0x00;\neeprom_buf[0x0b]=0x03;\neeprom_buf[0x0c]=0x09;\neeprom_buf[0x0d]=0x03;\neeprom_buf[0x0e]=0x00;\neeprom_buf[0x0f]=0x00;\neeprom_buf[0x10]=0x00;\neeprom_buf[0x11]=0x00;\neeprom_buf[0x12]=0x06;\neeprom_buf[0x13]=0x0D;\neeprom_buf[0x14]=0xFC;\neeprom_buf[0x15]=0x1B;\neeprom_buf[0x16]=0x00;\neeprom_buf[0x17]=0x00;\neeprom_buf[0x18]=0x6E;\neeprom_buf[0x19]=0x6E;\neeprom_buf[0x1a]=0x6E;\neeprom_buf[0x1b]=0x11;\neeprom_buf[0x1c]=0x00;\neeprom_buf[0x1d]=0x6E;\neeprom_buf[0x1e]=0xF0;\neeprom_buf[0x1f]=0x01;\neeprom_buf[0x20]=0x20;\neeprom_buf[0x21]=0x01;\neeprom_buf[0x22]=0x58;\neeprom_buf[0x23]=0x00;\neeprom_buf[0x24]=0x78;\neeprom_buf[0x25]=0x00;\neeprom_buf[0x26]=0x3C;\neeprom_buf[0x27]=0x3C;\neeprom_buf[0x28]=0x00;\neeprom_buf[0x3c]=0x0F;\neeprom_buf[0x3d]=0x11;\neeprom_buf[0x3e]=0x65;\neeprom_buf[0x3f]=0x00;\neeprom_buf[0x75]=0x01;\neeprom_buf[0x76]=0x98;\neeprom_buf[0x77]=0x07;\neeprom_buf[0x78]=0x25;\neeprom_buf[0x79]=0x18;\neeprom_buf[0x7a]=0x00;\neeprom_buf[0x7b]=0x00;\neeprom_buf[0x7c]=0x00;\neeprom_buf[0x7d]=0x00;\neeprom_buf[0x7e]=0x3D;\neeprom_buf[0x7f]=0xA7;\neeprom_buf[0x80]=0x4B;\neeprom_buf[0x81]=0x46;\neeprom_buf[0x82]=0x34;\neeprom_buf[0x83]=0x33;\neeprom_buf[0x84]=0x32;\neeprom_buf[0x85]=0x30;\neeprom_buf[0x86]=0x43;\neeprom_buf[0x87]=0x31;\neeprom_buf[0x88]=0x36;\neeprom_buf[0x89]=0x42;\neeprom_buf[0x8a]=0x42;\neeprom_buf[0x8b]=0x2F;\neeprom_buf[0x8c]=0x31;\neeprom_buf[0x8d]=0x36;\neeprom_buf[0x8e]=0x47;\neeprom_buf[0x8f]=0x20;\neeprom_buf[0x90]=0x20;\neeprom_buf[0x91]=0x20;\neeprom_buf[0x92]=0x00;\neeprom_buf[0x93]=0x00;\neeprom_buf[0x94]=0x00;\neeprom_buf[0x95]=0x00;\neeprom_buf[0xfe]=0x00;\neeprom_buf[0xff]=0x5A;\nfor (i = 0; i < nb_eeprom/g" \
            "Inject realistic DDR4-3200 16GB UDIMM SPD data (Kingston Fury)"
    else
        atd_skip "SPD EEPROM data already patched"
    fi

    # -- PCI device IDs (USB controller) --
    (( count++ )); atd_step ${count} ${total} "include/hw/pci/pci_ids.h (USB IDs)"
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/0x293/0x993/g" \
        "USB controller PCI IDs 0x293x -> 0x993x"
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/0x9930/0x2930/g" \
        "Restore 0x2930 (ICH9 base)"

    # -- HDA audio codec vendor --
    (( count++ )); atd_step ${count} ${total} "hw/audio/hda-codec.c (HDA vendor)"
    atd_sed "${src}/hw/audio/hda-codec.c" \
        "s/0x1af4/0x8086/g" \
        "HDA vendor ID 0x1af4 -> 0x8086 (Intel)"

    atd_ok "USB/SCSI device ID patching complete"
    return 0
}
