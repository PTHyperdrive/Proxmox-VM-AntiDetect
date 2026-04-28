#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- QEMU KVM CPUID Anti-Detection
#  Patches CPUID hypervisor bit and related identifiers
#
#  Usage: source patches/qemu-kvm-cpuid.patch.sh
#         patch_qemu_kvm_cpuid <qemu_src_dir> <config_file>
# ---------------------------------------------------------------

patch_qemu_kvm_cpuid() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching QEMU KVM CPUID Identifiers"

    # Note: The actual hypervisor bit (CPUID leaf 1, ECX bit 31) is
    # controlled at VM runtime via the args: -cpu host,hypervisor=off
    # This module handles the string-level identification in source.

    local count=0
    local total=1

    (( count++ )); atd_step ${count} ${total} "target/i386/kvm/kvm.c (hypervisor signature)"
    # The KVM hypervisor string "KVMKVMKVM\0\0\0" is replaced with null bytes
    # to prevent CPUID-based VM detection. The runtime -cpu hypervisor=off flag
    # complements this by zeroing the hypervisor present bit in CPUID.
    atd_sed "${src}/target/i386/kvm/kvm.c" \
        's/KVMKVMKVM\\0\\0\\0/\\1\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0\\0/g' \
        "Nullify KVM hypervisor CPUID signature"

    atd_ok "KVM CPUID patching complete"
    return 0
}
