#!/usr/bin/env bash
# tools/build-bash.sh — download and cross-compile GNU Bash 5.2 for i386/musl
#
# Usage:
#   ./tools/build-bash.sh [--musl=<musl-sysroot>] [--ncurses=<ncurses-prefix>]
#                         [--readline=<readline-prefix>] [--stage=<payload-dir>]
#                         [--version=<x.y>] [--patches=<N>]
#
# Variables:
#   BASH_VERSION      - bash base version to download (default: 5.2)
#   BASH_PATCH_LEVEL  - number of official GNU patches to apply (default: 21)
#   MUSL_PREFIX       - path to musl-blueyos sysroot
#   NCURSES_PREFIX    - path to ncurses build prefix (default: build/ncurses-install)
#   READLINE_PREFIX   - path to readline build prefix (default: build/readline-install)
#   STAGE_DIR         - payload directory to populate for the dimsim package
#                       (default: bash/payload)
#
# ⚠️  VIBE CODED RESEARCH PROJECT — NOT FOR PRODUCTION USE ⚠️
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BASH_VERSION="${BASH_VERSION:-5.2}"
BASH_PATCH_LEVEL="${BASH_PATCH_LEVEL:-21}"
# SHA256 of the official bash-5.2.tar.gz from https://ftp.gnu.org/gnu/bash/
BASH_SHA256="${BASH_SHA256:-a139c166df7ff4471c5e0733051642ee5556bd7d7dcdcc0e9f80b22d6a7a3c5a}"
MUSL_PREFIX="${MUSL_PREFIX:-${REPO_DIR}/build/musl}"
BUILD_DIR="${BUILD_DIR:-${REPO_DIR}/build}"
NCURSES_PREFIX="${NCURSES_PREFIX:-${BUILD_DIR}/ncurses-install}"
READLINE_PREFIX="${READLINE_PREFIX:-${BUILD_DIR}/readline-install}"
STAGE_DIR="${STAGE_DIR:-${REPO_DIR}/bash/payload}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version=*)  BASH_VERSION="${1#*=}";      shift ;;
    --patches=*)  BASH_PATCH_LEVEL="${1#*=}";  shift ;;
    --musl=*)     MUSL_PREFIX="${1#*=}";       shift ;;
    --ncurses=*)  NCURSES_PREFIX="${1#*=}";    shift ;;
    --readline=*) READLINE_PREFIX="${1#*=}";   shift ;;
    --stage=*)    STAGE_DIR="${1#*=}";         shift ;;
    --help|-h)
      sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

MUSL_INCLUDE="${MUSL_PREFIX}/include"
MUSL_LIB="${MUSL_PREFIX}/lib"
NCURSES_INCLUDE="${NCURSES_PREFIX}/include"
NCURSES_LIB="${NCURSES_PREFIX}/lib"
READLINE_INCLUDE="${READLINE_PREFIX}/include"
READLINE_LIB="${READLINE_PREFIX}/lib"

# Short version tag used in GNU patch filenames: "5.2" → "52"
BASH_SHORT="${BASH_VERSION//./}"

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if [ ! -d "${MUSL_INCLUDE}" ] || [ ! -f "${MUSL_LIB}/libc.a" ]; then
  echo ""
  echo "  [BASH] musl sysroot not found under ${MUSL_PREFIX}"
  echo "         Run: make musl"
  echo ""
  exit 1
fi

if [ ! -f "${READLINE_LIB}/libreadline.a" ]; then
  echo ""
  echo "  [BASH] readline build not found under ${READLINE_PREFIX}"
  echo "         Run: make readline"
  echo ""
  exit 1
fi

if [ ! -f "${NCURSES_LIB}/libncursesw.a" ]; then
  echo ""
  echo "  [BASH] ncurses wide-char build (libncursesw.a) not found under ${NCURSES_PREFIX}"
  echo "         Run: make ncurses"
  echo ""
  exit 1
fi

# ---------------------------------------------------------------------------
# Download base tarball
# ---------------------------------------------------------------------------
TARBALL="bash-${BASH_VERSION}.tar.gz"
TARBALL_URL="https://ftp.gnu.org/gnu/bash/${TARBALL}"
DOWNLOAD_DIR="${BUILD_DIR}/downloads"
SRC_DIR="${BUILD_DIR}/bash-${BASH_VERSION}"

mkdir -p "${DOWNLOAD_DIR}" "${BUILD_DIR}"

if [ ! -f "${DOWNLOAD_DIR}/${TARBALL}" ]; then
  echo "[BASH] Downloading ${TARBALL_URL}..."
  curl -fSL --retry 3 -o "${DOWNLOAD_DIR}/${TARBALL}" "${TARBALL_URL}"
fi

echo "[BASH] Verifying SHA256 for ${TARBALL}..."
echo "${BASH_SHA256}  ${DOWNLOAD_DIR}/${TARBALL}" | sha256sum -c -

if [ ! -d "${SRC_DIR}" ]; then
  echo "[BASH] Extracting ${TARBALL}..."
  tar -C "${BUILD_DIR}" -xzf "${DOWNLOAD_DIR}/${TARBALL}"
fi

# ---------------------------------------------------------------------------
# Apply GNU official patches (bash52-001 … bash52-NNN)
# ---------------------------------------------------------------------------
PATCH_DIR="${DOWNLOAD_DIR}/bash-${BASH_VERSION}-patches"
mkdir -p "${PATCH_DIR}"

if [ "${BASH_PATCH_LEVEL}" -gt 0 ]; then
  echo "[BASH] Applying ${BASH_PATCH_LEVEL} official GNU patches..."
  for i in $(seq 1 "${BASH_PATCH_LEVEL}"); do
    PATCH_NAME="$(printf "bash%s-%03d" "${BASH_SHORT}" "${i}")"
    PATCH_FILE="${PATCH_DIR}/${PATCH_NAME}"
    if [ ! -f "${PATCH_FILE}" ]; then
      PATCH_URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}-patches/${PATCH_NAME}"
      echo "  Fetching patch ${PATCH_NAME}..."
      curl -fSL --retry 3 -o "${PATCH_FILE}" "${PATCH_URL}"
    fi
    # Only apply if not already applied (patch --dry-run detects this)
    if patch --dry-run -d "${SRC_DIR}" -p0 < "${PATCH_FILE}" >/dev/null 2>&1; then
      patch -d "${SRC_DIR}" -p0 < "${PATCH_FILE}"
    fi
  done
fi

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

echo "[BASH] Configuring bash ${BASH_VERSION}.${BASH_PATCH_LEVEL} for i386/musl..."
"${SRC_DIR}/configure" \
  --prefix=/usr \
  --bindir=/bin \
  --host=i386-linux-musl \
  --build="$(uname -m)-linux-gnu" \
  --without-bash-malloc \
  --with-installed-readline="${READLINE_PREFIX}" \
  --enable-readline \
  --enable-history \
  --enable-job-control \
  --enable-array-variables \
  --enable-alias \
  --enable-process-substitution \
  --enable-prompt-string-decoding \
  --without-included-gettext \
  --disable-nls \
  CC="${CC}" \
  CFLAGS="-m32 -O2 -fno-stack-protector \
    -isystem ${MUSL_INCLUDE} \
    -I${READLINE_INCLUDE} \
    -I${NCURSES_INCLUDE}" \
  LDFLAGS="-m32 -static \
    -L${MUSL_LIB} \
    -L${READLINE_LIB} \
    -L${NCURSES_LIB}" \
  LIBS="-lreadline -lncursesw"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if command -v nproc >/dev/null 2>&1; then
  JOBS="$(nproc)"
else
  JOBS=1
fi

echo "[BASH] Building..."
make -j"${JOBS}"

# ---------------------------------------------------------------------------
# Stage payload for the dimsim package
# The final binary goes to /bin/bash on the target system.
# ---------------------------------------------------------------------------
echo "[BASH] Staging payload into ${STAGE_DIR}..."
mkdir -p "${STAGE_DIR}/bin"
mkdir -p "${STAGE_DIR}/usr/share/man/man1"
mkdir -p "${STAGE_DIR}/usr/share/doc/bash"

install -m 0755 bash "${STAGE_DIR}/bin/bash"

# Stage /bin/sh -> bash so the package's "provides": ["sh"] is accurate.
ln -sfn bash "${STAGE_DIR}/bin/sh"

# man page (if built)
if [ -f doc/bash.1 ]; then
  gzip -9 -c doc/bash.1 > "${STAGE_DIR}/usr/share/man/man1/bash.1.gz"
fi

# bundled documentation (nullglob so unmatched patterns expand to nothing)
(
  shopt -s nullglob
  for f in "${SRC_DIR}/doc/"*.pdf "${SRC_DIR}/doc/"*.html; do
    cp "${f}" "${STAGE_DIR}/usr/share/doc/bash/"
  done
)

echo ""
echo "  [BASH] Done."
echo "         Binary   : ${STAGE_DIR}/bin/bash"
echo "         Payload  : ${STAGE_DIR}"
