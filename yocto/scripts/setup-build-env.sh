#!/usr/bin/env bash
# Sets up the Yocto Scarthgap build environment on a Linux build host.
# Run once after cloning poky and all required layers.
#
# Usage: source yocto/scripts/setup-build-env.sh [build-dir]
#
# After sourcing, you are inside the build directory with BitBake on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
POKY_DIR="${POKY_DIR:-${REPO_ROOT}/yocto/poky}"
BUILD_DIR="${1:-${REPO_ROOT}/yocto/builds/rpi5}"

# ── Verify Poky exists ─────────────────────────────────────────────────────
if [[ ! -f "${POKY_DIR}/oe-init-build-env" ]]; then
    echo "ERROR: poky not found at ${POKY_DIR}"
    echo "Clone it first:"
    echo "  cd yocto && git clone -b scarthgap git://git.yoctoproject.org/poky"
    return 1
fi

# ── Host dependency check ──────────────────────────────────────────────────
MISSING=()
for cmd in git python3 gcc make chrpath diffstat lz4c zstd; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: Missing host tools: ${MISSING[*]}"
    echo "Install with:"
    echo "  sudo apt-get install -y git python3 gcc make chrpath diffstat \\"
    echo "    liblz4-tool zstd gawk wget file cpio xz-utils"
    return 1
fi

# ── Initialize the build environment ──────────────────────────────────────
source "${POKY_DIR}/oe-init-build-env" "${BUILD_DIR}"

echo ""
echo "Build environment ready."
echo "  Build dir : ${BUILD_DIR}"
echo "  MACHINE   : $(grep '^MACHINE' conf/local.conf 2>/dev/null | head -1 || echo '(not set)')"
echo ""
echo "Next step: bitbake securepi-image"
