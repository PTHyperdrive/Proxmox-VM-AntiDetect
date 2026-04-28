# CODING-STYLES.md -- proxmox-atd Terminal Output Standards

> All scripts in this project MUST adhere to these styling rules.
> No standard Unicode emojis. Only the glyph system defined below.

---

## 1. Status Glyphs

| Glyph   | Meaning      | When to Use                                    |
|---------|-------------|------------------------------------------------|
| `[>>]`  | Info / Step  | Announcing a step or general information       |
| `[OK]`  | Success      | Operation completed successfully               |
| `[!!]`  | Warning      | Non-fatal issue, operation continues           |
| `[XX]`  | Error        | Fatal error, operation aborted                 |
| `[--]`  | Skipped      | Step intentionally skipped                     |
| `[??]`  | Prompt       | Awaiting user input or confirmation            |
| `[..]`  | In Progress  | Long-running operation currently executing     |
| `[~~]`  | Dry Run      | Command shown but not executed (dry-run mode)  |
| `[<<]`  | Rollback     | Reverting a previous operation                 |
| `[##]`  | Debug        | Verbose debug output (level 4 only)            |

---

## 2. ANSI Color Codes

All colors use ANSI escape sequences. Scripts MUST use the variables
defined in `lib/atd-styles.sh` -- never hardcode raw escape codes.

| Variable     | Escape Code      | Usage                            |
|-------------|-----------------|----------------------------------|
| `$C_RESET`  | `\033[0m`       | Reset to default                 |
| `$C_BOLD`   | `\033[1m`       | Bold text                        |
| `$C_DIM`    | `\033[2m`       | Dimmed/muted text                |
| `$C_RED`    | `\033[1;31m`    | Errors, fatal messages           |
| `$C_GREEN`  | `\033[1;32m`    | Success, completion              |
| `$C_YELLOW` | `\033[1;33m`    | Warnings, caution                |
| `$C_BLUE`   | `\033[1;34m`    | Hyperlinks, references           |
| `$C_MAGENTA`| `\033[1;35m`    | Section headers, banners         |
| `$C_CYAN`   | `\033[1;36m`    | Info, steps, general output      |
| `$C_WHITE`  | `\033[1;37m`    | Emphasized text                  |
| `$C_GRAY`   | `\033[0;37m`    | Timestamps, metadata             |

---

## 3. Section Banners

Major phases MUST use boxed ASCII banners:

```
+======================================================+
|  PHASE 3/7 :: PATCH -- Applying Anti-Detection Mods  |
+======================================================+
```

Sub-sections use a lighter separator:

```
---- Patching QEMU Brand Identifiers ----
```

---

## 4. Step Progress Format

Sequential operations MUST use numbered step prefixes:

```
[>>] [STEP 03/17] Patching hw/acpi/aml-build.c ...
[OK] [STEP 03/17] Patched 4 targets in hw/acpi/aml-build.c
```

---

## 5. Log Levels

Controlled by environment variable `ATD_LOG_LEVEL`:

| Level | Name    | Description                                |
|-------|---------|---------------------------------------------|
| `0`   | Silent  | No output (only exit codes)                 |
| `1`   | Error   | `[XX]` messages only                        |
| `2`   | Warn    | `[XX]` + `[!!]` messages                    |
| `3`   | Info    | `[XX]` + `[!!]` + `[>>]` + `[OK]` (default)|
| `4`   | Debug   | All messages including `[##]`               |

---

## 6. Timestamp Format

When timestamps are shown (log files, debug mode):

```
[2026-04-28 15:33:41 +07:00] [>>] Starting build ...
```

Format: `YYYY-MM-DD HH:MM:SS TZ`

---

## 7. Error Output Format

Errors MUST include:
1. The glyph `[XX]`
2. A human-readable message
3. The failing command (when applicable)
4. Suggested remediation

```
[XX] Failed to clone pve-qemu repository
     Command: git clone git://git.proxmox.com/git/pve-qemu.git
     Reason:  Network unreachable
     Fix:     Check DNS resolution and firewall rules
```

---

## 8. Function Library Usage

All scripts MUST source the shared library:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/atd-styles.sh"
```

Available functions:

| Function                        | Purpose                                    |
|--------------------------------|---------------------------------------------|
| `atd_log <level> <msg>`       | Log a message at the specified level        |
| `atd_info <msg>`              | Shorthand for `atd_log INFO`                |
| `atd_ok <msg>`                | Shorthand for `atd_log OK`                  |
| `atd_warn <msg>`              | Shorthand for `atd_log WARN`                |
| `atd_err <msg>`               | Shorthand for `atd_log ERROR`               |
| `atd_debug <msg>`             | Shorthand for `atd_log DEBUG`               |
| `atd_skip <msg>`              | Shorthand for `atd_log SKIP`                |
| `atd_dry <msg>`               | Shorthand for `atd_log DRY`                 |
| `atd_banner <phase> <title>`  | Print a boxed section banner                |
| `atd_separator <title>`       | Print a sub-section separator               |
| `atd_step <n> <total> <msg>`  | Print a numbered step line                  |
| `atd_confirm <prompt>`        | Prompt user for Y/N confirmation            |
| `atd_die <msg> [exit_code]`   | Print error and exit                        |
| `atd_timer_start`             | Start a timer (stores epoch)                |
| `atd_timer_stop <label>`      | Stop timer, print elapsed time              |

---

## 9. Script Header Standard

Every script MUST begin with:

```bash
#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: <Script Name>
#  <One-line description>
#
#  Usage: ./<script-name>.sh [options]
#  Part of: https://github.com/<your-repo>/proxmox-atd
# ---------------------------------------------------------------
set -euo pipefail
```

---

## 10. Exit Code Convention

| Code | Meaning                                |
|------|----------------------------------------|
| `0`  | Success                                |
| `1`  | General / unspecified error             |
| `2`  | Invalid arguments or configuration     |
| `3`  | Missing dependency                     |
| `4`  | Patch application failure              |
| `5`  | Build failure                          |
| `6`  | Verification failure                   |
| `10` | User cancelled (interactive prompt)    |

---

## 11. Prohibited Patterns

- **No Unicode emojis** (`U+1F600`-`U+1F64F`, etc.) in any output
- **No raw `echo`** for user-facing messages -- use `atd_log` family
- **No hardcoded ANSI codes** -- use `$C_*` variables from `atd-styles.sh`
- **No `cd`** without `pushd`/`popd` or subshell isolation
- **No unquoted variables** -- always `"${var}"`
