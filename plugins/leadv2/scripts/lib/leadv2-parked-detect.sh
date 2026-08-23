#!/usr/bin/env bash
# WORKER-PARKED-ON-BG-01: bounded, best-effort parked-worker wording probe.
# lv2_parked_text_file <path> returns 0 only for the final parked-shaped text.

lv2_parked_text_file() {
  local path="$1" text lines line
  [[ "${LEADV2_PARKED_DETECT:-1}" != "0" ]] || return 1
  [[ -f "${path}" && -r "${path}" ]] || return 1
  text="$(tail -c 4096 "${path}" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
  [[ -n "${text}" ]] || return 1
  lines="$(printf '%s\n' "${text}" | sed '/^[[:space:]]*$/d' | tail -n 3 2>/dev/null || true)"
  [[ -n "${lines}" ]] || return 1
  while IFS= read -r line; do
    case "${line}" in
      *standing\ by*|*waiting\ for*|*waiting\ on*|*will\ report*|*no\ further\ action\ until*|*once\ it\ completes*|*once\ they\ complete*|*until\ it\ finishes*)
        return 0 ;;
    esac
  done <<EOF
${lines}
EOF
  return 1
}
