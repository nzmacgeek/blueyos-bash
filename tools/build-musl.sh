#!/usr/bin/env bash
# tools/build-musl.sh — clone nzmacgeek/musl-blueyos and build it for i386
#
# Usage:
#   ./tools/build-musl.sh [--prefix=<path>] [--ref=<branch-or-tag>]
#
# Variables:
#   PREFIX        - install prefix (default: build/musl); also honoured from env
#   TARGET        - musl target triplet (default: i386-linux-musl)
#   MUSL_REPO     - GitHub repo to clone (default: nzmacgeek/musl-blueyos)
#   MUSL_REF      - branch/tag/commit to check out (default: main)
#                   Override with --ref=<sha> for fully reproducible builds.
#
# After this script completes, build the packages with:
#   make MUSL_PREFIX=<PREFIX>
#
# ⚠️  VIBE CODED RESEARCH PROJECT — NOT FOR PRODUCTION USE ⚠️
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PREFIX="${PREFIX:-${REPO_DIR}/build/musl}"
TARGET="${TARGET:-i386-linux-musl}"
MUSL_REPO="${MUSL_REPO:-nzmacgeek/musl-blueyos}"
MUSL_REF="${MUSL_REF:-main}"  # default to 'main'; use --ref=<sha> for reproducibility

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix=*)  PREFIX="${1#*=}";    shift ;;
    --target=*)  TARGET="${1#*=}";    shift ;;
    --repo=*)    MUSL_REPO="${1#*=}"; shift ;;
    --ref=*)     MUSL_REF="${1#*=}";  shift ;;
    --help|-h)
      sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

MUSL_CLONE_URL="https://github.com/${MUSL_REPO}.git"

BUILD_TMP="$(mktemp -d -t blueyos-bash-musl-build.XXXXXX)"
trap 'rm -rf "${BUILD_TMP}"' EXIT

MUSL_SRC_DIR="${BUILD_TMP}/musl-blueyos"

echo "Building musl-blueyos for ${TARGET}"
echo "  source : ${MUSL_CLONE_URL}"
echo "  prefix : ${PREFIX}"
echo "  workdir: ${BUILD_TMP}"
echo ""

echo "Cloning ${MUSL_CLONE_URL} (ref: ${MUSL_REF})..."
git clone --depth=1 --branch "${MUSL_REF}" "${MUSL_CLONE_URL}" "${MUSL_SRC_DIR}"

cd "${MUSL_SRC_DIR}"

# Record the exact commit that was built for traceability.
MUSL_COMMIT="$(git rev-parse HEAD)"
echo "  musl-blueyos commit: ${MUSL_COMMIT}"
echo ""

CC="${CC:-gcc}"

./configure \
  --prefix="${PREFIX}" \
  --target="${TARGET}" \
  CC="${CC}" \
  CFLAGS="-m32 -O2" \
  LDFLAGS="-m32"

if command -v nproc >/dev/null 2>&1; then
  JOBS="$(nproc)"
elif command -v getconf >/dev/null 2>&1; then
  JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
else
  JOBS=1
fi

make -j"${JOBS}"
make install

echo ""
echo "  musl-blueyos installed to: ${PREFIX}"
echo "  commit: ${MUSL_COMMIT}"
echo ""
echo "  Build the packages now with:"
echo "    make MUSL_PREFIX=${PREFIX}"
