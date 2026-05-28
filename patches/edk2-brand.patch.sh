#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- EDK2/OVMF Brand Anti-Detection
#  Replaces QEMU/Virtio/Xen identifiers in EDK2 firmware
#
#  Usage: source patches/edk2-brand.patch.sh
#         patch_edk2_brand <edk2_src_dir> <brand>
# ---------------------------------------------------------------

patch_edk2_brand() {
    local src="$1"
    local brand="$2"

    atd_separator "Patching EDK2/OVMF Brand Identifiers [brand=${brand}]"

    if [[ ${#brand} -ne 4 ]]; then
        atd_err "Brand must be exactly 4 characters, got '${brand}' (${#brand} chars)"
        return 2
    fi

    local count=0
    local total=6

    # -- debian/rules PCD Firmware Strings --
    # This is the MOST CRITICAL patch: the PcdFirmwareVendor string shows up
    # as "BIOS Version/Date" in System Information. Without this patch it reads
    # "Proxmox distribution of EDK II" which is a dead giveaway.
    (( count++ )); atd_step ${count} ${total} "debian/rules PCD firmware vendor/version/date"
    local rules_file="${src}/../debian/rules"
    if [[ -f "${rules_file}" ]]; then
        # Read BIOS vendor info from profile (SMBIOS Type 0)
        local bios_vendor bios_version bios_date
        bios_vendor="$(atd_config_get "${PROFILE:-}" smbios_type0 vendor 2>/dev/null)"
        bios_version="$(atd_config_get "${PROFILE:-}" smbios_type0 version 2>/dev/null)"
        bios_date="$(atd_config_get "${PROFILE:-}" smbios_type0 date 2>/dev/null)"
        bios_vendor="${bios_vendor:-American Megatrends International LLC.}"
        bios_version="${bios_version:-${brand} BIOS}"
        # Replace PcdFirmwareVendor (the critical "Proxmox distribution of EDK II" string)
        if grep -q 'PcdFirmwareVendor=L"Proxmox distribution of EDK II' "${rules_file}"; then
            sed -i "s|PcdFirmwareVendor=L\"Proxmox distribution of EDK II|PcdFirmwareVendor=L\"${bios_vendor}|g" "${rules_file}"
            atd_debug "Replaced PcdFirmwareVendor -> '${bios_vendor}'"
        fi
        # Replace PcdFirmwareVersionString (version number shown in BIOS info)
        if grep -q 'PcdFirmwareVersionString=L"$(DEB_VERSION)' "${rules_file}"; then
            sed -i "s|PcdFirmwareVersionString=L\"\$(DEB_VERSION)|PcdFirmwareVersionString=L\"${bios_version}|g" "${rules_file}"
            atd_debug "Replaced PcdFirmwareVersionString -> '${bios_version}'"
        fi
        # Replace PcdFirmwareReleaseDateString with realistic BIOS date
        if [[ -n "${bios_date}" ]] && grep -q 'PcdFirmwareReleaseDateString=L"$(PCD_RELEASE_DATE)' "${rules_file}"; then
            sed -i "s|PcdFirmwareReleaseDateString=L\"\$(PCD_RELEASE_DATE)|PcdFirmwareReleaseDateString=L\"${bios_date}|g" "${rules_file}"
            atd_debug "Replaced PcdFirmwareReleaseDateString -> '${bios_date}'"
        fi
        atd_ok "Patched debian/rules PCD strings"
    else
        atd_warn "debian/rules not found at ${rules_file} -- BIOS vendor string NOT patched!"
    fi

    # -- MDE Module Package (signature) --
    (( count++ )); atd_step ${count} ${total} "MdeModulePkg/MdeModulePkg.dec"
    atd_sed "${src}/MdeModulePkg/MdeModulePkg.dec" \
        "s/0x20202020324B4445/0x20202020204c5450/g" \
        "EDK2 module signature"

    # -- OVMF ACPI Platform --
    (( count++ )); atd_step ${count} ${total} "OvmfPkg ACPI + Loaders"
    atd_sed "${src}/OvmfPkg/AcpiPlatformDxe/AcpiPlatformDxe.inf" \
        "s/QemuFwCfgAcpiPlatform/${brand}FwCfgAcpiPlatform/g" \
        "ACPI platform DXE name"
    atd_sed "${src}/OvmfPkg/QemuKernelLoaderFsDxe/QemuKernelLoaderFsDxe.inf" \
        "s/BASE_NAME                      = QemuKernelLoaderFsDxe/BASE_NAME                      = ${brand}KernelLoaderFsDxe/g" \
        "Kernel loader DXE name"

    # -- Virtio drivers --
    (( count++ )); atd_step ${count} ${total} "OvmfPkg Virtio drivers"
    local virtio_infs=(
        "OvmfPkg/Fdt/VirtioFdtDxe/VirtioFdtDxe.inf"
        "OvmfPkg/QemuRamfbDxe/QemuRamfbDxe.inf"
        "OvmfPkg/QemuVideoDxe/QemuVideoDxe.inf"
        "OvmfPkg/Virtio10Dxe/Virtio10.inf"
        "OvmfPkg/VirtioBlkDxe/VirtioBlk.inf"
        "OvmfPkg/VirtioFsDxe/VirtioFsDxe.inf"
        "OvmfPkg/VirtioGpuDxe/VirtioGpu.inf"
        "OvmfPkg/VirtioKeyboardDxe/VirtioKeyboard.inf"
        "OvmfPkg/VirtioNetDxe/VirtioNet.inf"
        "OvmfPkg/VirtioPciDeviceDxe/VirtioPciDeviceDxe.inf"
        "OvmfPkg/VirtioRngDxe/VirtioRng.inf"
        "OvmfPkg/VirtioScsiDxe/VirtioScsi.inf"
        "OvmfPkg/VirtioSerialDxe/VirtioSerial.inf"
        "OvmfPkg/VirtNorFlashDxe/VirtNorFlashDxe.inf"
    )

    for inf in "${virtio_infs[@]}"; do
        local target="${src}/${inf}"
        if [[ -f "${target}" ]]; then
            # Replace only BASE_NAME values -- anchored to avoid corrupting ENTRY_POINT etc.
            sed -i "/^[[:space:]]*BASE_NAME/s/= Virtio/= ${brand}io/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= VirtNor/= ${brand}Nor/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= QemuRamfb/= ${brand}Ramfb/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= QemuVideo/= ${brand}Video/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= VirtHsti/= ${brand}Hsti/g" "${target}" 2>/dev/null
            atd_debug "Patched $(basename "${inf}")"
        fi
    done

    # -- Xen drivers --
    (( count++ )); atd_step ${count} ${total} "OvmfPkg Xen drivers"
    local xen_infs=(
        "OvmfPkg/XenAcpiPlatformDxe/XenAcpiPlatformDxe.inf"
        "OvmfPkg/XenBusDxe/XenBusDxe.inf"
        "OvmfPkg/XenIoPciDxe/XenIoPciDxe.inf"
        "OvmfPkg/XenIoPvhDxe/XenIoPvhDxe.inf"
        "OvmfPkg/XenPlatformPei/XenPlatformPei.inf"
        "OvmfPkg/XenPvBlkDxe/XenPvBlkDxe.inf"
        "OvmfPkg/XenResetVector/XenResetVector.inf"
        "OvmfPkg/SmbiosPlatformDxe/XenSmbiosPlatformDxe.inf"
    )

    for inf in "${xen_infs[@]}"; do
        local target="${src}/${inf}"
        if [[ -f "${target}" ]]; then
            # Replace only BASE_NAME values -- anchored to avoid corrupting ENTRY_POINT etc.
            sed -i "/^[[:space:]]*BASE_NAME/s/= Xen/= ${brand}/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= XenAcpi/= ${brand}Acpi/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= XenBus/= ${brand}Bus/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= XenIo/= ${brand}Io/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= XenPlatform/= ${brand}Platform/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= XenPvBlk/= ${brand}PvBlk/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= XenReset/= ${brand}Reset/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= XenSmbios/= ${brand}Smbios/g" "${target}" 2>/dev/null
            atd_debug "Patched $(basename "${inf}")"
        fi
    done

    # -- OVMF Libraries --
    (( count++ )); atd_step ${count} ${total} "OvmfPkg Libraries"
    local lib_infs=(
        "OvmfPkg/Library/XenIoMmioLib/XenIoMmioLib.inf"
        "OvmfPkg/Library/XenPlatformLib/XenPlatformLib.inf"
        "OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgDxeLib.inf"
        "OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgLibNull.inf"
        "OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgMmioDxeLib.inf"
        "OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgMmioPeiLib.inf"
        "OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgPeiLib.inf"
        "OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgSecLib.inf"
        "OvmfPkg/Library/XenHypercallLib/XenHypercallLib.inf"
        "OvmfPkg/Library/QemuBootOrderLib/QemuBootOrderLib.inf"
        "OvmfPkg/Library/VirtioMmioDeviceLib/VirtioMmioDeviceLib.inf"
        "OvmfPkg/Library/X86QemuLoadImageLib/X86QemuLoadImageLib.inf"
        "OvmfPkg/Library/XenRealTimeClockLib/XenRealTimeClockLib.inf"
        "OvmfPkg/Library/XenConsoleSerialPortLib/XenConsoleSerialPortLib.inf"
        "OvmfPkg/Library/QemuFwCfgSimpleParserLib/QemuFwCfgSimpleParserLib.inf"
        "OvmfPkg/RiscVVirt/Library/VirtNorFlashPlatformLib/VirtNorFlashStaticLib.inf"
        "OvmfPkg/RiscVVirt/Library/VirtNorFlashPlatformLib/VirtNorFlashDeviceTreeLib.inf"
        "OvmfPkg/Library/QemuFwCfgS3Lib/BaseQemuFwCfgS3LibNull.inf"
        "OvmfPkg/Library/QemuFwCfgS3Lib/DxeQemuFwCfgS3LibFwCfg.inf"
        "OvmfPkg/Library/QemuFwCfgS3Lib/PeiQemuFwCfgS3LibFwCfg.inf"
        "OvmfPkg/Library/GenericQemuLoadImageLib/GenericQemuLoadImageLib.inf"
    )

    for inf in "${lib_infs[@]}"; do
        local target="${src}/${inf}"
        if [[ -f "${target}" ]]; then
            # Replace only BASE_NAME values -- anchored to avoid corrupting LIBRARY_CLASS etc.
            # Exact prefix patterns (GenericQemu, BaseQemu, DxeQemu, PeiQemu, X86Qemu)
            sed -i "/^[[:space:]]*BASE_NAME/s/= GenericQemu/= Generic${brand}/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= BaseQemu/= Base${brand}/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= DxeQemu/= Dxe${brand}/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= PeiQemu/= Pei${brand}/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= X86Qemu/= X86${brand}/g" "${target}" 2>/dev/null
            # Standard patterns (Qemu, Xen, Virtio, VirtNor)
            sed -i "/^[[:space:]]*BASE_NAME/s/= Qemu/= ${brand}/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= Xen/= ${brand}/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= Virtio/= ${brand}io/g" "${target}" 2>/dev/null
            sed -i "/^[[:space:]]*BASE_NAME/s/= VirtNor/= ${brand}Nor/g" "${target}" 2>/dev/null
            atd_debug "Patched $(basename "${inf}")"
        fi
    done

    # -- VirtHstiDxe --
    local vhsti="${src}/OvmfPkg/VirtHstiDxe/VirtHstiDxe.inf"
    if [[ -f "${vhsti}" ]]; then
        sed -i "/^[[:space:]]*BASE_NAME/s/= VirtHstiDxe/= ${brand}HstiDxe/g" "${vhsti}" 2>/dev/null
        atd_debug "Patched VirtHstiDxe.inf"
    fi

    atd_ok "EDK2/OVMF brand patching complete (${brand})"
    return 0
}
