#!/usr/bin/env bash
# lib/leadv2-control-prover.sh — GATE-PROVES-ITS-OWN-CONTROL-01
#
# Given a catalog of declared "negative controls" (a mutation + the suite that
# is supposed to catch it), APPLY each mutation itself, on the real call path,
# and require the declared suite to go red alone, then require a byte-clean
# revert. The author's claim that a control is diagnostic is never consulted;
# this script decides, mechanically, every time.
#
# Why this exists: every fake-control shape catalogued on this lane (mutation
# kills the wrong layer, half a guarantee decides alone, something else kills
# the mutation first) is invisible to a script that reads the claim in prose.
# The only fix is to run it.
#
# Catalog format: one entry per line, '#'-prefixed and blank lines ignored.
#   id|kind|target|from|to|suite|other_gates
#     id          unique label
#     kind        product|self_test — tallied separately (headline = product only)
#     target      path to the production file to mutate (repo-relative or absolute)
#     from        exact literal substring in target (must occur exactly once)
#     to          replacement literal substring
#     suite       path to the suite that is supposed to go red on this mutation
#     other_gates comma-separated extra suite paths run under the same mutation
#                 (comma-separated, may be empty) — a kill counts only if THIS
#                 suite is the only one that goes red
#
# Usage: leadv2-control-prover.sh --catalog <file> [--root <repo-root>]
# Exit 0 only when every catalog entry is proven diagnostic (killed==scored).
# Exit 1 when at least one entry is not diagnostic (see [BLOCKED] reasons).
# Exit 3 on an internal/irreversible failure (revert did not restore green —
# hard failure, never a warning).
set -uo pipefail

CATALOG=""
ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog) CATALOG="${2:-}"; shift 2 ;;
    --catalog=*) CATALOG="${1#--catalog=}"; shift ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    -h|--help)
      echo "usage: leadv2-control-prover.sh --catalog <file> [--root <repo-root>]" >&2
      exit 0 ;;
    *) echo "control-prover: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "${CATALOG}" || ! -f "${CATALOG}" ]]; then
  echo "control-prover: FATAL missing or unreadable --catalog '${CATALOG}'" >&2
  exit 2
fi

if [[ -z "${ROOT}" ]]; then
  ROOT="$(pwd)"
fi

# ---- byte-identity safety net -------------------------------------------
# Tracks the ONE target currently mid-mutation so any exit path (including an
# unexpected error) restores it. This is the "hard failure, not a warning"
# guarantee — rule 4 of the lane brief.
_cp_active_target=""
_cp_active_backup=""

_cp_restore_active() {
  if [[ -n "${_cp_active_target}" && -n "${_cp_active_backup}" && -f "${_cp_active_backup}" ]]; then
    cp -p "${_cp_active_backup}" "${_cp_active_target}"
    _cp_active_target=""
    _cp_active_backup=""
  fi
}
trap '_cp_restore_active' EXIT

_cp_workdir="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-control-prover.XXXXXX")"
trap '_cp_restore_active; rm -rf "${_cp_workdir}"' EXIT

SCORED=0
KILLED=0
PRODUCT_KILLED=0
SELF_TEST_KILLED=0
HARD_FAIL=0

_resolve() { # path -> absolute path (no realpath dependency, no ../ arithmetic)
  local p="$1"
  case "$p" in
    /*) printf '%s\n' "$p" ;;
    *) printf '%s\n' "${ROOT}/${p}" ;;
  esac
}

_is_fixture_path() { # path
  local p="$1" base
  base="$(basename "${p}")"
  case "${p}" in
    */tests/*|*/fixtures/*) return 0 ;;
  esac
  case "${base}" in
    test-*) return 0 ;;
  esac
  return 1
}

_count_occurrences() { # file needle
  # literal, non-regex count of an exact substring
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import sys
path, needle = sys.argv[1], sys.argv[2]
with open(path, "r") as fh:
    data = fh.read()
print(data.count(needle))
PY
}

_apply_literal() { # file from to
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, frm, to = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r") as fh:
    data = fh.read()
data = data.replace(frm, to, 1)
with open(path, "w") as fh:
    fh.write(data)
PY
}

_run_suite() { # suite -> 0 pass / nonzero fail (exit code is the ONLY signal, never grep text)
  local suite="$1"
  ( bash "${suite}" >/dev/null 2>&1 )
}

while IFS='|' read -r id kind target from to suite other_gates; do
  [[ -z "${id}" ]] && continue
  case "${id}" in \#*) continue ;; esac

  SCORED=$((SCORED + 1))
  target_abs="$(_resolve "${target}")"
  suite_abs="$(_resolve "${suite}")"

  if [[ ! -f "${target_abs}" ]]; then
    printf '[BLOCKED] id=%s reason=target_missing target=%s\n' "${id}" "${target}"
    continue
  fi
  if _is_fixture_path "${target_abs}"; then
    printf '[BLOCKED] id=%s reason=fixture_not_production target=%s\n' "${id}" "${target}"
    continue
  fi
  if [[ ! -f "${suite_abs}" ]]; then
    printf '[BLOCKED] id=%s reason=suite_missing suite=%s\n' "${id}" "${suite}"
    continue
  fi

  occ="$(_count_occurrences "${target_abs}" "${from}")"
  if [[ "${occ}" != "1" ]]; then
    printf '[BLOCKED] id=%s reason=mutation_pattern_invalid occurrences=%s\n' "${id}" "${occ}"
    continue
  fi

  backup="${_cp_workdir}/$(echo "${id}" | tr -c 'A-Za-z0-9._-' '_').orig"
  cp -p "${target_abs}" "${backup}"
  _cp_active_target="${target_abs}"
  _cp_active_backup="${backup}"

  _apply_literal "${target_abs}" "${from}" "${to}"

  if _run_suite "${suite_abs}"; then
    # rule 1: exit 0 with the mutation live — not diagnostic, no matter what
    # the suite printed to stdout/stderr.
    printf '[BLOCKED] id=%s reason=control_not_diagnostic\n' "${id}"
    _cp_restore_active
    continue
  fi

  # rule 2: the kill counts only if THIS suite is the one that went red.
  shared_kill=0
  if [[ -n "${other_gates}" ]]; then
    IFS=',' read -r -a _gates <<< "${other_gates}"
    for g in "${_gates[@]:-}"; do
      [[ -z "${g}" ]] && continue
      g_abs="$(_resolve "${g}")"
      [[ -f "${g_abs}" ]] || continue
      if ! _run_suite "${g_abs}"; then
        shared_kill=1
        break
      fi
    done
  fi
  if [[ "${shared_kill}" -eq 1 ]]; then
    printf '[BLOCKED] id=%s reason=shared_gate_kill\n' "${id}"
    _cp_restore_active
    continue
  fi

  # rule 3: revert must be byte-identical and the suite must return green.
  _cp_restore_active
  if ! cmp -s "${backup}" "${target_abs}"; then
    printf '[HARDFAIL] id=%s reason=revert_not_byte_identical\n' "${id}"
    HARD_FAIL=1
    continue
  fi
  if ! _run_suite "${suite_abs}"; then
    printf '[HARDFAIL] id=%s reason=revert_not_green\n' "${id}"
    HARD_FAIL=1
    continue
  fi

  KILLED=$((KILLED + 1))
  if [[ "${kind}" == "product" ]]; then
    PRODUCT_KILLED=$((PRODUCT_KILLED + 1))
  else
    SELF_TEST_KILLED=$((SELF_TEST_KILLED + 1))
  fi
  printf '[KILLED] id=%s kind=%s\n' "${id}" "${kind}"
done < "${CATALOG}"

invariant="ok"
[[ "${KILLED}" -eq "${SCORED}" ]] || invariant="violated"

printf 'control-prover: scored=%d killed=%d product_killed=%d self_test_killed=%d invariant=%s\n' \
  "${SCORED}" "${KILLED}" "${PRODUCT_KILLED}" "${SELF_TEST_KILLED}" "${invariant}"

if [[ "${HARD_FAIL}" -eq 1 ]]; then
  exit 3
fi
[[ "${invariant}" == "ok" ]]
