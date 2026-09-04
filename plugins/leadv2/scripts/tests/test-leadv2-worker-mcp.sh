#!/usr/bin/env bash
# tests/test-leadv2-worker-mcp.sh — CODE-INTEL-SKIPPED-FIFTEEN-TIMES-01.
#
# The 2026-09-04 measurement: 15/15 sonnet dispatches journaled
# `code_intel_preamble arm=sonnet mode=skipped reason=fail_open` (78
# historically, zero with any cause) while glm/glm-flash attached 3/3.
# Root cause was structural: worker_mcp_preamble_for_arm()'s sonnet branch
# mirrors claude-subsession.sh's opt-in LEADV2_SUBSESSION_SLIM_MCP (default
# 0) while every other arm mirrors LEADV2_WORKER_MCP (default 1), and nothing
# ever defaulted the sonnet gate for dispatched workers.
#
# This suite locks the two requirements of the fix:
#
#   R1 (loud fail-open): every rc!=0 branch of worker_mcp_preamble_for_arm()
#       prints exactly one machine-readable
#       `[worker-mcp] preamble_skip_cause=<token>` line to stderr, and the
#       dispatcher folds it into the journal line as `cause=<token>` — a skip
#       with no cause is itself surfaced as cause=no_cause_reported.
#   R2 (sonnet default attach): _spawn_worker_body defaults the sonnet arm's
#       SLIM_MCP gate to 1 (prediction AND spawn line), so a dispatched
#       sonnet worker gets the code-intel preamble + role-scoped MCP exactly
#       like glm; explicit LEADV2_SUBSESSION_SLIM_MCP=0 still wins (old
#       behaviour restored, loudly).
#
# Coverage is behavioural at two levels, house-style of
# test-worker-mcp-all-arms.sh: the lib is sourced and called directly; the
# dispatcher is driven through LEADV2_DISPATCH_SOURCE_ONLY=1 into
# _spawn_worker_body with a stubbed claude-subsession launcher and a stubbed
# journal bin, asserting the EXACT journal line, the spawn env, and the
# mission text the child would receive. NEGATIVE CONTROLS mutate function
# BODIES (lib + dispatcher scratch copies) and prove each mutation turns the
# matching check RED, reporting baseline_rc/mutated_rc pairs.
#
# Run: bash plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd "${PLUGIN_SCRIPTS}/.." && pwd)"
DISPATCH_SCRIPT="${PLUGIN_SCRIPTS}/leadv2-dispatch-code.sh"
WORKER_MCP_LIB="${PLUGIN_SCRIPTS}/lib/leadv2-worker-mcp.sh"
PREAMBLE_FILE="${PLUGIN_ROOT}/prompts/worker-code-intel-preamble.md"

PASS=0
FAIL=0
ERRORS=()

log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

CLEANUP_PATHS=()
SLEEP_PID_FILES=()
_cleanup() {
  local p f pid
  for f in "${SLEEP_PID_FILES[@]+"${SLEEP_PID_FILES[@]}"}"; do
    while IFS= read -r pid; do kill "${pid}" 2>/dev/null || true; done < "${f}" 2>/dev/null
  done
  for p in "${CLEANUP_PATHS[@]+"${CLEANUP_PATHS[@]}"}"; do
    rm -rf "${p}" 2>/dev/null || true
  done
}
trap _cleanup EXIT INT TERM

# ── bash 3.2 syntax floor on every shell file this lane touches ─────────────
for f in "scripts/leadv2-dispatch-code.sh" "scripts/lib/leadv2-worker-mcp.sh" \
         "scripts/tests/test-leadv2-worker-mcp.sh"; do
  if bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null && /bin/bash -n "${PLUGIN_ROOT}/${f}" 2>/dev/null; then
    PASS=$((PASS + 1)); log "PASS: bash -n ${f} (incl. 3.2)"
  else
    FAIL=$((FAIL + 1)); ERRORS+=("bash -n ${f}"); log "FAIL: bash -n ${f}"
  fi
done

# ── fixtures ────────────────────────────────────────────────────────────────
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/ci-skip.XXXXXX")"
CLEANUP_PATHS+=("${FIXTURE}")
STUB_BIN="${FIXTURE}/bin"; mkdir -p "${STUB_BIN}"

make_mcp_repo() { # <name> — git repo whose .mcp.json defines both servers
  local r="${FIXTURE}/$1"
  mkdir -p "${r}"
  printf '%s\n' '{"mcpServers": {"repowise": {"command": "stub-repowise", "args": []}, "codebase-memory-mcp": {"command": "stub-cbm", "args": []}}}' > "${r}/.mcp.json"
  git -C "${r}" init -q 2>/dev/null || true
  git -C "${r}" -c user.email=ci@test -c user.name=ci commit -q --allow-empty -m init 2>/dev/null || true
  printf '%s' "${r}"
}
MCP_REPO="$(make_mcp_repo mcp-repo)"
# A repo+HOME pair where NOTHING resolves: no .mcp.json, no settings — the
# resolve branch must fail rc=12 (servers unresolved), never silently.
NO_MCP_REPO="${FIXTURE}/no-mcp-repo"; mkdir -p "${NO_MCP_REPO}"
NO_MCP_HOME="${FIXTURE}/no-mcp-home"; mkdir -p "${NO_MCP_HOME}"

# ── L: lib-level causes — worker_mcp_preamble_for_arm() ─────────────────────
# cause_case <label> <want-rc> <want-cause-prefix> <lib> <arm> <root> <home|-> [env...]
# Asserts: rc as wanted, stdout EMPTY (the R4 silence contract on stdout is
# intact — the cause lives on stderr only), and stderr carrying the expected
# preamble_skip_cause token prefix. Returns non-zero when any leg fails.
cause_case() {
  local label="$1" want_rc="$2" want_cause="$3" lib="$4" arm="$5" root="$6" home="$7"
  shift 7
  local errf res rc out cause
  errf="${FIXTURE}/cause-stderr.txt"; : > "${errf}"
  if [[ "${home}" == "-" ]]; then
    res="$(env "$@" bash -c '
        source "$1"; shift
        out="$(worker_mcp_preamble_for_arm "$@")"; rc=$?
        printf "rc=%s\n--OUT--\n%s" "$rc" "$out"
      ' _ "${lib}" "${arm}" "${root}" 2>"${errf}")"
  else
    res="$(env HOME="${home}" "$@" bash -c '
        source "$1"; shift
        out="$(worker_mcp_preamble_for_arm "$@")"; rc=$?
        printf "rc=%s\n--OUT--\n%s" "$rc" "$out"
      ' _ "${lib}" "${arm}" "${root}" 2>"${errf}")"
  fi
  rc="${res%%$'\n'*}"; rc="${rc#rc=}"
  # $() strips the trailing newline, so strip the marker first, then any
  # leading newline — matching "*--OUT--\n" directly would never hit.
  out="${res#*--OUT--}"; out="${out#[$'\n']}"
  cause="$(sed -n 's/^.*preamble_skip_cause=\([^[:space:]]*\).*$/\1/p' "${errf}" | head -1)"
  if [[ "${rc}" == "${want_rc}" && "${cause}" == "${want_cause}"* ]] \
     && { [[ "${want_rc}" == "0" ]] || [[ -z "${out//[$'\n']/}" ]]; }; then
    if [[ "${CAUSE_CASE_SILENT:-0}" != "1" ]]; then
      pass "lib cause: ${label} -> rc=${rc} cause=${cause:-<none>}"
    fi
    return 0
  fi
  # CAUSE_CASE_SILENT=1 = mutation-probe mode: the caller EXPECTS this
  # branch to fail on a mutant and reads only the return code — a counted
  # fail() here would make the whole suite red on a caught mutation.
  if [[ "${CAUSE_CASE_SILENT:-0}" == "1" ]]; then
    return 1
  fi
  fail "lib cause: ${label} -> rc=${rc} (want ${want_rc}) cause=${cause:-<none>} (want prefix '${want_cause}') out='$(printf '%s' "${out}" | head -1)'"
  return 1
}

L_LIB="${WORKER_MCP_LIB}"
cause_case "sonnet default gate off names the gate"   3 "gate:LEADV2_SUBSESSION_SLIM_MCP=unset" "${L_LIB}" sonnet "${MCP_REPO}" - >/dev/null
cause_case "sonnet explicit 0 names gate and value"   3 "gate:LEADV2_SUBSESSION_SLIM_MCP=0"    "${L_LIB}" sonnet "${MCP_REPO}" - LEADV2_SUBSESSION_SLIM_MCP=0 >/dev/null
cause_case "kimi gate off names LEADV2_WORKER_MCP"    3 "gate:LEADV2_WORKER_MCP=0"             "${L_LIB}" kimi    "${MCP_REPO}" - LEADV2_WORKER_MCP=0 >/dev/null
cause_case "resolve failure names call and rc"        3 "resolve_role_mcp_config_rc=12"        "${L_LIB}" kimi    "${NO_MCP_REPO}" "${NO_MCP_HOME}" >/dev/null
cause_case "codex unwired names its cause"            4 "codex_no_mcp_wiring"                  "${L_LIB}" codex   "${MCP_REPO}" - >/dev/null

# attached row, expressed directly (stdout MUST be the preamble, stderr silent):
_ci_att="$(env LEADV2_SUBSESSION_SLIM_MCP=1 bash -c '
    source "$1"; worker_mcp_preamble_for_arm sonnet "$2" ""
  ' _ "${L_LIB}" "${MCP_REPO}" 2>"${FIXTURE}/att-err.txt")"
if [[ -n "${_ci_att}" ]] && grep -q "CODE-INTEL ROUTING" <<<"${_ci_att}" \
   && ! grep -q "preamble_skip_cause" "${FIXTURE}/att-err.txt"; then
  pass "lib attach: sonnet SLIM=1 -> preamble text, no cause line on stderr"
else
  fail "lib attach: sonnet SLIM=1 -> preamble text, no cause line on stderr (out='$(head -1 <<<"${_ci_att}")' err='$(head -1 "${FIXTURE}/att-err.txt")')"
fi

# preamble-file-missing row: full plugin-root scratch copy without prompts/
PF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ci-skip-pf.XXXXXX")"; CLEANUP_PATHS+=("${PF_DIR}")
cp -pR "${PLUGIN_ROOT}/" "${PF_DIR}/plugin/" 2>/dev/null || cp -pR "${PLUGIN_ROOT}" "${PF_DIR}/plugin"
rm -f "${PF_DIR}/plugin/prompts/worker-code-intel-preamble.md"
_pf_probe="$(env -u CLAUDE_PLUGIN_ROOT LEADV2_SUBSESSION_SLIM_MCP=1 bash -c '
    source "$1"; worker_mcp_preamble_for_arm sonnet "$2" ""
  ' _ "${PF_DIR}/plugin/scripts/lib/leadv2-worker-mcp.sh" "${MCP_REPO}" 2>&1)"
if grep -q "preamble_skip_cause=preamble_file_missing:" <<<"${_pf_probe}"; then
  pass "lib cause: preamble_file_missing fires from the scratch plugin copy"
else
  fail "lib cause: preamble_file_missing fires from the scratch plugin copy (got: ${_pf_probe})"
fi

# ── D: dispatcher-level — _spawn_worker_body with stubbed launcher ─────────
# journal stub: emit() calls  bash $JOURNAL_BIN append <task> <jtype> <line>
JOURNAL_STUB="${STUB_BIN}/journal-stub"
SUBSESSION_STUB="${STUB_BIN}/subsession-stub"

run_spawn_sonnet() { # <dispatch_script> <repo> <tag> [env k=v...] -> rc of _spawn_worker_body
  local dsh="$1" repo="$2" tag="$3"; shift 3
  local dir="${FIXTURE}/${tag}"
  mkdir -p "${dir}"
  : > "${dir}/journal.txt"; : > "${dir}/spawn-env.txt"; : > "${dir}/mission.txt"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${4:-}" >> "%s/journal.txt"\n' "${dir}" > "${JOURNAL_STUB}"
  cat > "${SUBSESSION_STUB}" <<STUBEOF
#!/usr/bin/env bash
printf 'SLIM_MCP=%s\n' "\${LEADV2_SUBSESSION_SLIM_MCP:-<unset>}" >> "${dir}/spawn-env.txt"
_prev=""
for _a in "\$@"; do
  if [[ "\$_prev" == "--mission-file" && -f "\$_a" ]]; then
    cp "\$_a" "${dir}/mission.txt" 2>/dev/null || true
  fi
  _prev="\$_a"
done
# The background sleep must NOT inherit this stub's stdout: the dispatcher
# captures the launcher's output in a command substitution, and a background
# child holding the pipe's write end blocks the EOF for its whole lifetime
# (observed: every dispatcher-level case hung 300s on exactly this).
sleep 300 >/dev/null 2>&1 </dev/null &
printf '%s\n' "\$!" >> "${dir}/sleep-pids"
printf 'PID=%s LABEL=citest SESSION_ID=citest\n' "\$!"
exit 0
STUBEOF
  chmod +x "${JOURNAL_STUB}" "${SUBSESSION_STUB}"
  SLEEP_PID_FILES+=("${dir}/sleep-pids")
  ( cd "${repo}" && \
    CIT_DIR="${dir}" \
    LEADV2_DISPATCH_SOURCE_ONLY=1 PROJECT_ROOT="${repo}" CLAUDE_PROJECT_ROOT="${repo}" \
    LEADV2_LANE_WORK_ROOT="${repo}" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${SUBSESSION_STUB}" \
    LEADV2_JOURNAL_BIN="${JOURNAL_STUB}" JOURNAL_TASK="citask" \
    env "$@" bash -c '
        set -uo pipefail
        source "$1"
        _spawn_worker_body sonnet "CI-MISSION-MARKER" "cisuite8" "'"${dir}"'/launcher-err.txt"
      ' _ "${dsh}" >"${dir}/run-stdout.txt" 2>"${dir}/run-stderr.txt" )
  return $?
}

# D1 probe: default env — sonnet attaches (R2). Returns 0 iff every leg holds.
d1_default_attach() { # <dispatch_script> <repo>
  local dsh="$1" repo="$2" rc=0
  run_spawn_sonnet "${dsh}" "${repo}" d1 || rc=1
  grep -q 'code_intel_preamble arm=sonnet task=cisuite8 mode=attached$' "${FIXTURE}/d1/journal.txt" 2>/dev/null || rc=1
  [[ "$(tail -1 "${FIXTURE}/d1/spawn-env.txt" 2>/dev/null)" == "SLIM_MCP=1" ]] || rc=1
  grep -q "CODE-INTEL ROUTING" "${FIXTURE}/d1/mission.txt" 2>/dev/null || rc=1
  grep -q "CI-MISSION-MARKER" "${FIXTURE}/d1/mission.txt" 2>/dev/null || rc=1
  return ${rc}
}
if d1_default_attach "${DISPATCH_SCRIPT}" "${MCP_REPO}"; then
  pass "D1 dispatcher: sonnet DEFAULT attaches — journal mode=attached, spawn SLIM_MCP=1, mission carries preamble"
else
  fail "D1 dispatcher: sonnet DEFAULT attaches (journal: $(grep code_intel_preamble "${FIXTURE}/d1/journal.txt" 2>/dev/null | head -1); spawn-env: $(tail -1 "${FIXTURE}/d1/spawn-env.txt" 2>/dev/null); mission has preamble: $(grep -c 'CODE-INTEL ROUTING' "${FIXTURE}/d1/mission.txt" 2>/dev/null))"
fi

# D2 probe: explicit SLIM_MCP=0 — old spawn restored, LOUDLY (R1+R2).
d2_loud_skip() { # <dispatch_script> <repo>
  local dsh="$1" repo="$2" rc=0
  run_spawn_sonnet "${dsh}" "${repo}" d2 LEADV2_SUBSESSION_SLIM_MCP=0 || rc=1
  grep -q 'code_intel_preamble arm=sonnet task=cisuite8 mode=skipped reason=fail_open cause=gate:LEADV2_SUBSESSION_SLIM_MCP=0$' "${FIXTURE}/d2/journal.txt" 2>/dev/null || rc=1
  [[ "$(tail -1 "${FIXTURE}/d2/spawn-env.txt" 2>/dev/null)" == "SLIM_MCP=0" ]] || rc=1
  grep -q "CODE-INTEL ROUTING" "${FIXTURE}/d2/mission.txt" 2>/dev/null && rc=1
  grep -q "CI-MISSION-MARKER" "${FIXTURE}/d2/mission.txt" 2>/dev/null || rc=1
  return ${rc}
}
if d2_loud_skip "${DISPATCH_SCRIPT}" "${MCP_REPO}"; then
  pass "D2 dispatcher: SLIM_MCP=0 skip is loud — journal carries cause=gate:LEADV2_SUBSESSION_SLIM_MCP=0, spawn env 0, mission without preamble"
else
  fail "D2 dispatcher: SLIM_MCP=0 skip is loud (journal: $(grep code_intel_preamble "${FIXTURE}/d2/journal.txt" 2>/dev/null | head -1))"
fi

# D3 probe: preamble assembly FAILS (nothing resolvable) — the journal must
# name the failing call and its rc, not a bare fail_open.
d3_resolve_failure_loud() { # <dispatch_script> <repo> <home>
  local dsh="$1" repo="$2" home="$3" rc=0
  run_spawn_sonnet "${dsh}" "${repo}" d3 HOME="${home}" || rc=1
  grep -q 'code_intel_preamble arm=sonnet task=cisuite8 mode=skipped reason=fail_open cause=resolve_role_mcp_config_rc=12$' "${FIXTURE}/d3/journal.txt" 2>/dev/null || rc=1
  return ${rc}
}
if d3_resolve_failure_loud "${DISPATCH_SCRIPT}" "${NO_MCP_REPO}" "${NO_MCP_HOME}"; then
  pass "D3 dispatcher: resolve failure is loud — journal cause=resolve_role_mcp_config_rc=12"
else
  fail "D3 dispatcher: resolve failure is loud (journal: $(grep code_intel_preamble "${FIXTURE}/d3/journal.txt" 2>/dev/null | head -1))"
fi

# ── NEGATIVE CONTROLS: mutations INSIDE function bodies ─────────────────────
# Each copies the whole plugin root (so the mutant keeps its lib/config/
# prompts siblings), mutates one body, re-runs the matching probe, and prints
# the baseline_rc/mutated_rc pair. diff_hash proves nothing here — the pairs do.
copy_plugin_root() { # <tag> -> echoes mutant root
  local d="${FIXTURE}/mut-$1"
  # cp creates the FINAL path component but never intermediate dirs — the
  # mut-<tag> parent must exist first or the copy (and the mutation python
  # that reads from it) dies with "no such file".
  mkdir -p "${d}"
  cp -pR "${PLUGIN_ROOT}/" "${d}/plugin/" 2>/dev/null || cp -pR "${PLUGIN_ROOT}" "${d}/plugin"
  printf '%s' "${d}/plugin"
}

# NC1 (lib body): the sonnet-gate cause printf deleted -> lib cause row RED.
NC1_ROOT="$(copy_plugin_root nc1)"
NC1_LIB="${NC1_ROOT}/scripts/lib/leadv2-worker-mcp.sh"
NC1_BASE_RC=0
cause_case "NC1 baseline (live lib)" 3 "gate:LEADV2_SUBSESSION_SLIM_MCP=unset" "${L_LIB}" sonnet "${MCP_REPO}" - >/dev/null || NC1_BASE_RC=$?
NC1_MUT_RC=0
python3 - "${NC1_LIB}" <<'PYMUT' || NC1_MUT_RC=$?
import sys
path = sys.argv[1]
text = open(path).read()
needle = """        printf '[worker-mcp] preamble_skip_cause=gate:LEADV2_SUBSESSION_SLIM_MCP=%s\\n' \\
          "${LEADV2_SUBSESSION_SLIM_MCP:-unset}" >&2
"""
if needle not in text:
    print("MUTATION_TARGET_NOT_FOUND", file=sys.stderr); sys.exit(1)
open(path, "w").write(text.replace(needle, "", 1))
PYMUT
if [[ ${NC1_MUT_RC} -ne 0 ]]; then
  fail "NC1 mutation target found in lib body"
else
  NC1_MUT_RC=0
  CAUSE_CASE_SILENT=1 cause_case "NC1 mutated lib (cause printf deleted)" 3 "gate:LEADV2_SUBSESSION_SLIM_MCP=unset" "${NC1_LIB}" sonnet "${MCP_REPO}" - \
    >/dev/null 2>&1 || NC1_MUT_RC=$?
  if [[ ${NC1_BASE_RC} -eq 0 && ${NC1_MUT_RC} -ne 0 ]]; then
    pass "NC1 lib body: baseline_rc=${NC1_BASE_RC} mutated_rc=${NC1_MUT_RC} — RED, cause-less skip cannot return silently"
  else
    fail "NC1 lib body: baseline_rc=${NC1_BASE_RC} mutated_rc=${NC1_MUT_RC} — mutation NOT caught"
  fi
fi

# NC2 (dispatcher body): `_ci_slim=1` neutered -> D1 (default attach) RED.
NC2_ROOT="$(copy_plugin_root nc2)"
NC2_DSH="${NC2_ROOT}/scripts/leadv2-dispatch-code.sh"
NC2_BASE_RC=0; d1_default_attach "${DISPATCH_SCRIPT}" "${MCP_REPO}" || NC2_BASE_RC=$?
NC2_MUT_RC=0
python3 - "${NC2_DSH}" <<'PYMUT' || NC2_MUT_RC=$?
import sys
path = sys.argv[1]
text = open(path).read()
needle = '  if [[ "${arm}" == "sonnet" && -z "${_ci_slim}" ]]; then\n    _ci_slim=1\n  fi\n'
if needle not in text:
    print("MUTATION_TARGET_NOT_FOUND", file=sys.stderr); sys.exit(1)
open(path, "w").write(text.replace(needle, '  : # mutated: sonnet default dropped\n', 1))
PYMUT
if [[ ${NC2_MUT_RC} -ne 0 ]]; then
  fail "NC2 mutation target found in _spawn_worker_body"
else
  NC2_MUT_RC=0
  d1_default_attach "${NC2_DSH}" "${MCP_REPO}" >/dev/null 2>&1 || NC2_MUT_RC=$?
  if [[ ${NC2_BASE_RC} -eq 0 && ${NC2_MUT_RC} -ne 0 ]]; then
    pass "NC2 dispatcher body: baseline_rc=${NC2_BASE_RC} mutated_rc=${NC2_MUT_RC} — RED, default-attach cannot silently vanish"
  else
    fail "NC2 dispatcher body: baseline_rc=${NC2_BASE_RC} mutated_rc=${NC2_MUT_RC} — mutation NOT caught"
  fi
fi

# NC3 (dispatcher body): `cause=${_ci_cause}` dropped from the fail_open emit
# -> D2 (loud skip) RED — the exact 2026-09-04 silence coming back.
NC3_ROOT="$(copy_plugin_root nc3)"
NC3_DSH="${NC3_ROOT}/scripts/leadv2-dispatch-code.sh"
NC3_BASE_RC=0; d2_loud_skip "${DISPATCH_SCRIPT}" "${MCP_REPO}" || NC3_BASE_RC=$?
NC3_MUT_RC=0
python3 - "${NC3_DSH}" <<'PYMUT' || NC3_MUT_RC=$?
import sys
path = sys.argv[1]
text = open(path).read()
needle = 'mode=skipped reason=fail_open cause=${_ci_cause}"'
if needle not in text:
    print("MUTATION_TARGET_NOT_FOUND", file=sys.stderr); sys.exit(1)
open(path, "w").write(text.replace(needle, 'mode=skipped reason=fail_open"', 1))
PYMUT
if [[ ${NC3_MUT_RC} -ne 0 ]]; then
  fail "NC3 mutation target found in _spawn_worker_body"
else
  NC3_MUT_RC=0
  d2_loud_skip "${NC3_DSH}" "${MCP_REPO}" >/dev/null 2>&1 || NC3_MUT_RC=$?
  if [[ ${NC3_BASE_RC} -eq 0 && ${NC3_MUT_RC} -ne 0 ]]; then
    pass "NC3 dispatcher body: baseline_rc=${NC3_BASE_RC} mutated_rc=${NC3_MUT_RC} — RED, bare fail_open cannot return"
  else
    fail "NC3 dispatcher body: baseline_rc=${NC3_BASE_RC} mutated_rc=${NC3_MUT_RC} — mutation NOT caught"
  fi
fi

echo
log "TOTAL: PASS=${PASS} FAIL=${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
  for e in "${ERRORS[@]}"; do log "${e}"; done
  exit 1
fi
exit 0
