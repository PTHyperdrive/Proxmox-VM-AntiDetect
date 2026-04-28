#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Patch Module -- Kernel KVM Anti-Detection
#  Patches KVM to intercept RDTSC/RDTSCP for timing anti-detection
#  Patches singlestep bypass for hypervisor interception evasion
#  Supports both Intel VMX and AMD SVM
#
#  Usage: source patches/kernel-rdtsc.patch.sh
#         patch_kernel_rdtsc <kernel_src_dir> <config_file>
#
#  Based on: pve-emu-realpc_kernel-main/build_kernel.sh
# ---------------------------------------------------------------

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

    local count=0
    local total=12

    # =================================================================
    #  x86.c -- Singlestep bypass + startup flag
    # =================================================================

    # -- Singlestep bypass: intercept DB_VECTOR to prevent hypervisor detection --
    (( count++ )); atd_step ${count} ${total} "x86.c: singlestep bypass"
    if ! atd_already_patched "${x86_c}" "KVM_GUESTDBG_SINGLESTEP"; then
        atd_sed "${x86_c}" \
            's/kvm_queue_exception_p(vcpu, DB_VECTOR, DR6_BS);/if (KVM_GUESTDBG_SINGLESTEP ) {\n\t\tprintk(KERN_ALERT "kvm_vcpu_do_singlestep if (KVM_GUESTDBG_SINGLESTEP)  AICodo  return 0\\n"); \n\t\tkvm_run->debug.arch.dr6 = DR6_BS | DR6_ACTIVE_LOW | 1;\n\t\tkvm_run->debug.arch.pc = kvm_get_linear_rip(vcpu);\n\t\tkvm_run->debug.arch.exception = DB_VECTOR;\n\t\tkvm_run->exit_reason = KVM_EXIT_DEBUG;\n\t\treturn 0;\n\t}\n\tkvm_queue_exception_p(vcpu, DB_VECTOR, DR6_BS);/g' \
            "Singlestep hypervisor interception bypass"
    else
        atd_skip "x86.c singlestep bypass already patched"
    fi

    # -- kvm.ko startup flag --
    (( count++ )); atd_step ${count} ${total} "x86.c: kvm.ko startup flag"
    if ! atd_already_patched "${x86_c}" "kvm.ko AICodo"; then
        atd_sed "${x86_c}" \
            's/kvm_init_xstate_sizes/printk(KERN_ALERT "kvm.ko AICodo v2.0 Start,ok!!!\\n");\n\tkvm_init_xstate_sizes/g' \
            "Add kvm.ko startup identification"
    else
        atd_skip "x86.c startup flag already patched"
    fi

    # =================================================================
    #  vmx.h -- Enable RDTSC exiting in VMX capability mask
    # =================================================================

    (( count++ )); atd_step ${count} ${total} "vmx.h: RDTSC exiting flag"
    if ! atd_already_patched "${vmx_h}" "CPU_BASED_RDTSC_EXITING |"; then
        # Remove existing RDTSC_EXITING line (may be in wrong position)
        if (( ATD_DRY_RUN )); then
            atd_dry "sed -i '/CPU_BASED_RDTSC_EXITING/d' ${vmx_h}"
            atd_dry "sed -i 's/CPU_BASED_TPR_SHADOW/(CPU_BASED_TPR_SHADOW/g' ${vmx_h}"
            atd_dry "sed -i 's/CPU_BASED_INTR_WINDOW_EXITING/CPU_BASED_RDTSC_EXITING | ... CPU_BASED_INTR_WINDOW_EXITING/g' ${vmx_h}"
        else
            sed -i '/CPU_BASED_RDTSC_EXITING/d' "${vmx_h}"
            sed -i 's/CPU_BASED_TPR_SHADOW/(CPU_BASED_TPR_SHADOW/g' "${vmx_h}"
            sed -i 's/CPU_BASED_INTR_WINDOW_EXITING/CPU_BASED_RDTSC_EXITING |\t\t\t\t\t\\\n\t CPU_BASED_INTR_WINDOW_EXITING/g' "${vmx_h}"
            atd_debug "Patched vmx.h RDTSC exiting flags"
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
            "Add TSC scaling helper functions"
    else
        atd_skip "vmx.c TSC helpers already patched"
    fi

    # -- Ensure RDTSC exiting is enabled in exec_control --
    (( count++ )); atd_step ${count} ${total} "vmx.c: exec_control RDTSC"
    if ! atd_already_patched "${vmx_c}" "Ensure handle_rdtsc"; then
        atd_sed "${vmx_c}" \
            's/exec_control \&= ~(CPU_BASED_RDTSC_EXITING |/exec_control \&= ~(/g' \
            "Remove RDTSC from exec_control clear mask"
        atd_sed "${vmx_c}" \
            's/\/\* INTR_WINDOW_EXITING/exec_control |= CPU_BASED_RDTSC_EXITING; \/\/Ensure handle_rdtsc() is used.added line AICodo \n\t\/\* INTR_WINDOW_EXITING/g' \
            "Force enable RDTSC exiting"
    else
        atd_skip "vmx.c exec_control RDTSC already patched"
    fi

    # -- handle_rdtsc + handle_rdtscp + handle_umwait + handle_tpause --
    (( count++ )); atd_step ${count} ${total} "vmx.c: RDTSC/RDTSCP handler functions"
    if ! atd_already_patched "${vmx_c}" "handle_rdtsc"; then
        atd_sed "${vmx_c}" \
            's/static int handle_notify/static u32 print_once_rdtsc = 1;\nstatic int handle_rdtsc(struct kvm_vcpu \*vcpu) {\n\tu64 offset = vcpu->arch.tsc_offset;\n\tu64 ratio = vcpu->arch.tsc_scaling_ratio;\n\tu64 rdtsc_fake;\n\tif(print_once_rdtsc){\n\t\tprintk(KERN_ALERT "[handle_rdtsc] vmx.c fake rdtsc vmx function is working AICodo \\n");\n\t\tprint_once_rdtsc = 0;\n\t}\n\tif (vmx_get_cpl(vcpu) != 0 || !is_protmode(vcpu)){ratio \/= 4;}\n\trdtsc_fake = kvm_scale_tsc0(rdtsc(), ratio) + offset;\n\tvcpu->arch.regs[VCPU_REGS_RAX] = rdtsc_fake \& -1u;\n\tvcpu->arch.regs[VCPU_REGS_RDX] = (rdtsc_fake >> 32) \& -1u;\n\treturn skip_emulated_instruction(vcpu);\n}\nstatic u32 print_once_rdtscp = 1;\nstatic int handle_rdtscp(struct kvm_vcpu \*vcpu) {\n\tif(print_once_rdtscp){\n\t\tprintk(KERN_ALERT "[handle_rdtscp] vmx.c fake rdtscp vmx function is working AICodo\\n");\n\t\tprint_once_rdtscp = 0;\n\t}\n\tvcpu->arch.regs[VCPU_REGS_RCX] = vmcs_read16(VIRTUAL_PROCESSOR_ID);\n\treturn handle_rdtsc(vcpu);\n}\n\nstatic int handle_umwait(struct kvm_vcpu *vcpu){return skip_emulated_instruction(vcpu);}\nstatic int handle_tpause(struct kvm_vcpu *vcpu){return skip_emulated_instruction(vcpu);}\nstatic int handle_notify/g' \
            "Add RDTSC/RDTSCP/UMWAIT/TPAUSE handler functions"
    else
        atd_skip "vmx.c RDTSC handlers already patched"
    fi

    # -- Register exit handlers --
    (( count++ )); atd_step ${count} ${total} "vmx.c: exit handler table entries"
    if ! atd_already_patched "${vmx_c}" "EXIT_REASON_RDTSC"; then
        atd_sed "${vmx_c}" \
            's/handle_notify,/handle_notify,\n\t[EXIT_REASON_RDTSC]                   = handle_rdtsc, \/\/added line AICodo \n\t[EXIT_REASON_RDTSCP]                  = handle_rdtscp, \/\/added line AICodo \n\t[EXIT_REASON_UMWAIT]                  = handle_umwait, \/\/added line AICodo \n\t[EXIT_REASON_TPAUSE]\t\t      = handle_tpause, \/\/added line AICodo /g' \
            "Register RDTSC/RDTSCP/UMWAIT/TPAUSE exit handlers"
    else
        atd_skip "vmx.c exit handler entries already patched"
    fi

    # -- kvm-intel.ko startup flag --
    (( count++ )); atd_step ${count} ${total} "vmx.c: kvm-intel.ko startup flag"
    if ! atd_already_patched "${vmx_c}" "kvm-intel.ko AICodo"; then
        atd_sed "${vmx_c}" \
            's/int r, cpu;/int r, cpu;\n\tprintk(KERN_ALERT "kvm-intel.ko AICodo  v2.0 Start,ok!!!\\n");\/\/added line AICodo /g' \
            "Add kvm-intel.ko startup identification"
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
            "Enable SVM RDTSC interception"
    else
        atd_skip "svm.c RDTSC intercept already patched"
    fi

    # -- handle_rdtsc_interception function --
    (( count++ )); atd_step ${count} ${total} "svm.c: RDTSC handler function (div=${rdtsc_div})"
    if ! atd_already_patched "${svm_c}" "handle_rdtsc_interception"; then
        atd_sed "${svm_c}" \
            "s/static int (\\*const svm_exit_handlers/static u32 print_once = 1;\\nstatic int handle_rdtsc_interception(struct kvm_vcpu \\*vcpu){\\n\\tstatic u64 rdtsc_fake = 0;\\n\\tstatic u64 rdtsc_prev = 0;\\n\\tu64 rdtsc_real = rdtsc();\\n\\tif(print_once){\\n\\t\\tprintk(KERN_ALERT \"[handle_rdtsc] svm.c fake rdtsc svm function is working diff ${rdtsc_div} AICodo \\\\n\");\\n\\t\\tprint_once = 0;\\n\\t\\trdtsc_fake = rdtsc_real;\\n\\t}\\n\\tif(rdtsc_prev != 0){\\n\\t\\tif(rdtsc_real > rdtsc_prev){\\n\\t\\t\\tu64 diff = rdtsc_real - rdtsc_prev;\\n\\t\\t\\tu64 fake_diff =  diff \\/ ${rdtsc_div};\\n\\t\\t\\trdtsc_fake += fake_diff;\\n\\t\\t}\\n\\t}\\n\\tif(rdtsc_fake > rdtsc_real){rdtsc_fake = rdtsc_real;}\\n\\trdtsc_prev = rdtsc_real;\\n\\tvcpu->arch.regs[VCPU_REGS_RAX] = rdtsc_fake \\& -1u;\\n\\tvcpu->arch.regs[VCPU_REGS_RDX] = (rdtsc_fake >> 32) \\& -1u;\\n\\treturn svm_skip_emulated_instruction(vcpu);\\n}\\nstatic int (*const svm_exit_handlers/g" \
            "Add SVM RDTSC interception handler"
    else
        atd_skip "svm.c RDTSC handler already patched"
    fi

    # -- Register SVM exit handler --
    (( count++ )); atd_step ${count} ${total} "svm.c: exit handler table entry"
    if ! atd_already_patched "${svm_c}" "SVM_EXIT_RDTSC"; then
        atd_sed "${svm_c}" \
            's/avic_unaccelerated_access_interception,/avic_unaccelerated_access_interception,\n\t[SVM_EXIT_RDTSC]\t\t\t= handle_rdtsc_interception, \/\/added line AICodo /g' \
            "Register SVM RDTSC exit handler"
    else
        atd_skip "svm.c exit handler entry already patched"
    fi

    # -- kvm-amd.ko startup flag --
    (( count++ )); atd_step ${count} ${total} "svm.c: kvm-amd.ko startup flag"
    if ! atd_already_patched "${svm_c}" "kvm-amd.ko AICodo"; then
        atd_sed "${svm_c}" \
            's/__unused_size_checks/printk(KERN_ALERT "kvm-amd.ko AICodo  v2.0 Start,ok!!!\\n");\/\/added line AICodo \n\t__unused_size_checks/g' \
            "Add kvm-amd.ko startup identification"
    else
        atd_skip "svm.c startup flag already patched"
    fi

    atd_ok "Kernel KVM anti-detection patching complete (divisor=${rdtsc_div})"
    return 0
}
