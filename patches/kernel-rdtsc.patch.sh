#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- Kernel KVM Anti-Detection
#  Patches KVM to intercept RDTSC/RDTSCP for timing anti-detection
#  Patches singlestep bypass for hypervisor interception evasion
#  Supports both Intel VMX and AMD SVM
#
#  Version-resilient: uses fallback anchor chains for kernel 6.8-6.17+
#
#  Usage: source patches/kernel-rdtsc.patch.sh
#         patch_kernel_rdtsc <kernel_src_dir> <config_file>
#
#  Based on: pve-emu-realpc_kernel-main/build_kernel.sh
# ---------------------------------------------------------------

# ===== Helper: Try multiple sed anchor patterns =====
# Usage: _atd_sed_fallback <file> <description> <pattern1> [<pattern2> ...]
# Tries each sed pattern in order until one succeeds (file actually changes).
# Returns 0 on first successful substitution, 1 if all patterns fail.
_atd_sed_fallback() {
    local file="$1"
    local desc="$2"
    shift 2

    if (( ATD_DRY_RUN )); then
        atd_dry "sed (fallback chain) on ${file}: ${desc}"
        atd_dry "  Anchors to try: $#"
        return 0
    fi

    if [[ ! -f "${file}" ]]; then
        atd_err "Target file not found: ${file}"
        return 1
    fi

    local hash_before attempt=0
    hash_before=$(md5sum "${file}" | cut -d' ' -f1)

    for pattern in "$@"; do
        (( attempt++ ))
        # Work on a copy so failed attempts don't corrupt the file
        cp "${file}" "${file}.atd_try"
        sed -i "${pattern}" "${file}.atd_try" 2>/dev/null || continue

        local hash_after
        hash_after=$(md5sum "${file}.atd_try" | cut -d' ' -f1)
        if [[ "${hash_before}" != "${hash_after}" ]]; then
            mv "${file}.atd_try" "${file}"
            atd_debug "Patched (anchor #${attempt}): ${desc} in $(basename "${file}")"
            return 0
        fi
        rm -f "${file}.atd_try"
    done
    rm -f "${file}.atd_try" 2>/dev/null

    atd_err "All ${attempt} anchor patterns failed for: ${desc} in $(basename "${file}")"
    atd_err "  This kernel version may have incompatible code layout."
    return 1
}

# ===== Helper: Verify a marker exists in file after patching =====
# Usage: _atd_verify_patch <file> <grep_pattern> <description>
_atd_verify_patch() {
    local file="$1"
    local pattern="$2"
    local desc="$3"

    if (( ATD_DRY_RUN )); then
        return 0
    fi

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        atd_debug "Verified: ${desc}"
        return 0
    else
        atd_err "Post-patch verification FAILED: ${desc}"
        atd_err "  Expected '${pattern}' in $(basename "${file}") but not found."
        return 1
    fi
}

patch_kernel_rdtsc() {
    local src="$1"
    local cfg="$2"

    atd_separator "Patching Kernel KVM Anti-Detection"

    local rdtsc_div
    rdtsc_div="$(atd_config_get "${cfg}" kvm rdtsc_divisor)"
    rdtsc_div="${rdtsc_div:-20}"

    atd_info "RDTSC timing divisor: ${rdtsc_div}"
    atd_info "Applying kernel patches via sed (version-resilient)"

    local x86_c="${src}/arch/x86/kvm/x86.c"
    local vmx_h="${src}/arch/x86/kvm/vmx/vmx.h"
    local vmx_c="${src}/arch/x86/kvm/vmx/vmx.c"
    local svm_c="${src}/arch/x86/kvm/svm/svm.c"

    # Validate required files exist
    for f in "${x86_c}" "${vmx_h}" "${vmx_c}" "${svm_c}"; do
        if [[ ! -f "${f}" ]]; then
            atd_err "Required kernel file not found: ${f}"
            return 4
        fi
    done

    # =================================================================
    #  GUARD: Detect double-patching and abort if tree is dirty
    # =================================================================
    # Check for the most critical marker — if handler functions are already
    # present, the tree was previously patched. All-or-nothing to avoid
    # partial re-patching that corrupts the code.
    local _markers=("print_once_rdtsc" "handle_rdtsc_interception" "kvm.ko AICodo")
    local _found=0 _total_markers=${#_markers[@]}
    for _m in "${_markers[@]}"; do
        if grep -q "${_m}" "${vmx_c}" "${svm_c}" "${x86_c}" 2>/dev/null; then
            (( _found++ ))
        fi
    done
    if (( _found > 0 && _found < _total_markers )); then
        atd_warn "Partially patched kernel detected (${_found}/${_total_markers} markers found)."
        atd_warn "This may cause corruption. Consider cleaning the source tree first:"
        atd_warn "  cd ${src} && git checkout ."
    fi
    if (( _found == _total_markers )); then
        atd_skip "Kernel already fully patched (all ${_total_markers} markers present). Skipping."
        return 0
    fi

    local count=0
    local total=12
    local errors=0

    # =================================================================
    #  x86.c -- Singlestep bypass + startup flag
    # =================================================================

    # -- Singlestep bypass: intercept DB_VECTOR to prevent hypervisor detection --
    (( count++ )); atd_step ${count} ${total} "x86.c: singlestep bypass"
    if ! atd_already_patched "${x86_c}" "KVM_GUESTDBG_SINGLESTEP"; then
        atd_sed "${x86_c}" \
            's/kvm_queue_exception_p(vcpu, DB_VECTOR, DR6_BS);/if (KVM_GUESTDBG_SINGLESTEP ) {\n\t\tprintk(KERN_ALERT "kvm_vcpu_do_singlestep if (KVM_GUESTDBG_SINGLESTEP)  AICodo  return 0\\n"); \n\t\tkvm_run->debug.arch.dr6 = DR6_BS | DR6_ACTIVE_LOW | 1;\n\t\tkvm_run->debug.arch.pc = kvm_get_linear_rip(vcpu);\n\t\tkvm_run->debug.arch.exception = DB_VECTOR;\n\t\tkvm_run->exit_reason = KVM_EXIT_DEBUG;\n\t\treturn 0;\n\t}\n\tkvm_queue_exception_p(vcpu, DB_VECTOR, DR6_BS);/g' \
            "Singlestep hypervisor interception bypass" || (( errors++ ))
    else
        atd_skip "x86.c singlestep bypass already patched"
    fi

    # -- kvm.ko startup flag --
    (( count++ )); atd_step ${count} ${total} "x86.c: kvm.ko startup flag"
    if ! atd_already_patched "${x86_c}" "kvm.ko AICodo"; then
        atd_sed "${x86_c}" \
            's/kvm_init_xstate_sizes/printk(KERN_ALERT "kvm.ko AICodo v2.0 Start,ok!!!\\n");\n\tkvm_init_xstate_sizes/g' \
            "Add kvm.ko startup identification" || (( errors++ ))
    else
        atd_skip "x86.c startup flag already patched"
    fi

    # =================================================================
    #  vmx.h -- Enable RDTSC exiting in VMX capability mask
    # =================================================================

    (( count++ )); atd_step ${count} ${total} "vmx.h: RDTSC exiting flag"
    if ! atd_already_patched "${vmx_h}" "CPU_BASED_RDTSC_EXITING |"; then
        # This step uses raw sed (not atd_sed) because it's a multi-step
        # delete + reformat operation, not a single substitution.
        if (( ATD_DRY_RUN )); then
            atd_dry "sed -i '/CPU_BASED_RDTSC_EXITING/d' ${vmx_h}"
            atd_dry "sed -i 's/CPU_BASED_TPR_SHADOW/(CPU_BASED_TPR_SHADOW/g' ${vmx_h}"
            atd_dry "sed -i 's/CPU_BASED_INTR_WINDOW_EXITING/CPU_BASED_RDTSC_EXITING | ... CPU_BASED_INTR_WINDOW_EXITING/g' ${vmx_h}"
        else
            local _vmx_h_hash_before
            _vmx_h_hash_before=$(md5sum "${vmx_h}" | cut -d' ' -f1)

            sed -i '/CPU_BASED_RDTSC_EXITING/d' "${vmx_h}"
            sed -i 's/CPU_BASED_TPR_SHADOW/(CPU_BASED_TPR_SHADOW/g' "${vmx_h}"
            sed -i 's/CPU_BASED_INTR_WINDOW_EXITING/CPU_BASED_RDTSC_EXITING |\t\t\t\t\t\\\n\t CPU_BASED_INTR_WINDOW_EXITING/g' "${vmx_h}"

            local _vmx_h_hash_after
            _vmx_h_hash_after=$(md5sum "${vmx_h}" | cut -d' ' -f1)
            if [[ "${_vmx_h_hash_before}" == "${_vmx_h_hash_after}" ]]; then
                atd_err "vmx.h RDTSC exiting patch did not change the file"
                (( errors++ ))
            else
                atd_debug "Patched vmx.h RDTSC exiting flags"
            fi
        fi
    else
        atd_skip "vmx.h RDTSC exiting already patched"
    fi

    # =================================================================
    #  vmx.c -- TSC scaling helpers + RDTSC/RDTSCP handlers
    # =================================================================

    # -- TSC scaling helper functions --
    (( count++ )); atd_step ${count} ${total} "vmx.c: TSC scaling helpers"
    if ! atd_already_patched "${vmx_c}" "mul_u64_u64_shr0"; then
        atd_sed "${vmx_c}" \
            's/static int vmx_setup_l1d_flush/static __always_inline u64 mul_u64_u64_shr0(u64 a, u64 mul, unsigned int shift){\treturn (u64)(((unsigned __int128)a \* mul) >> shift); }\nstatic inline u64 __scale_tsc0(u64 ratio, u64 tsc){\treturn mul_u64_u64_shr0(tsc, ratio, kvm_caps.tsc_scaling_ratio_frac_bits); }\nstatic inline u64 kvm_scale_tsc0(u64 tsc, u64 ratio){\n\tu64 _tsc = tsc;\n\tif (ratio != kvm_caps.default_tsc_scaling_ratio){_tsc = __scale_tsc0(ratio, tsc);}\n\treturn _tsc;\n}\nstatic int vmx_setup_l1d_flush/g' \
            "Add TSC scaling helper functions" || (( errors++ ))
    else
        atd_skip "vmx.c TSC helpers already patched"
    fi

    # -- Ensure RDTSC exiting is enabled in exec_control --
    (( count++ )); atd_step ${count} ${total} "vmx.c: exec_control RDTSC"
    if ! atd_already_patched "${vmx_c}" "Ensure handle_rdtsc"; then
        # Try removing RDTSC from the clear mask (may or may not be present depending on version)
        atd_sed "${vmx_c}" \
            's/exec_control \&= ~(CPU_BASED_RDTSC_EXITING |/exec_control \&= ~(/g' \
            "Remove RDTSC from exec_control clear mask" "--warn-only"
        # Force enable RDTSC exiting -- anchor on INTR_WINDOW_EXITING comment
        atd_sed "${vmx_c}" \
            's/\/\* INTR_WINDOW_EXITING/exec_control |= CPU_BASED_RDTSC_EXITING; \/\/Ensure handle_rdtsc() is used.added line AICodo \n\t\/\* INTR_WINDOW_EXITING/g' \
            "Force enable RDTSC exiting" || (( errors++ ))
    else
        atd_skip "vmx.c exec_control RDTSC already patched"
    fi

    # -- handle_rdtsc + handle_rdtscp + handle_umwait + handle_tpause --
    # This is the CRITICAL step that was failing: the anchor 'handle_notify'
    # may not exist in all kernel versions. Use fallback chain.
    (( count++ )); atd_step ${count} ${total} "vmx.c: RDTSC/RDTSCP handler functions"
    if ! atd_already_patched "${vmx_c}" "print_once_rdtsc"; then
        local _handler_body='static u32 print_once_rdtsc = 1;\nstatic int handle_rdtsc(struct kvm_vcpu \*vcpu) {\n\tu64 offset = vcpu->arch.tsc_offset;\n\tu64 ratio = vcpu->arch.tsc_scaling_ratio;\n\tu64 rdtsc_fake;\n\tif(print_once_rdtsc){\n\t\tprintk(KERN_ALERT "[handle_rdtsc] vmx.c fake rdtsc vmx function is working AICodo \\n");\n\t\tprint_once_rdtsc = 0;\n\t}\n\tif (vmx_get_cpl(vcpu) != 0 || !is_protmode(vcpu)){ratio \/= 4;}\n\trdtsc_fake = kvm_scale_tsc0(rdtsc(), ratio) + offset;\n\tvcpu->arch.regs[VCPU_REGS_RAX] = rdtsc_fake \& -1u;\n\tvcpu->arch.regs[VCPU_REGS_RDX] = (rdtsc_fake >> 32) \& -1u;\n\treturn skip_emulated_instruction(vcpu);\n}\nstatic u32 print_once_rdtscp = 1;\nstatic int handle_rdtscp(struct kvm_vcpu \*vcpu) {\n\tif(print_once_rdtscp){\n\t\tprintk(KERN_ALERT "[handle_rdtscp] vmx.c fake rdtscp vmx function is working AICodo\\n");\n\t\tprint_once_rdtscp = 0;\n\t}\n\tvcpu->arch.regs[VCPU_REGS_RCX] = vmcs_read16(VIRTUAL_PROCESSOR_ID);\n\treturn handle_rdtsc(vcpu);\n}\n\nstatic int handle_umwait(struct kvm_vcpu *vcpu){return skip_emulated_instruction(vcpu);}\nstatic int handle_tpause(struct kvm_vcpu *vcpu){return skip_emulated_instruction(vcpu);}'

        # Fallback anchor chain for injecting handler functions:
        #   1. 'static int handle_notify' -- kernel 6.8 / early 6.11+
        #   2. 'static int handle_bus_lock_vmexit' -- present in most 6.x kernels
        #   3. 'static int (*kvm_vmx_exit_handlers' -- the table itself (last resort)
        _atd_sed_fallback "${vmx_c}" "Add RDTSC/RDTSCP/UMWAIT/TPAUSE handler functions" \
            "s/static int handle_notify/${_handler_body}\nstatic int handle_notify/g" \
            "s/static int handle_bus_lock_vmexit/${_handler_body}\nstatic int handle_bus_lock_vmexit/g" \
            "s/static int (\*kvm_vmx_exit_handlers/${_handler_body}\nstatic int (*kvm_vmx_exit_handlers/g" \
            || (( errors++ ))

        # CRITICAL: Verify the handler was actually injected
        _atd_verify_patch "${vmx_c}" "handle_rdtsc" \
            "handle_rdtsc function exists in vmx.c" || (( errors++ ))
    else
        atd_skip "vmx.c RDTSC handlers already patched"
    fi

    # -- Register exit handlers --
    # Same fallback chain issue: 'handle_notify,' may not be in the table.
    (( count++ )); atd_step ${count} ${total} "vmx.c: exit handler table entries"
    if ! atd_already_patched "${vmx_c}" "EXIT_REASON_RDTSC"; then
        local _table_entries='\n\t[EXIT_REASON_RDTSC]                   = handle_rdtsc, \/\/added line AICodo \n\t[EXIT_REASON_RDTSCP]                  = handle_rdtscp, \/\/added line AICodo \n\t[EXIT_REASON_UMWAIT]                  = handle_umwait, \/\/added line AICodo \n\t[EXIT_REASON_TPAUSE]\t\t      = handle_tpause, \/\/added line AICodo '

        # Fallback anchor chain for exit handler table:
        #   1. 'handle_notify,' -- 6.8+
        #   2. 'handle_bus_lock_vmexit,' -- most 6.x
        #   3. '};' closing the kvm_vmx_exit_handlers array
        #      (insert BEFORE the closing brace — uses different pattern)
        _atd_sed_fallback "${vmx_c}" "Register RDTSC/RDTSCP/UMWAIT/TPAUSE exit handlers" \
            "s/handle_notify,/handle_notify,${_table_entries}/g" \
            "s/handle_bus_lock_vmexit,/handle_bus_lock_vmexit,${_table_entries}/g" \
            "s/\[EXIT_REASON_ENCLS\]/[EXIT_REASON_ENCLS]/g" \
            || (( errors++ ))
        # Note: anchor #3 is a no-op fallback placeholder.
        # If neither handle_notify nor handle_bus_lock_vmexit exist in the table,
        # we need manual intervention -- the exit handler array structure has changed
        # too much. The error from _atd_sed_fallback will alert the user.

        # CRITICAL: Verify the table entry was injected
        _atd_verify_patch "${vmx_c}" "EXIT_REASON_RDTSC" \
            "EXIT_REASON_RDTSC table entry in vmx.c" || (( errors++ ))
    else
        atd_skip "vmx.c exit handler entries already patched"
    fi

    # -- kvm-intel.ko startup flag --
    (( count++ )); atd_step ${count} ${total} "vmx.c: kvm-intel.ko startup flag"
    if ! atd_already_patched "${vmx_c}" "kvm-intel.ko AICodo"; then
        atd_sed "${vmx_c}" \
            's/int r, cpu;/int r, cpu;\n\tprintk(KERN_ALERT "kvm-intel.ko AICodo  v2.0 Start,ok!!!\\n");\/\/added line AICodo /g' \
            "Add kvm-intel.ko startup identification" || (( errors++ ))
    else
        atd_skip "vmx.c startup flag already patched"
    fi

    # =================================================================
    #  svm.c -- AMD SVM RDTSC interception
    # =================================================================

    # -- Enable RDTSC intercept --
    (( count++ )); atd_step ${count} ${total} "svm.c: RDTSC intercept enable"
    if ! atd_already_patched "${svm_c}" "INTERCEPT_RDTSC"; then
        atd_sed "${svm_c}" \
            's/svm_set_intercept(svm, INTERCEPT_RSM);/svm_set_intercept(svm, INTERCEPT_RSM);\n\tsvm_set_intercept(svm, INTERCEPT_RDTSC); \/\/added line AICodo /g' \
            "Enable SVM RDTSC interception" || (( errors++ ))
    else
        atd_skip "svm.c RDTSC intercept already patched"
    fi

    # -- handle_rdtsc_interception function --
    (( count++ )); atd_step ${count} ${total} "svm.c: RDTSC handler function (div=${rdtsc_div})"
    if ! atd_already_patched "${svm_c}" "handle_rdtsc_interception"; then
        atd_sed "${svm_c}" \
            "s/static int (\\*const svm_exit_handlers/static u32 print_once = 1;\\nstatic int handle_rdtsc_interception(struct kvm_vcpu \\*vcpu){\\n\\tstatic u64 rdtsc_fake = 0;\\n\\tstatic u64 rdtsc_prev = 0;\\n\\tu64 rdtsc_real = rdtsc();\\n\\tif(print_once){\\n\\t\\tprintk(KERN_ALERT \\\"[handle_rdtsc] svm.c fake rdtsc svm function is working diff ${rdtsc_div} AICodo \\\\\\\\n\\\");\\n\\t\\tprint_once = 0;\\n\\t\\trdtsc_fake = rdtsc_real;\\n\\t}\\n\\tif(rdtsc_prev != 0){\\n\\t\\tif(rdtsc_real > rdtsc_prev){\\n\\t\\t\\tu64 diff = rdtsc_real - rdtsc_prev;\\n\\t\\t\\tu64 fake_diff =  diff \\/ ${rdtsc_div};\\n\\t\\t\\trdtsc_fake += fake_diff;\\n\\t\\t}\\n\\t}\\n\\tif(rdtsc_fake > rdtsc_real){rdtsc_fake = rdtsc_real;}\\n\\trdtsc_prev = rdtsc_real;\\n\\tvcpu->arch.regs[VCPU_REGS_RAX] = rdtsc_fake \\& -1u;\\n\\tvcpu->arch.regs[VCPU_REGS_RDX] = (rdtsc_fake >> 32) \\& -1u;\\n\\treturn svm_skip_emulated_instruction(vcpu);\\n}\\nstatic int (*const svm_exit_handlers/g" \
            "Add SVM RDTSC interception handler" || (( errors++ ))

        # Verify SVM handler was injected
        _atd_verify_patch "${svm_c}" "handle_rdtsc_interception" \
            "handle_rdtsc_interception function in svm.c" || (( errors++ ))
    else
        atd_skip "svm.c RDTSC handler already patched"
    fi

    # -- Register SVM exit handler --
    # NOTE: The guard must NOT use plain "SVM_EXIT_RDTSC" because the upstream
    # svm.c already contains that string in the x86_intercept table (unrelated).
    # Use the full handler assignment pattern to avoid false positives.
    (( count++ )); atd_step ${count} ${total} "svm.c: exit handler table entry"
    if ! atd_already_patched "${svm_c}" "handle_rdtsc_interception, //added"; then
        atd_sed "${svm_c}" \
            's/avic_unaccelerated_access_interception,/avic_unaccelerated_access_interception,\n\t[SVM_EXIT_RDTSC]\t\t\t= handle_rdtsc_interception, \/\/added line AICodo /g' \
            "Register SVM RDTSC exit handler" || (( errors++ ))
    else
        atd_skip "svm.c exit handler entry already patched"
    fi

    # -- kvm-amd.ko startup flag --
    (( count++ )); atd_step ${count} ${total} "svm.c: kvm-amd.ko startup flag"
    if ! atd_already_patched "${svm_c}" "kvm-amd.ko AICodo"; then
        atd_sed "${svm_c}" \
            's/__unused_size_checks/printk(KERN_ALERT "kvm-amd.ko AICodo  v2.0 Start,ok!!!\\n");\/\/added line AICodo \n\t__unused_size_checks/g' \
            "Add kvm-amd.ko startup identification" || (( errors++ ))
    else
        atd_skip "svm.c startup flag already patched"
    fi

    # =================================================================
    #  Final validation
    # =================================================================
    if (( errors > 0 )); then
        atd_err "Kernel patching completed with ${errors} error(s)!"
        atd_err "The build will likely fail. Check the anchor patterns above."
        return 4
    fi

    atd_ok "Kernel KVM anti-detection patching complete (divisor=${rdtsc_div})"
    return 0
}
