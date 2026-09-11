#!/usr/bin/env bash
# tests/nc-premise-markdown-backlog.sh — negative control for
# PREMISE-GATE-MARKDOWN-BACKLOG-01 / test-premise-markdown-backlog.sh.
#
# Proves the suite actually detects the two matching bugs it exists to catch,
# not just that its own fixtures happen to be green. Copies the canonical
# reader to a scratch file, applies one surgical mutation at a time to the
# exact line an `# nc-anchor: <name>` comment marks in
# lib/leadv2-markdown-backlog-read.py, then re-runs the full suite against
# the mutant via LEADV2_MARKDOWN_BACKLOG_READER and asserts it goes red on
# the specific case the mutation should break. Never mutates the canonical
# file in place, and refuses loudly (never a silent partial pass) if an
# anchor line has moved or a mutation fails to redden anything.
#
# Run: bash plugins/leadv2/scripts/tests/nc-premise-markdown-backlog.sh
set -uo pipefail
_t_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_t_src" && -f "${0:-}" ]]; then _t_src="$0"; fi
SCRIPT_DIR="$(cd "$(dirname "$_t_src")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

SUITE="${SCRIPT_DIR}/test-premise-markdown-backlog.sh"
CANON_READER="${SCRIPTS_ROOT}/lib/leadv2-markdown-backlog-read.py"

PASS=0; FAIL=0
log()  { printf -- '[NC] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

NC_TMP="$(lv2_mktemp_dir premise-md-backlog-nc)"
trap 'rm -rf "$NC_TMP"' EXIT

[[ -f "${CANON_READER}" ]] || { printf -- 'NC-SETUP-FAIL: canonical reader not found: %s\n' "${CANON_READER}" >&2; exit 1; }

# ── run_mutation <anchor> <sed_expr> <required_fail_substring>... ──────────
# Copies the canonical reader to a fresh scratch file (refusing if that
# scratch path is somehow tracked in git — it must be a disposable copy,
# never the real file), asserts the anchor comment is present verbatim
# exactly once, applies the mutation, runs the full suite against the
# mutant, and asserts the suite (a) exits non-zero and (b) names every
# required case in its FAIL output.
run_mutation() {
  local anchor="$1" sed_expr="$2"; shift 2
  local -a required_fails=("$@")
  local mutant="${NC_TMP}/mutant-${anchor//[^a-zA-Z0-9]/-}.py"

  cp "${CANON_READER}" "${mutant}" || { printf -- 'NC-SETUP-FAIL: could not copy reader to %s\n' "${mutant}" >&2; exit 1; }

  if git -C "${SCRIPTS_ROOT}" ls-files --error-unmatch "${mutant}" >/dev/null 2>&1; then
    printf -- 'NC-SETUP-FAIL: mutation target %s is tracked in git -- refusing to mutate a real file.\n' "${mutant}" >&2
    exit 1
  fi

  local hits
  hits="$(grep -c -- "# nc-anchor: ${anchor}" "${mutant}" 2>/dev/null || true)"
  if [[ "${hits}" != "1" ]]; then
    printf -- 'NC-SETUP-FAIL: expected exactly one line anchored "# nc-anchor: %s" in %s, found %s -- the reader has drifted out from under this negative control. Fix the anchor or this script.\n' "${anchor}" "${CANON_READER}" "${hits}" >&2
    exit 1
  fi

  sed -i.bak -e "${sed_expr}" "${mutant}" || { printf -- 'NC-SETUP-FAIL: sed mutation failed for anchor %s\n' "${anchor}" >&2; exit 1; }
  rm -f "${mutant}.bak"

  if ! python3 -m py_compile "${mutant}" 2>/dev/null; then
    printf -- 'NC-SETUP-FAIL: mutant for anchor %s does not compile -- mutation is malformed.\n' "${anchor}" >&2
    exit 1
  fi

  local out rc
  out="$(LEADV2_MARKDOWN_BACKLOG_READER="${mutant}" bash "${SUITE}" 2>&1)"; rc=$?

  if [[ "${rc}" -eq 0 ]]; then
    fail "${anchor}: mutant suite exited 0 -- suite did not detect the mutation at all"
    return
  fi

  local missing=0 want
  for want in "${required_fails[@]}"; do
    if ! printf '%s\n' "${out}" | grep -q -- "FAIL: ${want}"; then
      printf -- '[NC]   missing expected failure line for %s (anchor %s)\n' "${want}" "${anchor}" >&2
      missing=1
    fi
  done
  if [[ "${missing}" -eq 1 ]]; then
    fail "${anchor}: mutant suite went red (rc=${rc}) but not on the expected case(s): ${required_fails[*]}"
    return
  fi

  pass "${anchor}: mutant suite reddened rc=${rc} on ${required_fails[*]}"
}

# ── Mutation 1: closed_statuses exact-match -> prefix match ───────────────
# Must redden A4/A5 (prefix-trap cases: "в проде, флаг OFF" / "в проде, без
# потребителя" must NOT be treated as closed just because "в проде" is a
# closed status and a prefix of the cell).
run_mutation "closed-exact" \
  's/closed = status_norm in decl\["closed_statuses"\]  # nc-anchor: closed-exact/closed = any(status_norm.startswith(_c) for _c in decl["closed_statuses"])  # nc-anchor: closed-exact/' \
  "A4 id27:" "A5 id30:"

# ── Mutation 2: row-id exact match -> substring match ──────────────────────
# Must redden A6b (task id "1" must not match row id "17" just because "1"
# is a substring of "17").
run_mutation "id-exact" \
  's/if _nfc(cell_id) != task_id_norm:  # nc-anchor: id-exact/if task_id_norm not in _nfc(cell_id):  # nc-anchor: id-exact/' \
  "A6b id1:"

printf -- '\n%s passed, %s failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]] && exit 0 || exit 1
# bash-guard: allow
