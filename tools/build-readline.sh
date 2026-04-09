#!/usr/bin/env bash
# tools/build-readline.sh — download and cross-compile GNU Readline 8.2 for i386/musl
#
# Usage:
#   ./tools/build-readline.sh [--prefix=<install-prefix>] [--musl=<musl-sysroot>]
#                             [--ncurses=<ncurses-prefix>] [--stage=<payload-dir>]
#                             [--version=<x.y>]
#
# Variables:
#   READLINE_VERSION  - readline version to build (default: 8.2)
#   MUSL_PREFIX       - path to musl-blueyos sysroot
#   NCURSES_PREFIX    - path to ncurses build prefix (default: build/ncurses-install)
#   INSTALL_PREFIX    - where readline headers/libs are installed for dependents
#                       (default: build/readline-install)
#   STAGE_DIR         - payload directory to populate for the dimsim package
#                       (default: readline/payload)
#
# ⚠️  VIBE CODED RESEARCH PROJECT — NOT FOR PRODUCTION USE ⚠️
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

READLINE_VERSION="${READLINE_VERSION:-8.2}"
# SHA256 of the official readline-8.2.tar.gz from https://ftp.gnu.org/gnu/readline/
READLINE_SHA256="${READLINE_SHA256:-3feb7171f16a84ee82ca18a36d7b9be109a52c04f492a053331d7d1095007c35}"
MUSL_PREFIX="${MUSL_PREFIX:-${REPO_DIR}/build/musl}"
BUILD_DIR="${BUILD_DIR:-${REPO_DIR}/build}"
NCURSES_PREFIX="${NCURSES_PREFIX:-${BUILD_DIR}/ncurses-install}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${BUILD_DIR}/readline-install}"
STAGE_DIR="${STAGE_DIR:-${REPO_DIR}/readline/payload}"

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
    echo "[READLINE] configure missing; regenerating with autoreconf..."
    (cd "${src_dir}" && autoreconf -fi)
  fi

  if [ ! -x "${configure_path}" ]; then
    echo "[READLINE] Missing ${configure_path}" >&2
    echo "           Remove ${src_dir} and retry. If this is a checkout, install autotools first." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version=*)  READLINE_VERSION="${1#*=}"; shift ;;
    --musl=*)     MUSL_PREFIX="${1#*=}";      shift ;;
    --ncurses=*)  NCURSES_PREFIX="${1#*=}";   shift ;;
    --prefix=*)   INSTALL_PREFIX="${1#*=}";   shift ;;
    --stage=*)    STAGE_DIR="${1#*=}";        shift ;;
    --help|-h)
      sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

BUILD_DIR="$(abspath "${BUILD_DIR}")"
NCURSES_PREFIX="$(abspath "${NCURSES_PREFIX}")"
INSTALL_PREFIX="$(abspath "${INSTALL_PREFIX}")"
STAGE_DIR="$(abspath "${STAGE_DIR}")"
MUSL_PREFIX="$(BLUEYOS_SYSROOT="${BLUEYOS_SYSROOT:-/opt/blueyos-sysroot}" BUILD_DIR="${BUILD_DIR}" bash "${SCRIPT_DIR}/resolve-musl-prefix.sh" "${MUSL_PREFIX}")"

MUSL_INCLUDE="${MUSL_PREFIX}/include"
MUSL_LIB="${MUSL_PREFIX}/lib"
NCURSES_INCLUDE="${NCURSES_PREFIX}/include"
NCURSES_LIB="${NCURSES_PREFIX}/lib"

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if [ ! -d "${MUSL_INCLUDE}" ] || [ ! -f "${MUSL_LIB}/libc.a" ]; then
  echo ""
  echo "  [READLINE] musl sysroot not found under ${MUSL_PREFIX}"
  echo "             Run: make musl"
  echo ""
  exit 1
fi

if [ ! -f "${NCURSES_LIB}/libncursesw.a" ]; then
  echo ""
  echo "  [READLINE] ncurses wide-char build (libncursesw.a) not found under ${NCURSES_PREFIX}"
  echo "             Run: make ncurses"
  echo ""
  exit 1
fi

# ---------------------------------------------------------------------------
# Download source
# ---------------------------------------------------------------------------
TARBALL="readline-${READLINE_VERSION}.tar.gz"
TARBALL_URL="https://ftp.gnu.org/gnu/readline/${TARBALL}"
DOWNLOAD_DIR="${BUILD_DIR}/downloads"
SRC_DIR="${BUILD_DIR}/readline-${READLINE_VERSION}"

mkdir -p "${DOWNLOAD_DIR}" "${BUILD_DIR}"

if [ ! -f "${DOWNLOAD_DIR}/${TARBALL}" ]; then
  echo "[READLINE] Downloading ${TARBALL_URL}..."
  curl -fSL --retry 3 -o "${DOWNLOAD_DIR}/${TARBALL}" "${TARBALL_URL}"
fi

echo "[READLINE] Verifying SHA256 for ${TARBALL}..."
echo "${READLINE_SHA256}  ${DOWNLOAD_DIR}/${TARBALL}" | sha256sum -c -

if [ ! -d "${SRC_DIR}" ]; then
  echo "[READLINE] Extracting ${TARBALL}..."
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

echo "[READLINE] Configuring readline ${READLINE_VERSION} for i386/musl..."
"${SRC_DIR}/configure" \
  --prefix="${INSTALL_PREFIX}" \
  --host=i386-linux-musl \
  --build="$(uname -m)-linux-gnu" \
  --with-curses \
  --disable-install-examples \
  CC="${CC}" \
  CFLAGS="-m32 -O2 -fno-stack-protector -isystem ${MUSL_INCLUDE} -I${NCURSES_INCLUDE}" \
  LDFLAGS="-m32 -static -L${MUSL_LIB} -L${NCURSES_LIB}${EXTRA_LDFLAGS}" \
  LIBS="-lncursesw"

# ---------------------------------------------------------------------------
# Build and install to the build prefix
# ---------------------------------------------------------------------------
if command -v nproc >/dev/null 2>&1; then
  JOBS="$(nproc)"
else
  JOBS=1
fi

echo "[READLINE] Building..."
make -j"${JOBS}"
make install

# ---------------------------------------------------------------------------
# Stage payload for the dimsim package
# ---------------------------------------------------------------------------
echo "[READLINE] Staging payload into ${STAGE_DIR}..."
STAGING_PREFIX="${STAGE_DIR}/usr"
mkdir -p "${STAGING_PREFIX}"

make install prefix="${STAGING_PREFIX}"

echo ""
echo "  [READLINE] Done. Build prefix : ${INSTALL_PREFIX}"
echo "              Payload staged at  : ${STAGE_DIR}"
