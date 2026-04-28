# Checkpoint-004: Build Orchestrator Complete

**Date:** 2026-04-28T15:55:00+07:00
**Phase:** 4 -- Build Orchestrator

## Deliverables

| File | Status | Description |
|---|---|---|
| `pve-build-orchestrator.sh` | Done | 8-phase unified build pipeline |

## Phases

1. **PREFLIGHT** -- Root check, OS detection, disk space, RAM, profile validation
2. **DEPS** -- Unified dependency list (deduped across all 3 targets, ~60 packages)
3. **CLONE** -- Clone upstream Proxmox repos + submodule init + mk-build-deps
4. **PATCH** -- Invokes `atd-patcher.sh` with configured profile and targets
5. **BUILD** -- Parallel make with `-j$(nproc)` support
6. **PACKAGE** -- Collects .deb, .ko, .patch, .aml artifacts
7. **VERIFY** -- Post-build artifact existence validation
8. **CLEANUP** -- Git checkout reset of source trees

## Features

- Target selection: `--target qemu|edk2|kernel|all`
- Resume from any phase: `--resume-from <phase>`
- Full dry-run: `--dry-run`
- Build logging to `/var/log/atd-build-*.log`
- Error trap with resume instructions on failure
