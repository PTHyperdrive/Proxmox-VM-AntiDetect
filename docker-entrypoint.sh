#!/usr/bin/env bash
# ---------------------------------------------------------------
#  proxmox-atd :: Docker Entrypoint
#  Builds in a container-internal directory to avoid Windows/macOS
#  volume-mount filesystem issues (symlinks, permissions, cp -a).
#  Only final artifacts are copied to the mounted output volume.
# ---------------------------------------------------------------
set -uo pipefail
# NOTE: do NOT use 'set -e' — we need artifact copy to run even if the build fails

INTERNAL_BUILD="/tmp/atd-build"
MOUNT_OUTPUT="/build/build-output"

echo "[>>] Building in container-internal directory: ${INTERNAL_BUILD}"

# Run the orchestrator with internal build dir
# Capture the real exit code without aborting (set -e is off, so this is safe)
BUILD_RC=0
bash /build/pve-build-orchestrator.sh \
    --skip-deps \
    --output "${INTERNAL_BUILD}" \
    "$@" || BUILD_RC=$?

# Copy artifacts to mounted volume (if mount exists)
if [[ -d "${MOUNT_OUTPUT}" ]]; then
    echo ""
    echo "[>>] Copying artifacts to mounted output ..."
    mkdir -p "${MOUNT_OUTPUT}/artifacts"

    # 1) Copy from the orchestrator's artifacts/ directory
    if [[ -d "${INTERNAL_BUILD}/artifacts" ]]; then
        cp -r "${INTERNAL_BUILD}/artifacts/"* "${MOUNT_OUTPUT}/artifacts/" 2>/dev/null || true
    fi

    # 2) Fallback: find ALL .deb files in the build tree (covers partial builds)
    deb_count=0
    while IFS= read -r -d '' debfile; do
        cp -v "${debfile}" "${MOUNT_OUTPUT}/artifacts/" 2>/dev/null || true
        (( deb_count++ )) || true
    done < <(find "${INTERNAL_BUILD}" -maxdepth 3 -name '*.deb' ! -name '*dbgsym*' -print0 2>/dev/null)

    if (( deb_count > 0 )); then
        echo "[OK] Copied ${deb_count} .deb file(s) to ${MOUNT_OUTPUT}/artifacts/"
    else
        echo "[!!] No .deb files found in build tree"
    fi

    # 3) List what we collected
    echo ""
    echo "[>>] Artifacts:"
    ls -lh "${MOUNT_OUTPUT}/artifacts/" 2>/dev/null || echo "  (empty)"
fi

# Also copy build logs
if [[ -d "${MOUNT_OUTPUT}" ]]; then
    if ls "${INTERNAL_BUILD}"/*.log 1>/dev/null 2>&1; then
        cp "${INTERNAL_BUILD}"/*.log "${MOUNT_OUTPUT}/" 2>/dev/null || true
    fi
    if ls /build/atd-*.log 1>/dev/null 2>&1; then
        cp /build/atd-*.log "${MOUNT_OUTPUT}/" 2>/dev/null || true
    fi
fi

exit ${BUILD_RC}
