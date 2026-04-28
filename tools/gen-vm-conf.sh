#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: VM Configuration Generator
#  Generates /etc/pve/qemu-server/<VMID>.conf from a profile
#
#  Usage: ./tools/gen-vm-conf.sh [options]
#    --profile <file>   Config profile (.conf or .json)
#    --vmid <id>        VM ID (default: 100)
#    --output <file>    Output file (default: stdout)
#    --qemu-version <v> 9|10 (default: 10)
#    --validate         Validate without generating
#    --help             Show help
#
#  REMOTE EXECUTION ONLY -- run on your Proxmox server
# ---------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/atd-styles.sh"

PROFILE="${SCRIPT_DIR}/../profiles/default.conf"
VMID="100"
OUTPUT=""
QEMU_VER="10"
VALIDATE_ONLY=0

usage() {
    cat <<EOF
proxmox-atd VM Configuration Generator

Usage: $(basename "$0") [options]

Options:
  --profile <file>      Config profile (default: profiles/default.conf)
  --vmid <id>           VM ID (default: 100)
  --output <file>       Output file (default: print to stdout)
  --qemu-version <ver>  QEMU version: 9 or 10 (default: 10)
  --validate            Validate config without generating
  --help                Show this help

Examples:
  # Generate to stdout
  ./tools/gen-vm-conf.sh --profile profiles/default.conf --vmid 102

  # Write directly to PVE config
  sudo ./tools/gen-vm-conf.sh --vmid 102 \\
       --output /etc/pve/qemu-server/102.conf

  # Validate only
  ./tools/gen-vm-conf.sh --profile profiles/example-intel-desktop.conf --validate
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)       PROFILE="$2"; shift 2 ;;
        --vmid)          VMID="$2"; shift 2 ;;
        --output)        OUTPUT="$2"; shift 2 ;;
        --qemu-version)  QEMU_VER="$2"; shift 2 ;;
        --validate)      VALIDATE_ONLY=1; shift ;;
        --help)          usage ;;
        *)               atd_die "Unknown option: $1" 2 ;;
    esac
done

[[ ! -f "${PROFILE}" ]] && atd_die "Profile not found: ${PROFILE}" 2

# ===== Read Config =====
cfg() { atd_config_get "${PROFILE}" "$1" "$2"; }

BRAND="$(cfg brand name)";                  BRAND="${BRAND:-ASUS}"
T0_VENDOR="$(cfg smbios_type0 vendor)";     T0_VENDOR="${T0_VENDOR:-American Megatrends International LLC.}"
T0_VERSION="$(cfg smbios_type0 version)";   T0_VERSION="${T0_VERSION:-H3.7G}"
T0_DATE="$(cfg smbios_type0 date)";         T0_DATE="${T0_DATE:-02/21/2023}"
T0_REL_MAJ="$(cfg smbios_type0 release_major)"; T0_REL_MAJ="${T0_REL_MAJ:-3}"
T0_REL_MIN="$(cfg smbios_type0 release_minor)"; T0_REL_MIN="${T0_REL_MIN:-7}"

T1_MFG="$(cfg smbios_type1 manufacturer)";  T1_MFG="${T1_MFG:-ASUS}"
T1_PROD="$(cfg smbios_type1 product)";      T1_PROD="${T1_PROD:-PRIME B760M-A}"
T1_VER="$(cfg smbios_type1 version)";       T1_VER="${T1_VER:-VER:H3.7G(2022/11/29)}"
T1_SER="$(cfg smbios_type1 serial)";        T1_SER="${T1_SER:-Default string}"
T1_SKU="$(cfg smbios_type1 sku)";           T1_SKU="${T1_SKU:-Default string}"
T1_FAM="$(cfg smbios_type1 family)";        T1_FAM="${T1_FAM:-Default string}"

T2_MFG="$(cfg smbios_type2 manufacturer)";  T2_MFG="${T2_MFG:-ASUS}"
T2_PROD="$(cfg smbios_type2 product)";      T2_PROD="${T2_PROD:-PRIME B760M-A}"
T2_VER="$(cfg smbios_type2 version)";       T2_VER="${T2_VER:-VER:H3.7G(2022/11/29)}"
T2_SER="$(cfg smbios_type2 serial)";        T2_SER="${T2_SER:-Default string}"
T2_ASSET="$(cfg smbios_type2 asset)";       T2_ASSET="${T2_ASSET:-Default string}"
T2_LOC="$(cfg smbios_type2 location)";      T2_LOC="${T2_LOC:-Default string}"

T3_MFG="$(cfg smbios_type3 manufacturer)";  T3_MFG="${T3_MFG:-Default string}"
T3_VER="$(cfg smbios_type3 version)";       T3_VER="${T3_VER:-Default string}"
T3_SER="$(cfg smbios_type3 serial)";        T3_SER="${T3_SER:-Default string}"
T3_ASSET="$(cfg smbios_type3 asset)";       T3_ASSET="${T3_ASSET:-Default string}"
T3_SKU="$(cfg smbios_type3 sku)";           T3_SKU="${T3_SKU:-Default string}"

T4_MFG="$(cfg smbios_type4 manufacturer)";  T4_MFG="${T4_MFG:-Intel(R) Corporation}"
T4_VER="$(cfg smbios_type4 version)";       T4_VER="${T4_VER:-12th Gen Intel(R) 0000}"

T17_SER="$(cfg smbios_type17 serial)";      T17_SER="${T17_SER:-DF1EC466}"
T17_ASSET="$(cfg smbios_type17 asset)";     T17_ASSET="${T17_ASSET:-9876543210}"

MEM="$(cfg vm_config memory)";              MEM="${MEM:-16384}"
CORES="$(cfg vm_config cores)";             CORES="${CORES:-8}"
SOCKETS="$(cfg vm_config sockets)";         SOCKETS="${SOCKETS:-1}"
DISK_SIZE="$(cfg vm_config disk_size)";     DISK_SIZE="${DISK_SIZE:-128G}"
NIC="$(cfg network nic_model)";             NIC="${NIC:-e1000}"
MAC_PFX="$(cfg network mac_prefix)";        MAC_PFX="${MAC_PFX:-D8:FC:93}"

# ===== Validation =====
ERRORS=0

# Memory must be 4096, 8192, or 16384
case "${MEM}" in
    4096|8192|16384) ;;
    *) atd_err "Memory must be 4096, 8192, or 16384 (got: ${MEM})"; (( ERRORS++ )) ;;
esac

# MAC prefix
if [[ ! "${MAC_PFX}" =~ ^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$ ]]; then
    atd_err "Invalid MAC prefix: ${MAC_PFX} (expected XX:XX:XX)"; (( ERRORS++ ))
fi

# Brand length
if [[ ${#BRAND} -ne 4 ]]; then
    atd_err "Brand must be 4 characters: ${BRAND}"; (( ERRORS++ ))
fi

# Sockets must be 1
if [[ "${SOCKETS}" != "1" ]]; then
    atd_warn "Sockets should be 1 for anti-detection (got: ${SOCKETS})"
fi

if (( ERRORS > 0 )); then
    atd_die "Validation failed with ${ERRORS} error(s)" 2
fi

if (( VALIDATE_ONLY )); then
    atd_ok "Profile validated successfully"
    exit 0
fi

# ===== Generate random MAC suffix =====
MAC_SUFFIX=$(printf '%02X:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
MAC="${MAC_PFX}:${MAC_SUFFIX}"

# ===== Generate UUID =====
UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "505429c8-a350-41e9-9154-3851c095254e")
VMGENID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "2271babc-cafc-4c68-be8b-2bb3157c9924")

# ===== Build SMBIOS args =====
ARGS="args: -acpitable file=/root/ssdt.aml -acpitable file=/root/ssdt-ec.aml -acpitable file=/root/hpet.aml"
ARGS+=" -cpu host,host-cache-info=on,hypervisor=off,vmware-cpuid-freq=false,enforce=false,host-phys-bits=true"
ARGS+=" -smbios type=0,vendor=\"${T0_VENDOR}\",version=${T0_VERSION},date='${T0_DATE}',release=${T0_REL_MAJ}.${T0_REL_MIN}"
ARGS+=" -smbios type=1,manufacturer=\"${T1_MFG}\",product=\"${T1_PROD}\",version=\"${T1_VER}\",serial=\"${T1_SER}\",sku=\"${T1_SKU}\",family=\"${T1_FAM}\""
ARGS+=" -smbios type=2,manufacturer=\"${T2_MFG}\",product=\"${T2_PROD}\",version=\"${T2_VER}\",serial=\"${T2_SER}\",asset=\"${T2_ASSET}\",location=\"${T2_LOC}\""
ARGS+=" -smbios type=3,manufacturer=\"${T3_MFG}\",version=\"${T3_VER}\",serial=\"${T3_SER}\",asset=\"${T3_ASSET}\",sku=\"${T3_SKU}\""
ARGS+=" -smbios type=17,serial=${T17_SER},asset=\"${T17_ASSET}\""
ARGS+=" -smbios type=4,manufacturer=\"${T4_MFG}\",version=\"${T4_VER}\""
ARGS+=" -smbios type=9 -smbios type=8 -smbios type=8"

# ===== Generate Config =====
CONFIG="${ARGS}
balloon: 0
bios: ovmf
boot: order=ide2;sata0;net0
cores: ${CORES}
cpu: host
efidisk0: local:${VMID}/vm-${VMID}-disk-0.raw,efitype=4m,size=528K
ide2: none,media=cdrom
localtime: 1
memory: ${MEM}
meta: creation-qemu=10.0.0,ctime=$(date +%s)
name: win10-atd
net0: ${NIC}=${MAC},bridge=vmbr0,firewall=1
numa: 0
ostype: l26
sata0: local:${VMID}/vm-${VMID}-disk-1.raw,size=${DISK_SIZE},ssd=1,serial=0123456789ABCDEF0123
scsihw: virtio-scsi-single
smbios1: uuid=${UUID}
sockets: ${SOCKETS}
vmgenid: ${VMGENID}"

# ===== Output =====
if [[ -n "${OUTPUT}" ]]; then
    echo "${CONFIG}" > "${OUTPUT}"
    atd_ok "VM config written to ${OUTPUT}"
else
    echo "${CONFIG}"
fi
