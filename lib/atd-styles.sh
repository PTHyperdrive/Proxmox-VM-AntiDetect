#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Shared Styling Library
#  Terminal output functions adhering to CODING-STYLES.md
#
#  Usage: source "lib/atd-styles.sh"
#  Part of: https://github.com/proxmox-atd
# ---------------------------------------------------------------

# -- Guard against double-sourcing --
[[ -n "${_ATD_STYLES_LOADED:-}" ]] && return 0
_ATD_STYLES_LOADED=1

# ===== ANSI Color Codes =====
if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RED='\033[1;31m'
    C_GREEN='\033[1;32m'
    C_YELLOW='\033[1;33m'
    C_BLUE='\033[1;34m'
    C_MAGENTA='\033[1;35m'
    C_CYAN='\033[1;36m'
    C_WHITE='\033[1;37m'
    C_GRAY='\033[0;37m'
else
    C_RESET='' C_BOLD='' C_DIM=''
    C_RED='' C_GREEN='' C_YELLOW=''
    C_BLUE='' C_MAGENTA='' C_CYAN=''
    C_WHITE='' C_GRAY=''
fi
export C_RESET C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_MAGENTA C_CYAN C_WHITE C_GRAY

# ===== Configuration =====
ATD_LOG_LEVEL="${ATD_LOG_LEVEL:-3}"  # Default: Info
ATD_DRY_RUN="${ATD_DRY_RUN:-0}"
ATD_LOG_FILE="${ATD_LOG_FILE:-}"

# ===== Internal: Timestamp =====
_atd_timestamp() {
    date '+%Y-%m-%d %H:%M:%S %z'
}

# ===== Internal: Write to log file =====
_atd_log_file() {
    if [[ -n "${ATD_LOG_FILE}" ]]; then
        local stripped
        stripped="$(echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g')"
        echo "[$(_atd_timestamp)] ${stripped}" >> "${ATD_LOG_FILE}"
    fi
}

# ===== Core Logging =====
# Usage: atd_log <LEVEL> <message>
# Levels: ERROR, WARN, INFO, OK, DEBUG, SKIP, DRY, ROLLBACK, PROGRESS
atd_log() {
    local level="$1"
    shift
    local msg="$*"
    local glyph color min_level

    case "${level}" in
        ERROR)    glyph="[XX]"; color="${C_RED}";     min_level=1 ;;
        WARN)     glyph="[!!]"; color="${C_YELLOW}";  min_level=2 ;;
        INFO)     glyph="[>>]"; color="${C_CYAN}";    min_level=3 ;;
        OK)       glyph="[OK]"; color="${C_GREEN}";   min_level=3 ;;
        SKIP)     glyph="[--]"; color="${C_DIM}";     min_level=3 ;;
        DRY)      glyph="[~~]"; color="${C_MAGENTA}"; min_level=3 ;;
        ROLLBACK) glyph="[<<]"; color="${C_YELLOW}";  min_level=3 ;;
        PROGRESS) glyph="[..]"; color="${C_CYAN}";    min_level=3 ;;
        DEBUG)    glyph="[##]"; color="${C_GRAY}";    min_level=4 ;;
        PROMPT)   glyph="[??]"; color="${C_WHITE}";   min_level=1 ;;
        *)        glyph="[>>]"; color="${C_CYAN}";    min_level=3 ;;
    esac

    _atd_log_file "${glyph} ${msg}"

    if (( ATD_LOG_LEVEL >= min_level )); then
        echo -e "${color}${glyph}${C_RESET} ${msg}"
    fi
}

# ===== Shorthand Functions =====
atd_info()  { atd_log INFO "$@"; }
atd_ok()    { atd_log OK "$@"; }
atd_warn()  { atd_log WARN "$@"; }
atd_err()   { atd_log ERROR "$@"; }
atd_debug() { atd_log DEBUG "$@"; }
atd_skip()  { atd_log SKIP "$@"; }
atd_dry()   { atd_log DRY "$@"; }

# ===== Banner: Major Phase Header =====
# Usage: atd_banner <phase_str> <title>
# Example: atd_banner "PHASE 3/7" "PATCH -- Applying Anti-Detection Mods"
atd_banner() {
    local phase="$1"
    local title="$2"
    local content="  ${phase} :: ${title}  "
    local width=${#content}
    (( width < 56 )) && width=56
    local border
    border=$(printf '%*s' "${width}" '' | tr ' ' '=')

    if (( ATD_LOG_LEVEL >= 3 )); then
        echo ""
        echo -e "${C_MAGENTA}+${border}+${C_RESET}"
        printf "${C_MAGENTA}|${C_BOLD}%-${width}s${C_MAGENTA}|${C_RESET}\n" "${content}"
        echo -e "${C_MAGENTA}+${border}+${C_RESET}"
        echo ""
    fi
    _atd_log_file "===== ${phase} :: ${title} ====="
}

# ===== Separator: Sub-section Header =====
# Usage: atd_separator <title>
atd_separator() {
    local title="$1"
    if (( ATD_LOG_LEVEL >= 3 )); then
        echo -e "${C_DIM}---- ${title} ----${C_RESET}"
    fi
    _atd_log_file "---- ${title} ----"
}

# ===== Step: Numbered Progress =====
# Usage: atd_step <current> <total> <message>
atd_step() {
    local current="$1"
    local total="$2"
    shift 2
    local msg="$*"
    local padded
    padded=$(printf '%02d' "${current}")
    local padded_total
    padded_total=$(printf '%02d' "${total}")
    atd_info "${C_DIM}[STEP ${padded}/${padded_total}]${C_RESET} ${msg}"
}

# ===== Confirm: Y/N Prompt =====
# Usage: atd_confirm "Are you sure?" && do_thing
# Returns 0 for yes, 1 for no
atd_confirm() {
    local prompt="$1"
    local reply
    echo -en "${C_WHITE}[??]${C_RESET} ${prompt} ${C_DIM}[y/N]${C_RESET} "
    read -r reply
    case "${reply}" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ===== Die: Fatal Error + Exit =====
# Usage: atd_die <message> [exit_code]
atd_die() {
    local msg="$1"
    local code="${2:-1}"
    atd_err "${msg}"
    exit "${code}"
}

# ===== Timer =====
_ATD_TIMER_START=0

atd_timer_start() {
    _ATD_TIMER_START=$(date +%s)
}

# Usage: atd_timer_stop <label>
atd_timer_stop() {
    local label="$1"
    local end
    end=$(date +%s)
    local elapsed=$(( end - _ATD_TIMER_START ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))
    atd_ok "${label} completed in ${mins}m ${secs}s"
}

# ===== Error Detail Block =====
# Usage: atd_error_detail <message> <command> <reason> <fix>
atd_error_detail() {
    local msg="$1"
    local cmd="${2:-}"
    local reason="${3:-}"
    local fix="${4:-}"
    atd_err "${msg}"
    [[ -n "${cmd}" ]]    && echo -e "     ${C_DIM}Command:${C_RESET} ${cmd}"
    [[ -n "${reason}" ]] && echo -e "     ${C_DIM}Reason:${C_RESET}  ${reason}"
    [[ -n "${fix}" ]]    && echo -e "     ${C_DIM}Fix:${C_RESET}     ${fix}"
}

# ===== Sed Wrapper with Verification =====
# Usage: atd_sed <file> <pattern> <description> [--allow-missing]
# Runs sed -i, then verifies the replacement landed.
# In dry-run mode, prints the command without executing.
atd_sed() {
    local file="$1"
    local pattern="$2"
    local desc="$3"
    local allow_missing="${4:-}"

    if (( ATD_DRY_RUN )); then
        atd_dry "sed -i '${pattern}' ${file}"
        atd_dry "  -> ${desc}"
        return 0
    fi

    if [[ ! -f "${file}" ]]; then
        if [[ "${allow_missing}" == "--allow-missing" ]]; then
            atd_skip "File not found (allowed): ${file}"
            return 0
        else
            atd_err "Target file not found: ${file}"
            return 1
        fi
    fi

    sed -i "${pattern}" "${file}"
    local rc=$?

    if (( rc != 0 )); then
        atd_err "sed failed on ${file}: ${desc}"
        return 1
    fi

    atd_debug "Patched: ${desc} in $(basename "${file}")"
    return 0
}

# ===== Sed Wrapper with Pre/Post Verification =====
# Usage: atd_sed_verify <file> <sed_pattern> <verify_grep> <description>
# Runs sed, then greps for expected result to confirm patch applied.
atd_sed_verify() {
    local file="$1"
    local sed_pattern="$2"
    local verify_grep="$3"
    local desc="$4"

    atd_sed "${file}" "${sed_pattern}" "${desc}" || return 1

    if (( ! ATD_DRY_RUN )); then
        if ! grep -q "${verify_grep}" "${file}" 2>/dev/null; then
            atd_warn "Verification failed for: ${desc} in $(basename "${file}")"
            atd_warn "  Expected to find: ${verify_grep}"
            return 1
        fi
        atd_debug "Verified: ${desc}"
    fi
    return 0
}

# ===== Backup/Rollback System =====
ATD_BACKUP_DIR=""

# Initialize backup directory
# Usage: atd_backup_init <base_dir>
atd_backup_init() {
    local base="$1"
    ATD_BACKUP_DIR="${base}/.atd-backup/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${ATD_BACKUP_DIR}"
    atd_debug "Backup directory: ${ATD_BACKUP_DIR}"
}

# Backup a file before patching
# Usage: atd_backup_file <filepath>
atd_backup_file() {
    local filepath="$1"
    if [[ -z "${ATD_BACKUP_DIR}" ]]; then
        atd_warn "Backup not initialized, skipping backup of ${filepath}"
        return 0
    fi
    if [[ -f "${filepath}" ]]; then
        local relpath="${filepath#/}"
        local dest="${ATD_BACKUP_DIR}/${relpath}"
        mkdir -p "$(dirname "${dest}")"
        cp -a "${filepath}" "${dest}"
        atd_debug "Backed up: ${filepath}"
    fi
}

# Rollback all backed-up files
# Usage: atd_rollback <backup_timestamp_dir>
atd_rollback() {
    local backup_dir="$1"
    if [[ ! -d "${backup_dir}" ]]; then
        atd_err "Backup directory not found: ${backup_dir}"
        return 1
    fi
    atd_log ROLLBACK "Restoring files from ${backup_dir} ..."
    local count=0
    while IFS= read -r -d '' backed_file; do
        local relpath="${backed_file#${backup_dir}/}"
        local dest="/${relpath}"
        cp -a "${backed_file}" "${dest}"
        (( count++ ))
    done < <(find "${backup_dir}" -type f -print0)
    atd_ok "Rolled back ${count} file(s)"
}

# ===== INI Config Parser =====
# Usage: atd_parse_ini <file> <section> <key>
# Returns the value for [section].key from an INI file
atd_parse_ini() {
    local file="$1"
    local section="$2"
    local key="$3"
    local in_section=0
    local value=""

    while IFS= read -r line; do
        # Strip comments and whitespace
        line="${line%%#*}"
        line="${line%%\;*}"
        line="$(echo "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "${line}" ]] && continue

        # Section header
        if [[ "${line}" =~ ^\[([^]]+)\]$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "${section}" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi

        # Key=Value in matching section
        if (( in_section )) && [[ "${line}" =~ ^([^=]+)=(.*)$ ]]; then
            local k="${BASH_REMATCH[1]}"
            local v="${BASH_REMATCH[2]}"
            k="$(echo "${k}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            v="$(echo "${v}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')"
            if [[ "${k}" == "${key}" ]]; then
                value="${v}"
            fi
        fi
    done < "${file}"

    echo "${value}"
}

# ===== JSON Config Parser =====
# Usage: atd_parse_json <file> <jq_expression>
# Requires jq. Falls back to grep-based extraction for simple keys.
atd_parse_json() {
    local file="$1"
    local expr="$2"

    if command -v jq &>/dev/null; then
        jq -r "${expr}" "${file}" 2>/dev/null
    else
        atd_warn "jq not found, using fallback JSON parser (limited)"
        # Fallback: extract simple top-level or one-deep keys
        # expr format expected: .section.key
        local section key
        section="$(echo "${expr}" | cut -d. -f2)"
        key="$(echo "${expr}" | cut -d. -f3)"
        if [[ -n "${key}" ]]; then
            grep -A 100 "\"${section}\"" "${file}" | \
                grep "\"${key}\"" | head -1 | \
                sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/'
        else
            grep "\"${section}\"" "${file}" | head -1 | \
                sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/'
        fi
    fi
}

# ===== Unified Config Reader =====
# Usage: atd_config_get <config_file> <section> <key>
# Auto-detects INI vs JSON based on file extension
atd_config_get() {
    local file="$1"
    local section="$2"
    local key="$3"

    case "${file}" in
        *.json)
            atd_parse_json "${file}" ".${section}.${key}"
            ;;
        *.conf|*.ini)
            atd_parse_ini "${file}" "${section}" "${key}"
            ;;
        *)
            atd_warn "Unknown config format: ${file}, trying INI"
            atd_parse_ini "${file}" "${section}" "${key}"
            ;;
    esac
}

# ===== Idempotency Check =====
# Usage: atd_already_patched <file> <marker_string>
# Returns 0 if marker found (already patched), 1 if not
atd_already_patched() {
    local file="$1"
    local marker="$2"
    if grep -q "${marker}" "${file}" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ===== Summary Table =====
# Usage: atd_summary <title> <key1> <val1> [<key2> <val2> ...]
atd_summary() {
    local title="$1"
    shift
    echo ""
    echo -e "${C_BOLD}${title}${C_RESET}"
    echo -e "${C_DIM}$(printf '%*s' 50 '' | tr ' ' '-')${C_RESET}"
    while (( $# >= 2 )); do
        printf "  ${C_CYAN}%-24s${C_RESET} %s\n" "$1" "$2"
        shift 2
    done
    echo -e "${C_DIM}$(printf '%*s' 50 '' | tr ' ' '-')${C_RESET}"
    echo ""
}
