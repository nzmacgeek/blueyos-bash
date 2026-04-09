#!/usr/bin/env bash
# tools/build-ncurses.sh — download and cross-compile ncurses 6.5 for i386/musl
#
# Usage:
#   ./tools/build-ncurses.sh [--prefix=<install-prefix>] [--musl=<musl-sysroot>]
#                            [--stage=<payload-dir>]   [--version=<x.y>]
#
# Variables:
#   NCURSES_VERSION - ncurses version to build (default: 6.5)
#   MUSL_PREFIX     - path to musl-blueyos sysroot
#   INSTALL_PREFIX  - where ncurses headers/libs are installed for dependents
#                     (default: build/ncurses-install)
#   STAGE_DIR       - payload directory to populate for the dimsim package
#                     (default: ncurses/payload)
#
# ⚠️  VIBE CODED RESEARCH PROJECT — NOT FOR PRODUCTION USE ⚠️
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

NCURSES_VERSION="${NCURSES_VERSION:-6.5}"
# SHA256 of the official ncurses-6.5.tar.gz from https://ftp.gnu.org/gnu/ncurses/
NCURSES_SHA256="${NCURSES_SHA256:-136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6}"
MUSL_PREFIX="${MUSL_PREFIX:-${REPO_DIR}/build/musl}"
BUILD_DIR="${BUILD_DIR:-${REPO_DIR}/build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${BUILD_DIR}/ncurses-install}"
STAGE_DIR="${STAGE_DIR:-${REPO_DIR}/ncurses/payload}"

abspath() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "${REPO_DIR}" "$1" ;;
  esac
}

ensure_configure_script() {
  local src_dir configure_path
  src_dir="$1"
  configure_path="${src_dir}/configure"

  if [ -x "${configure_path}" ]; then
    return 0
  fi

  if command -v autoreconf >/dev/null 2>&1 && \
     { [ -f "${src_dir}/configure.ac" ] || [ -f "${src_dir}/configure.in" ]; }; then
    echo "[NCURSES] configure missing; regenerating with autoreconf..."
    (cd "${src_dir}" && autoreconf -fi)
  fi

  if [ ! -x "${configure_path}" ]; then
    echo "[NCURSES] Missing ${configure_path}" >&2
    echo "          Remove ${src_dir} and retry. If this is a checkout, install autotools first." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version=*)  NCURSES_VERSION="${1#*=}"; shift ;;
    --musl=*)     MUSL_PREFIX="${1#*=}";     shift ;;
    --prefix=*)   INSTALL_PREFIX="${1#*=}";  shift ;;
    --stage=*)    STAGE_DIR="${1#*=}";       shift ;;
    --help|-h)
      sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

BUILD_DIR="$(abspath "${BUILD_DIR}")"
INSTALL_PREFIX="$(abspath "${INSTALL_PREFIX}")"
STAGE_DIR="$(abspath "${STAGE_DIR}")"
MUSL_PREFIX="$(BLUEYOS_SYSROOT="${BLUEYOS_SYSROOT:-/opt/blueyos-sysroot}" BUILD_DIR="${BUILD_DIR}" bash "${SCRIPT_DIR}/resolve-musl-prefix.sh" "${MUSL_PREFIX}")"

MUSL_INCLUDE="${MUSL_PREFIX}/include"
MUSL_LIB="${MUSL_PREFIX}/lib"

# ---------------------------------------------------------------------------
# Validate musl sysroot
# ---------------------------------------------------------------------------
if [ ! -d "${MUSL_INCLUDE}" ] || [ ! -f "${MUSL_LIB}/libc.a" ]; then
  echo ""
  echo "  [NCURSES] musl sysroot not found under ${MUSL_PREFIX}"
  echo "            Run: make musl   or   ./tools/build-musl.sh --prefix=${MUSL_PREFIX}"
  echo ""
  exit 1
fi

# ---------------------------------------------------------------------------
# Download source
# ---------------------------------------------------------------------------
TARBALL="ncurses-${NCURSES_VERSION}.tar.gz"
TARBALL_URL="https://ftp.gnu.org/gnu/ncurses/${TARBALL}"
DOWNLOAD_DIR="${BUILD_DIR}/downloads"
SRC_DIR="${BUILD_DIR}/ncurses-${NCURSES_VERSION}"

mkdir -p "${DOWNLOAD_DIR}" "${BUILD_DIR}"

if [ ! -f "${DOWNLOAD_DIR}/${TARBALL}" ]; then
  echo "[NCURSES] Downloading ${TARBALL_URL}..."
  curl -fSL --retry 3 -o "${DOWNLOAD_DIR}/${TARBALL}" "${TARBALL_URL}"
fi

echo "[NCURSES] Verifying SHA256 for ${TARBALL}..."
echo "${NCURSES_SHA256}  ${DOWNLOAD_DIR}/${TARBALL}" | sha256sum -c -

if [ ! -d "${SRC_DIR}" ]; then
  echo "[NCURSES] Extracting ${TARBALL}..."
  tar -C "${BUILD_DIR}" -xzf "${DOWNLOAD_DIR}/${TARBALL}"
fi

ensure_configure_script "${SRC_DIR}"

# ---------------------------------------------------------------------------
# Configure
# ---------------------------------------------------------------------------
BUILD_SUBDIR="${SRC_DIR}/build-blueyos"
mkdir -p "${BUILD_SUBDIR}"
cd "${BUILD_SUBDIR}"

# Prefer the musl-gcc wrapper installed by `make musl`; fall back to plain gcc.
# CC may be set explicitly by the caller (e.g. from the Makefile) — respect that.
MUSL_GCC="${MUSL_PREFIX}/bin/musl-gcc"
if [ -z "${CC:-}" ]; then
  if [ -x "${MUSL_GCC}" ]; then
    CC="${MUSL_GCC}"
  else
    CC="gcc"
  fi
fi

if [ "${CC##*/}" = "musl-gcc" ] && [ -z "${REALGCC:-}" ]; then
  REALGCC="gcc"
  export REALGCC
fi

EXTRA_LDFLAGS=""
if [ "${CC##*/}" = "musl-gcc" ]; then
  EXTRA_LDFLAGS=" -Wl,-m,elf_i386"
fi

echo "[NCURSES] Configuring ncurses ${NCURSES_VERSION} for i386/musl..."
"${SRC_DIR}/configure" \
  --prefix="${INSTALL_PREFIX}" \
  --host=i386-linux-musl \
  --build="$(uname -m)-linux-gnu" \
  --without-ada \
  --without-tests \
  --without-manpages \
  --without-cxx \
  --without-cxx-binding \
  --disable-pc-files \
  --disable-mixed-case \
  --enable-widec \
  --with-default-terminfo-dir=/usr/share/terminfo \
  CC="${CC}" \
  CFLAGS="-m32 -O2 -fno-stack-protector -isystem ${MUSL_INCLUDE}" \
  LDFLAGS="-m32 -static -L${MUSL_LIB}${EXTRA_LDFLAGS}"

# ---------------------------------------------------------------------------
# Build and install to the build prefix (for readline/bash to link against)
# ---------------------------------------------------------------------------
if command -v nproc >/dev/null 2>&1; then
  JOBS="$(nproc)"
else
  JOBS=1
fi

echo "[NCURSES] Building..."
make -j"${JOBS}"
make install ticdir="${INSTALL_PREFIX}/share/terminfo" ticlibdir="${INSTALL_PREFIX}/share/terminfo"

# ---------------------------------------------------------------------------
# Stage payload for the dimsim package
# Installs into STAGE_DIR mirroring the target root (/).
# ---------------------------------------------------------------------------
echo "[NCURSES] Staging payload into ${STAGE_DIR}..."
STAGING_PREFIX="${STAGE_DIR}/usr"
mkdir -p "${STAGING_PREFIX}"

make install prefix="${STAGING_PREFIX}" ticdir="${STAGING_PREFIX}/share/terminfo" ticlibdir="${STAGING_PREFIX}/share/terminfo"

# Provide conventional symlinks: libncurses → libncursesw (wide-char is default)
if compgen -G "${STAGING_PREFIX}/lib/libncursesw*" > /dev/null 2>&1; then
  for f in "${STAGING_PREFIX}/lib"/libncursesw*; do
    base="${f##*/}"
    compat="${base/ncursesw/ncurses}"
    target="${STAGING_PREFIX}/lib/${compat}"
    [ -e "${target}" ] || ln -sfn "${base}" "${target}"
  done
fi

# Provide curses.h → ncurses/curses.h compatibility header
if [ ! -f "${STAGING_PREFIX}/include/curses.h" ] && \
   [ -f "${STAGING_PREFIX}/include/ncursesw/curses.h" ]; then
  ln -sfn ncursesw/curses.h "${STAGING_PREFIX}/include/curses.h"
  ln -sfn ncursesw/ncurses.h "${STAGING_PREFIX}/include/ncurses.h"
fi

echo ""
echo "  [NCURSES] Done. Build prefix : ${INSTALL_PREFIX}"
echo "             Payload staged at  : ${STAGE_DIR}"
