#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Docker Build Wrapper
#  Convenience script to build inside Docker without needing PVE
#
#  Usage:
#    ./docker-build.sh                      # Build all targets
#    ./docker-build.sh --target qemu        # QEMU only
#    ./docker-build.sh --target kernel      # Kernel only
#    ./docker-build.sh --target edk2        # EDK2 only
#    ./docker-build.sh --no-cache           # Force rebuild image
#
#  Artifacts will appear in ./build-output/artifacts/
#  Part of: https://github.com/proxmox-atd
# ---------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="atd-builder"
CONTAINER_NAME="atd-build-$$"
OUTPUT_DIR="${SCRIPT_DIR}/build-output"

# ── Parse wrapper-specific flags ──
DOCKER_BUILD_ARGS=()
ORCHESTRATOR_ARGS=()
NO_CACHE=""

for arg in "$@"; do
    case "${arg}" in
        --no-cache)
            NO_CACHE="--no-cache"
            ;;
        *)
            ORCHESTRATOR_ARGS+=("${arg}")
            ;;
    esac
done

# ── Colors ──
C_CYAN='\033[1;36m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_DIM='\033[2m'
C_RESET='\033[0m'

echo ""
echo -e "${C_CYAN}+======================================================+${C_RESET}"
echo -e "${C_CYAN}|  ${C_GREEN}proxmox-atd :: Docker Build${C_CYAN}                         |${C_RESET}"
echo -e "${C_CYAN}+======================================================+${C_RESET}"
echo ""

# ── Build the Docker image ──
echo -e "${C_CYAN}[>>]${C_RESET} Building Docker image: ${IMAGE_NAME} ..."
docker build ${NO_CACHE} -t "${IMAGE_NAME}" "${SCRIPT_DIR}"
echo -e "${C_GREEN}[OK]${C_RESET} Docker image ready"
echo ""

# ── Create output directory ──
mkdir -p "${OUTPUT_DIR}"

# ── Run the build ──
echo -e "${C_CYAN}[>>]${C_RESET} Starting build container ..."
echo -e "${C_DIM}     Args: ${ORCHESTRATOR_ARGS[*]:-<default: --target all>}${C_RESET}"
echo ""

docker run \
    --rm \
    --name "${CONTAINER_NAME}" \
    -v "${OUTPUT_DIR}:/build/build-output" \
    -e "CI=1" \
    "${IMAGE_NAME}" \
    "${ORCHESTRATOR_ARGS[@]:-}"

BUILD_RC=$?

echo ""
if (( BUILD_RC == 0 )); then
    echo -e "${C_GREEN}[OK]${C_RESET} Build complete! Artifacts:"
    ls -lh "${OUTPUT_DIR}/artifacts/" 2>/dev/null || echo -e "${C_YELLOW}[!!]${C_RESET} No artifacts found in ${OUTPUT_DIR}/artifacts/"
else
    echo -e "${C_RED}[XX]${C_RESET} Build failed with exit code ${BUILD_RC}"
fi

exit ${BUILD_RC}
