# Checkpoint-003: Patcher Engine Complete

**Date:** 2026-04-28T15:53:00+07:00
**Phase:** 3 -- Patcher Engine

## Deliverables

| File | Status | Description |
|---|---|---|
| `patches/qemu-brand.patch.sh` | Done | 47-step brand replacement across ~50 QEMU source files |
| `patches/qemu-acpi.patch.sh` | Done | vmgenid, FADT rev, sleep regs, C-state, DSDT _OSI/_TZ/_PTS |
| `patches/qemu-smbios.patch.sh` | Done | 14-step SMBIOS type 0/4/16/17 hardware values from config |
| `patches/qemu-ide-sata.patch.sh` | Done | Random serials, SMART data (power-on hours, cycle count) |
| `patches/qemu-usb-scsi.patch.sh` | Done | SPD EEPROM injection, PCI USB IDs, HDA audio vendor |
| `patches/qemu-pci-ids.patch.sh` | Done | GPU passthrough fix, bootsplash customization |
| `patches/qemu-kvm-cpuid.patch.sh` | Done | KVM hypervisor CPUID signature nullification |
| `patches/qemu-misc.patch.sh` | Done | Custom SMBIOS overlay, bootsplash file copy |
| `patches/edk2-brand.patch.sh` | Done | EDK2/OVMF driver and library INF renaming |
| `patches/kernel-rdtsc.patch.sh` | Done | Kernel patch application via git apply/patch |
| `atd-patcher.sh` | Done | Main engine: config loading, module orchestration, dry-run, rollback |

## Architecture

- 10 independent patch modules, each exporting a `patch_*()` function
- All config-driven via `atd_config_get()`, no hardcoded values
- Idempotency guards (`atd_already_patched`) prevent double-patching
- Full dry-run support (`--dry-run` flag)
- Backup/rollback via `.atd-backup/` directory
