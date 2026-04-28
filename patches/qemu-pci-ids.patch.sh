#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU PCI Vendor/Device IDs
#  Patches PCI IDs that reveal virtual hardware
#
#  Usage: source patches/qemu-pci-ids.patch.sh
#         patch_qemu_pci_ids <qemu_src_dir> <config_file>
# ---------------------------------------------------------------

patch_qemu_pci_ids() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching QEMU PCI Vendor/Device IDs"

    local count=0
    local total=2

    # Note: We intentionally do NOT patch PCI_VENDOR_ID_REDHAT (0x1af4)
    # or PCI_VENDOR_ID_REDHAT (0x1b36) as this breaks virtio, SCSI, and
    # virtioNET/virtioBlock device drivers. Only SUBVENDOR is safe to touch.
    # The user should avoid using virtio devices entirely for anti-detection.

    # -- IGD passthrough fix --
    (( count++ )); atd_step ${count} ${total} "hw/vfio/igd.c (GPU passthrough fix)"
    atd_sed "${src}/hw/vfio/igd.c" \
        "s/!object_dynamic_cast/object_dynamic_cast/g" \
        "Fix IGD/GPU passthrough logic inversion"

    # -- Bootsplash customization --
    (( count++ )); atd_step ${count} ${total} "pc-bios/meson.build + fw_cfg.c (bootsplash)"
    atd_sed "${src}/pc-bios/meson.build" \
        "s/vgabios.bin/vgabios.bin',\n\t'bootsplash.jpg/g" \
        "Add bootsplash.jpg to BIOS assets"
    atd_sed "${src}/hw/nvram/fw_cfg.c" \
        "s/current_machine->boot_config.splash;/\"\/usr\/share\/kvm\/bootsplash.jpg\";/g" \
        "Force custom bootsplash path"

    atd_ok "PCI ID and passthrough patching complete"
    return 0
}
