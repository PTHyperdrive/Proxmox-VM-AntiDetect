# Checkpoint-005: Tooling and CI Complete

**Date:** 2026-04-28T15:57:00+07:00
**Phase:** 5 -- Tooling and CI

## Deliverables

| File | Status | Description |
|---|---|---|
| `tools/gen-vm-conf.sh` | Done | VM config generator from hardware profiles |
| `.github/workflows/unified-build.yml` | Done | Consolidated CI/CD pipeline |

## VM Config Generator Features

- Reads any `.conf` or `.json` profile
- Auto-generates SMBIOS args string for QEMU 9/10
- Validates anti-detection constraints (memory sizes, MAC prefix, brand length)
- Random MAC suffix and UUID generation
- Can write directly to `/etc/pve/qemu-server/<VMID>.conf`
- Supports `--validate` mode for checking without generating

## CI Pipeline Features

- Build matrix: parallel builds for qemu, edk2, kernel
- Workflow dispatch with target + profile selection
- Consolidated release with all artifacts
- Replaces the previous 4 separate workflow files
