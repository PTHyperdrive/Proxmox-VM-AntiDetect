#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- Kernel RDTSC Interception
#  Patches KVM to intercept RDTSC/RDTSCP for timing anti-detection
#  Supports both Intel VMX and AMD SVM
#
#  Usage: source patches/kernel-rdtsc.patch.sh
#         patch_kernel_rdtsc <kernel_src_dir> <config_file>
# ---------------------------------------------------------------

patch_kernel_rdtsc() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching Kernel KVM RDTSC Interception"

    local rdtsc_div
    rdtsc_div="$(atd_config_get "${cfg}" kvm rdtsc_divisor)"
    rdtsc_div="${rdtsc_div:-20}"

    atd_info "RDTSC timing divisor: ${rdtsc_div}"
    atd_info "Applying kernel patches from pre-built kernel.patch file"

    # The kernel RDTSC patches are complex multi-function insertions that
    # are best applied via the maintained kernel.patch file rather than
    # individual sed operations. This ensures correctness across kernel versions.

    local patch_file
    patch_file="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/pve-emu-realpc_kernel-main/kernel.patch"

    if [[ ! -f "${patch_file}" ]]; then
        atd_err "kernel.patch not found at ${patch_file}"
        return 4
    fi

    if (( ATD_DRY_RUN )); then
        atd_dry "cd ${src} && git apply ${patch_file}"
        atd_dry "Patches: VMX RDTSC/RDTSCP handlers, SVM RDTSC handler, x86 singlestep bypass"
        return 0
    fi

    # Attempt git apply first, fall back to patch command
    pushd "${src}" > /dev/null || return 1
    if git apply --check "${patch_file}" 2>/dev/null; then
        git apply "${patch_file}"
        atd_ok "kernel.patch applied via git apply"
    elif patch -p1 --dry-run < "${patch_file}" &>/dev/null; then
        patch -p1 < "${patch_file}"
        atd_ok "kernel.patch applied via patch command"
    else
        atd_err "kernel.patch failed to apply cleanly"
        atd_err "The kernel source may have diverged from the expected version"
        popd > /dev/null
        return 4
    fi
    popd > /dev/null

    atd_ok "Kernel RDTSC interception patching complete (divisor=${rdtsc_div})"
    return 0
}
