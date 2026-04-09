#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REQUESTED_ROOT="${1:-}"
MUSL_PREFIX="${MUSL_PREFIX:-}"
BLUEYOS_SYSROOT="${BLUEYOS_SYSROOT:-/opt/blueyos-sysroot}"

abspath() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "${REPO_DIR}" "$1" ;;
  esac
}

derive_from_musl_prefix() {
  local prefix
  prefix="$1"
  [ -n "${prefix}" ] || return 1
  prefix="$(abspath "${prefix}")"

  case "${prefix}" in
    */usr) printf '%s\n' "${prefix%/usr}" ;;
    *) return 1 ;;
  esac
}

if [ -n "${REQUESTED_ROOT}" ]; then
  abspath "${REQUESTED_ROOT}"
  exit 0
fi

if [ -d "${BLUEYOS_SYSROOT}" ]; then
  abspath "${BLUEYOS_SYSROOT}"
  exit 0
fi

if derive_from_musl_prefix "${MUSL_PREFIX}"; then
  exit 0
fi

exit 1