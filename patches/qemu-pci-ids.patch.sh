#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU PCI Vendor/Device IDs
#  Patches PCI IDs that reveal virtual hardware to appear as
#  real Intel hardware (Cannon Lake / Coffee Lake era)
#
#  Targets:
#    - PCI_VENDOR_ID_REDHAT (0x1b36) → Intel (0x8086)
#    - PCI_SUBVENDOR_ID_REDHAT_QUMRANET (0x1af4) → Intel (0x8086)
#    - QEMU-specific device IDs → matching Intel Cannon Lake IDs
#    - QXL display vendor → Intel UHD Graphics
#    - IGD passthrough fix + bootsplash customization
#
#  SAFETY NOTE:
#    Changing PCI_VENDOR_ID_REDHAT is safe ONLY when the VM does
#    NOT use VirtIO devices. The deploy script uses SATA + e1000.
#    VirtIO devices use PCI_VENDOR_ID_REDHAT_QUMRANET (0x1af4)
#    which is NOT changed by this patch.
#
#  Usage: source patches/qemu-pci-ids.patch.sh
#         patch_qemu_pci_ids <qemu_src_dir> <config_file>
# ---------------------------------------------------------------

patch_qemu_pci_ids() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching QEMU PCI Vendor/Device IDs"

    # Read PCI override values from config (with Intel Cannon Lake defaults)
    local pci_vendor pci_subvendor
    local pcie_rp_devid xhci_devid pci_bridge_devid pcie_bridge_devid
    local qxl_devid pvpanic_devid nvme_devid

    if [[ -n "${cfg}" ]] && [[ -f "${cfg}" ]]; then
        pci_vendor="$(atd_config_get "${cfg}" pci vendor_id)"
        pci_subvendor="$(atd_config_get "${cfg}" pci subvendor_id)"
        pcie_rp_devid="$(atd_config_get "${cfg}" pci pcie_root_port)"
        xhci_devid="$(atd_config_get "${cfg}" pci xhci)"
        pci_bridge_devid="$(atd_config_get "${cfg}" pci pci_bridge)"
        pcie_bridge_devid="$(atd_config_get "${cfg}" pci pcie_bridge)"
        qxl_devid="$(atd_config_get "${cfg}" pci qxl)"
        pvpanic_devid="$(atd_config_get "${cfg}" pci pvpanic)"
        nvme_devid="$(atd_config_get "${cfg}" pci nvme)"
    fi

    # Intel Cannon Lake / Coffee Lake defaults
    pci_vendor="${pci_vendor:-0x8086}"
    pci_subvendor="${pci_subvendor:-0x8086}"
    pcie_rp_devid="${pcie_rp_devid:-0xA394}"       # Intel Cannon Lake PCIe Root Port
    xhci_devid="${xhci_devid:-0xA36D}"              # Intel Cannon Lake xHCI USB 3.1
    pci_bridge_devid="${pci_bridge_devid:-0x244E}"   # Intel 82801 PCI Bridge
    pcie_bridge_devid="${pcie_bridge_devid:-0x2448}"  # Intel 82801 Mobile PCIe-to-PCI Bridge
    qxl_devid="${qxl_devid:-0x5917}"                 # Intel UHD Graphics 620
    pvpanic_devid="${pvpanic_devid:-0x8C4E}"         # Intel Q87 LPC Controller (innocuous)
    nvme_devid="${nvme_devid:-0xF1A8}"               # Intel SSD 660p NVMe

    local count=0
    local total=10

    # =================================================================
    #  1. PCI_VENDOR_ID_REDHAT: 0x1b36 → Intel (0x8086)
    # =================================================================
    # This is the primary QEMU vendor ID used for:
    #   - PCIe Root Port (0x000c)
    #   - XHCI USB (0x000d)
    #   - PCI bridges (0x0001, 0x000a, 0x000b, 0x000e)
    #   - NVMe (0x0010), pvpanic (0x0011), QXL (0x0100), etc.
    #
    # Windows uses generic PCI bus drivers for bridges and ports —
    # they are vendor-agnostic. The XHCI controller uses the same
    # standard xHCI spec regardless of vendor ID. Safe to change.
    #
    # NOTE: PCI_VENDOR_ID_REDHAT_QUMRANET (0x1af4) for VirtIO is
    # defined in pci.h, NOT in pci_ids.h, and is NOT changed here.
    # VirtIO devices keep working (not that we use them).

    (( count++ )); atd_step ${count} ${total} "include/hw/pci/pci.h (PCI_VENDOR_ID_REDHAT)"

    # Change PCI_VENDOR_ID_REDHAT 0x1b36 → Intel
    atd_sed "${src}/include/hw/pci/pci.h" \
        "s/#define PCI_VENDOR_ID_REDHAT             0x1b36/#define PCI_VENDOR_ID_REDHAT             ${pci_vendor}/g" \
        "PCI_VENDOR_ID_REDHAT 0x1b36 → ${pci_vendor} (Intel)"

    # =================================================================
    #  2. PCI_SUBVENDOR_ID_REDHAT_QUMRANET: 0x1af4 → Intel (0x8086)
    # =================================================================
    # This is the SUBSYSTEM vendor ID. VMAware checks for SUBSYS_11001AF4.
    # Changing the subvendor does NOT affect VirtIO device functionality —
    # VirtIO drivers bind on the primary vendor ID, not the subvendor.

    (( count++ )); atd_step ${count} ${total} "include/hw/pci/pci.h (PCI_SUBVENDOR_ID)"
    atd_sed "${src}/include/hw/pci/pci.h" \
        "s/#define PCI_SUBVENDOR_ID_REDHAT_QUMRANET 0x1af4/#define PCI_SUBVENDOR_ID_REDHAT_QUMRANET ${pci_subvendor}/g" \
        "PCI_SUBVENDOR_ID 0x1af4 → ${pci_subvendor} (Intel)"

    # =================================================================
    #  3. QEMU-specific device IDs → Intel Cannon Lake equivalents
    # =================================================================
    # These are in include/hw/pci/pci_ids.h or in individual device .c files.
    # We remap to real Intel device IDs so Windows Device Manager shows
    # "Intel(R) ..." instead of "Red Hat QEMU ..."

    (( count++ )); atd_step ${count} ${total} "include/hw/pci/pci_ids.h (QEMU device IDs)"

    # PCIe Root Port: 0x000c → Intel Cannon Lake RP
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/PCI_DEVICE_ID_REDHAT_PCIE_RP    0x000c/PCI_DEVICE_ID_REDHAT_PCIE_RP    ${pcie_rp_devid}/g" \
        "PCIe Root Port → ${pcie_rp_devid} (Intel Cannon Lake RP)" --allow-missing

    # XHCI USB: 0x000d → Intel Cannon Lake xHCI
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/PCI_DEVICE_ID_REDHAT_XHCI       0x000d/PCI_DEVICE_ID_REDHAT_XHCI       ${xhci_devid}/g" \
        "XHCI USB → ${xhci_devid} (Intel Cannon Lake xHCI)" --allow-missing

    # PCI-PCI Bridge: 0x0001 → Intel 82801 PCI Bridge
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/PCI_DEVICE_ID_REDHAT_BRIDGE     0x0001/PCI_DEVICE_ID_REDHAT_BRIDGE     ${pci_bridge_devid}/g" \
        "PCI Bridge → ${pci_bridge_devid} (Intel 82801)" --allow-missing

    # PCIe-to-PCI Bridge: 0x000e → Intel 82801 Mobile
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/PCI_DEVICE_ID_REDHAT_PCIE_BRIDGE 0x000e/PCI_DEVICE_ID_REDHAT_PCIE_BRIDGE ${pcie_bridge_devid}/g" \
        "PCIe-to-PCI Bridge → ${pcie_bridge_devid} (Intel 82801 Mobile)" --allow-missing

    # QXL display: 0x0100 → Intel UHD Graphics
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/PCI_DEVICE_ID_REDHAT_QXL        0x0100/PCI_DEVICE_ID_REDHAT_QXL        ${qxl_devid}/g" \
        "QXL → ${qxl_devid} (Intel UHD Graphics 620)" --allow-missing

    # pvpanic: 0x0011 → innocuous Intel LPC ID
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/PCI_DEVICE_ID_REDHAT_PVPANIC    0x0011/PCI_DEVICE_ID_REDHAT_PVPANIC    ${pvpanic_devid}/g" \
        "pvpanic → ${pvpanic_devid}" --allow-missing

    # NVMe: 0x0010 → Intel SSD 660p
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/PCI_DEVICE_ID_REDHAT_NVME       0x0010/PCI_DEVICE_ID_REDHAT_NVME       ${nvme_devid}/g" \
        "NVMe → ${nvme_devid} (Intel SSD 660p)" --allow-missing

    # =================================================================
    #  4. Hardcoded 0x1b36 references in device source files
    # =================================================================
    # Some device files hardcode the vendor ID directly instead of using
    # the PCI_VENDOR_ID_REDHAT macro. Patch those too.

    (( count++ )); atd_step ${count} ${total} "Hardcoded 0x1b36 in device sources"

    # hw/display/qxl.c — QXL device hardcodes vendor
    atd_sed "${src}/hw/display/qxl.c" \
        "s/0x1b36/${pci_vendor}/g" \
        "QXL hardcoded vendor" --allow-missing

    # hw/usb/hcd-xhci-pci.c — XHCI hardcodes vendor
    atd_sed "${src}/hw/usb/hcd-xhci-pci.c" \
        "s/0x1b36/${pci_vendor}/g" \
        "XHCI hardcoded vendor" --allow-missing

    # hw/pci-bridge/pci_expander_bridge.c — PXB hardcodes vendor
    atd_sed "${src}/hw/pci-bridge/pci_expander_bridge.c" \
        "s/0x1b36/${pci_vendor}/g" \
        "PXB hardcoded vendor" --allow-missing

    # hw/misc/pvpanic-pci.c — pvpanic hardcodes vendor
    atd_sed "${src}/hw/misc/pvpanic-pci.c" \
        "s/0x1b36/${pci_vendor}/g" \
        "pvpanic hardcoded vendor" --allow-missing

    # hw/nvme/ctrl.c — NVMe hardcodes vendor (separate from brand patch)
    atd_sed "${src}/hw/nvme/ctrl.c" \
        "s/0x1b36/${pci_vendor}/g" \
        "NVMe hardcoded vendor" --allow-missing

    # hw/pci-bridge/pcie_root_port.c — PCIe Root Port
    atd_sed "${src}/hw/pci-bridge/pcie_root_port.c" \
        "s/0x1b36/${pci_vendor}/g" \
        "PCIe Root Port hardcoded vendor" --allow-missing

    # hw/acpi/erst.c — ACPI ERST device
    atd_sed "${src}/hw/acpi/erst.c" \
        "s/0x1b36/${pci_vendor}/g" \
        "ERST hardcoded vendor" --allow-missing

    # =================================================================
    #  5. Subsystem ID 0x1100 (VirtIO default subsystem device ID)
    # =================================================================
    # VMAware checks for SUBSYS_11001AF4. We already changed the subvendor
    # above. The device subsystem ID 0x1100 is generic enough to keep.

    (( count++ )); atd_step ${count} ${total} "PCI subsystem IDs"
    atd_sed "${src}/include/hw/pci/pci.h" \
        "s/PCI_SUBSYSTEM_ID_QEMU           0x1100/PCI_SUBSYSTEM_ID_QEMU           0x7270/g" \
        "Subsystem device ID 0x1100 → 0x7270 (Intel 82371AB)" --allow-missing

    # =================================================================
    #  6. USB controller PCI IDs (ICH9 UHCI/EHCI range)
    # =================================================================
    # These are already handled in qemu-usb-scsi.patch.sh but we keep
    # the original patches here too for the 0x293x range.

    (( count++ )); atd_step ${count} ${total} "include/hw/pci/pci_ids.h (USB controller IDs)"
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/0x293/0x993/g" \
        "USB controller PCI IDs 0x293x → 0x993x"
    atd_sed "${src}/include/hw/pci/pci_ids.h" \
        "s/0x9930/0x2930/g" \
        "Restore 0x2930 (ICH9 base)"

    # =================================================================
    #  7. IGD passthrough fix
    # =================================================================
    (( count++ )); atd_step ${count} ${total} "hw/vfio/igd.c (GPU passthrough fix)"
    atd_sed "${src}/hw/vfio/igd.c" \
        "s/!object_dynamic_cast/object_dynamic_cast/g" \
        "Fix IGD/GPU passthrough logic inversion"

    # =================================================================
    #  8. Bootsplash customization
    # =================================================================
    (( count++ )); atd_step ${count} ${total} "pc-bios/meson.build + fw_cfg.c (bootsplash)"
    atd_sed "${src}/pc-bios/meson.build" \
        "s/vgabios.bin/vgabios.bin',\n\t'bootsplash.jpg/g" \
        "Add bootsplash.jpg to BIOS assets"
    atd_sed "${src}/hw/nvram/fw_cfg.c" \
        "s/current_machine->boot_config.splash;/\"\/usr\/share\/kvm\/bootsplash.jpg\";/g" \
        "Force custom bootsplash path"

    # =================================================================
    #  9. HDA audio codec vendor (already in usb-scsi but kept for safety)
    # =================================================================
    (( count++ )); atd_step ${count} ${total} "hw/audio/hda-codec.c (HDA vendor)"
    atd_sed "${src}/hw/audio/hda-codec.c" \
        "s/0x1af4/0x8086/g" \
        "HDA vendor ID 0x1af4 → 0x8086 (Intel)"

    # =================================================================
    # 10. BOCHS VGA device ID (0x1234 / 0x1111)
    # =================================================================
    # VMAware checks for VEN_1234 (QEMU default VGA / bochs-display)
    # and DEV_1111. The stdvga device uses these.

    (( count++ )); atd_step ${count} ${total} "BOCHS VGA vendor/device IDs"
    # hw/display/bochs-display.c — bochs-display vendor
    atd_sed "${src}/hw/display/bochs-display.c" \
        "s/0x1234/0x8086/g" \
        "BOCHS VGA vendor 0x1234 → 0x8086 (Intel)" --allow-missing
    atd_sed "${src}/hw/display/bochs-display.c" \
        "s/0x1111/0x5917/g" \
        "BOCHS VGA device 0x1111 → 0x5917 (Intel UHD 620)" --allow-missing

    atd_ok "PCI vendor/device ID patching complete (vendor=${pci_vendor})"
    return 0
}
