#!/usr/bin/env bash

set -euo pipefail

CANGJIECLAW_CJPM_BUILD_LOCK_DIR="${TMPDIR:-/tmp}/metis-cjpm-build.lock"

acquire_metis_cjpm_build_lock() {
  while ! mkdir "${CANGJIECLAW_CJPM_BUILD_LOCK_DIR}" 2>/dev/null; do
    if [ -f "${CANGJIECLAW_CJPM_BUILD_LOCK_DIR}/pid" ]; then
      local lock_pid
      lock_pid="$(cat "${CANGJIECLAW_CJPM_BUILD_LOCK_DIR}/pid" 2>/dev/null || true)"
      if [ -n "${lock_pid}" ] && ! kill -0 "${lock_pid}" 2>/dev/null; then
        rm -rf "${CANGJIECLAW_CJPM_BUILD_LOCK_DIR}" >/dev/null 2>&1 || true
        continue
      fi
    fi
    sleep 1
  done
  printf '%s\n' "$$" > "${CANGJIECLAW_CJPM_BUILD_LOCK_DIR}/pid"
}

release_metis_cjpm_build_lock() {
  rm -rf "${CANGJIECLAW_CJPM_BUILD_LOCK_DIR}" >/dev/null 2>&1 || true
}

with_metis_cjpm_build_lock() {
  acquire_metis_cjpm_build_lock
  "$@"
  local status=$?
  release_metis_cjpm_build_lock
  return "${status}"
}
