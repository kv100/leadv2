#!/usr/bin/env bash
# tests/test-report-only-gate.sh — REPORT-ONLY-GATE-01.
#
# A lane may declare its deliverable is a FILE (report:<rel path>), not a diff, and be
# gated on that file existing and being non-trivial. Six cases (mission §5):
#
#   1 — report lane, good report      -> rc0, kind: report + deliverable: in
#        review-gate.md; report.md survives under ROOT docs/handoff/dispatch-<sig>/
#        AFTER the lane worktree is deleted (harvest proof).
#   2 — report lane, no file          -> status blocked / reason report_missing,
#        ledger no_work:report_missing.
#   3 — report lane, 3-line stub      -> reason report_too_thin, bytes: printed.
#   4 — diff lane regression          -> declaration absent + real diff: review-gate.md
#        byte-identical to the pre-change (git archive HEAD) gate output.
#   5 — dead worker regression        -> empty diff + clean tree: reason no_work WITH
#        kind: diff (distinguishable from a report lane by review-gate.md alone).
#   6 — unknown kind (artifact:x)     -> treated as a diff lane (case 6a: gate shape);
#        dispatch journals lane_deliverable status=ignored (6b); a valid report
#        declaration satisfies _lane_writes_guard (6c minimal pair: declared
#        dispatches, undeclared parks no_lane_writes).
#
# Red-first: cases 1/2/3/5/6a are also run against a `git archive HEAD` extraction
# (pre-fix scripts, which do not know LANE_DELIVERABLE); reds there are evidence.
# Drives the REAL gate scripts (never a reimplementation). Sandboxed HOME/TMPDIR;
# never touches the real repo's ledger or ~/.claude/cache.
# Run: bash scripts/tests/test-report-only-gate.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_LIVE="$(cd "${TESTS_DIR}/.." && pwd)"
LEADV2_REPO="$(git -C "${SCRIPTS_LIVE}" rev-parse --show-toplevel 2>/dev/null || true)"
# case_4_diff_golden's "pre" baseline must predate BUILDER-SELFCHECK-GATE-01
# (merged 53d4465), not just be "HEAD" — once the gate itself is committed,
# archiving literal HEAD makes live==pre and the golden comparison tautological
# (it can never go red again). 1806b4f is the gate's immediate parent commit.
PRE_GATE_REF="1806b4f43394f4799c244947a405bcd3ea6e1ec3"

ORIG_HOME="${HOME}"
if [[ -z "${ROG1_SANDBOXED:-}" ]]; then
  SANDBOX_HOME="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-home.XXXXXX")"
  mkdir -p "${SANDBOX_HOME}/tmp"
  export HOME="${SANDBOX_HOME}" TMPDIR="${SANDBOX_HOME}/tmp" ROG1_SANDBOXED=1
fi

# SUITES-WRITE-THE-LIVE-CONTROL-PLANE-01: a sandboxed HOME is not enough. Every
# docs/leadv2 entry in any checkout is a SYMLINK into the shared live control
# plane (~/.claude/leadv2-state/leadv2/), so a product invocation that resolves
# its control-plane root through leadv2-state-path.sh writes the FLEET's bus,
# merge queue, questions and locks -- measured 2026-09-04: this suite alone, from
# a clean tree, left eight entries dirty including a type-change that replaced
# the shared open-threads.md symlink with a real file (the active.yaml disease).
# This suite already pins LEADV2_PROJECT_ROOT per invocation; state-path.sh keys
# on LEADV2_STATE_ROOT (see its line ~78), which nothing here was setting.
if [[ -z "${LEADV2_STATE_ROOT:-}" ]]; then
  export LEADV2_STATE_ROOT="${TMPDIR:-/tmp}/rog1-state"
  mkdir -p "${LEADV2_STATE_ROOT}"
fi

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1.XXXXXX")"
  ( cd "${d}" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p agent \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "${d}"
}
ensure_worktree() { # <scripts_dir> <repo> <tid> -> prints wt path
  LEADV2_PROJECT_ROOT="$2" bash "$1/leadv2-lane-worktree.sh" ensure "$3" standard >/dev/null 2>&1
  printf '%s/.claude/worktrees/%s' "$2" "$3"
}
make_resolver_stub() { # <path> <reviewer-arm>
  cat > "$1" <<PYEOF
#!/usr/bin/env python3
print("reviewer=$2")
print("pool=$2")
print("refusal=")
PYEOF
  chmod +x "$1"
}
make_review_pass_stub() { # <path>
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
exit 0
EOF
  chmod +x "$1"
}
# >=600 non-whitespace bytes across >=12 non-blank lines.
write_good_report() { # <abs>
  local i
  mkdir -p "$(dirname "$1")"
  {
    printf '# Analysis report\n\n'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
      printf 'Finding %02d: file src/mod%d.c line %d contradicts claim %d; evidence quoted verbatim here.\n' "$i" "$i" $((i * 11)) "$i"
    done
    printf '\nRecommendation follows from the findings above.\n'
  } > "$1"
}
write_stub_report() { # <abs>
  mkdir -p "$(dirname "$1")"
  printf 'short\nstub\nreport\n' > "$1"
}

# run_gate <scripts_dir> <root> <sig> <lane_wt> <d> <errf> <deliverable> <ledger_file|-> <writes_csv>
# Captures the gate's rc on stdout ("rc=<n>"); stderr to <errf> (emit's target).
# A real ledger file routes write-terminal to the REAL ledger (sandboxed file); "-" uses
# /bin/true so no row is written.
run_gate() {
  local sd="$1" root="$2" sig="$3" lane="$4" d="$5" errf="$6" deliverable="$7" ledger="$8" writes="${9:-}"
  local term_ledger=1 ledger_bin="${sd}/leadv2-dispatch-ledger.sh"
  if [[ "${ledger}" == "-" ]]; then
    term_ledger=0; ledger_bin=/bin/true; ledger="${d}/ledger-unused.jsonl"
  fi
  CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" \
  LEADV2_DISPATCH_CACHE_DIR="${d}/cache" \
  LEADV2_DISPATCH_TERMINAL_LEDGER="${term_ledger}" \
  LEADV2_DISPATCH_LEDGER_BIN="${ledger_bin}" \
  LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="${ledger}" \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_DISPATCH_LANE_WRITES="${writes}" \
  LEADV2_DISPATCH_LANE_DELIVERABLE="${deliverable}" \
  LEADV2_LANE_WORK_ROOT="${lane}" LEADV2_REVIEW_DIFF_CROSS_REPO=0 \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
    bash "${sd}/leadv2-dispatch-product-close.sh" "${root}" "${sig}" sonnet "" 0 1 "${sig}-founder" \
    >/dev/null 2>"${errf}"
  printf 'rc=%s' "$?"
}
gate_md() { local root="$1" sig="$2"; cat "${root}/docs/handoff/dispatch-${sig}/review-gate.md" 2>/dev/null; }
gate_terminal_line() { local errf="$1"; grep 'review_gate ' "${errf}" 2>/dev/null | tail -1; }

# ── Case 1 — good report: pass shape + survival after worktree deletion ───────────
case_1_good_report() { # <scripts_dir>
  local sd="$1"
  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf rrc gate
  root="$(new_repo)"; tid="rog1c1-$$"
  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  write_good_report "${wt}/analysis/report.md"
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  rrc="$(run_gate "${sd}" "${root}" rog1c1sig "${wt}" "${d}" "${errf}" "report:analysis/report.md" "-")"
  gate="$(gate_md "${root}" rog1c1sig)"
  local ok=0
  [[ "${rrc}" == "rc=0" ]] || ok=1
  grep -q '^status: pass' <<<"${gate}" || ok=1
  grep -q '^kind: report' <<<"${gate}" || ok=1
  grep -q '^deliverable: docs/handoff/dispatch-rog1c1sig/report.md' <<<"${gate}" || ok=1
  grep -q '^review: PASS' <<<"${gate}" || ok=1
  # survival: delete the lane worktree, the harvested report must still be ROOT-side
  rm -rf "${wt}"
  [[ -s "${root}/docs/handoff/dispatch-rog1c1sig/report.md" ]] || ok=1
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── Case 2 — report lane, no file -> blocked report_missing + ledger row ──────────
case_2_missing() { # <scripts_dir>
  local sd="$1"
  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf rrc gate row
  root="$(new_repo)"; tid="rog1c2-$$"
  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  rrc="$(run_gate "${sd}" "${root}" rog1c2sig "${wt}" "${d}" "${errf}" "report:analysis/report.md" "${d}/ledger.jsonl")"
  gate="$(gate_md "${root}" rog1c2sig)"
  row="$(grep '"task_sig":"rog1c2sig"' "${d}/ledger.jsonl" 2>/dev/null)"
  local ok=0
  [[ "${rrc}" == "rc=5" ]] || ok=1
  grep -q '^status: blocked' <<<"${gate}" || ok=1
  grep -q '^reason: report_missing' <<<"${gate}" || ok=1
  grep -q '^kind: report' <<<"${gate}" || ok=1
  grep -q '^declared: analysis/report.md' <<<"${gate}" || ok=1
  grep -q '"terminal":"no_work"' <<<"${row}" || ok=1
  grep -q '"cause":"report_missing"' <<<"${row}" || ok=1
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── Case 3 — 3-line stub -> report_too_thin with bytes ────────────────────────────
case_3_thin() { # <scripts_dir>
  local sd="$1"
  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf rrc gate row
  root="$(new_repo)"; tid="rog1c3-$$"
  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  write_stub_report "${wt}/analysis/report.md"
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  rrc="$(run_gate "${sd}" "${root}" rog1c3sig "${wt}" "${d}" "${errf}" "report:analysis/report.md" "${d}/ledger.jsonl")"
  gate="$(gate_md "${root}" rog1c3sig)"
  row="$(grep '"task_sig":"rog1c3sig"' "${d}/ledger.jsonl" 2>/dev/null)"
  local ok=0
  [[ "${rrc}" == "rc=5" ]] || ok=1
  grep -q '^status: blocked' <<<"${gate}" || ok=1
  grep -q '^reason: report_too_thin' <<<"${gate}" || ok=1
  grep -q '^kind: report' <<<"${gate}" || ok=1
  grep -q '^bytes: ' <<<"${gate}" || ok=1
  grep -q '^min: ' <<<"${gate}" || ok=1
  grep -q '"cause":"report_too_thin"' <<<"${row}" || ok=1
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── Case 4 — diff lane regression: byte-identical review-gate.md vs pre-change ────
# Shared scenario runner: tracked modification in the lane worktree, NO deliverable.
run_diff_lane_scenario() { # <scripts_dir> <out_gate_file>
  local sd="$1" out="$2"
  local root tid wt d errf
  root="$(new_repo)"; tid="rog1c4-$$"
  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  # BUILDER-SELFCHECK-GATE-01: content must be VALID Python — the selfcheck gate now
  # py_compiles changed .py files, and the old bare-words seed was a syntax error, so
  # the golden case (expects status: pass) red-ed on a legitimately-broken fixture diff.
  printf '# seed\n# edited-in-worktree-for-golden\n' > "${wt}/agent/seed.py"
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  run_gate "${sd}" "${root}" rog1c4sig "${wt}" "${d}" "${errf}" "" "-" "agent/seed.py" >/dev/null
  cp "${root}/docs/handoff/dispatch-rog1c4sig/review-gate.md" "${out}" 2>/dev/null || touch "${out}"
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return 0
}
case_4_diff_golden() { # <scripts_dir>
  local sd="$1"
  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
  local live_gate pre_gate prefix_dir
  live_gate="$(mktemp "${TMPDIR:-/tmp}/leadv1-g1.XXXXXX")"
  pre_gate="$(mktemp "${TMPDIR:-/tmp}/leadv1-g2.XXXXXX")"
  run_diff_lane_scenario "${sd}" "${live_gate}"
  if ! grep -q '^status: pass' "${live_gate}"; then
    rm -f "${live_gate}" "${pre_gate}"
    return 1
  fi
  # no git history (no LEADV2_REPO), or the fixed pre-gate ref is unreachable
  # from this checkout (shallow clone / rewritten history) => no pre-change
  # baseline to compare against; skip rather than silently comparing HEAD to
  # itself.
  [[ -n "${LEADV2_REPO}" ]] || { rm -f "${live_gate}" "${pre_gate}"; return 2; }
  git -C "${LEADV2_REPO}" cat-file -e "${PRE_GATE_REF}" 2>/dev/null || { rm -f "${live_gate}" "${pre_gate}"; return 2; }
  prefix_dir="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-pre.XXXXXX")"
  git -C "${LEADV2_REPO}" archive "${PRE_GATE_REF}" plugins/leadv2/scripts 2>/dev/null | tar -x -C "${prefix_dir}" 2>/dev/null
  if [[ ! -f "${prefix_dir}/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh" ]]; then
    rm -rf "${prefix_dir}"; rm -f "${live_gate}" "${pre_gate}"
    return 2
  fi
  run_diff_lane_scenario "${prefix_dir}/plugins/leadv2/scripts" "${pre_gate}"
  rm -rf "${prefix_dir}"
  local ok=0
  if ! cmp -s "${live_gate}" "${pre_gate}"; then
    ok=1
    log "golden mismatch: live=[$(cat "${live_gate}")] pre=[$(cat "${pre_gate}")]"
  fi
  rm -f "${live_gate}" "${pre_gate}"
  return "${ok}"
}

# ── Case 5 — dead worker: empty diff + clean tree -> no_work WITH kind: diff ──────
case_5_dead_worker() { # <scripts_dir>
  local sd="$1"
  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf rrc gate line
  root="$(new_repo)"; tid="rog1c5-$$"
  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  rrc="$(run_gate "${sd}" "${root}" rog1c5sig "${wt}" "${d}" "${errf}" "" "-")"
  gate="$(gate_md "${root}" rog1c5sig)"
  line="$(gate_terminal_line "${errf}")"
  local ok=0
  [[ "${rrc}" == "rc=5" ]] || ok=1
  grep -q '^status: blocked' <<<"${gate}" || ok=1
  grep -q '^reason: no_work' <<<"${gate}" || ok=1
  grep -q '^kind: diff' <<<"${gate}" || ok=1
  grep -q 'terminal=no_work' <<<"${line}" || ok=1
  grep -q 'cause=empty_diff' <<<"${line}" || ok=1
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── Case 6a — unknown kind through the GATE: treated as a diff lane ───────────────
case_6a_unknown_kind_gate() { # <scripts_dir>
  local sd="$1"
  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d errf rrc gate
  root="$(new_repo)"; tid="rog1c6-$$"
  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  rrc="$(run_gate "${sd}" "${root}" rog1c6sig "${wt}" "${d}" "${errf}" "artifact:docs/x.md" "-")"
  gate="$(gate_md "${root}" rog1c6sig)"
  local ok=0
  # clean tree + unparsable declaration => exactly the dead-worker diff-lane shape
  [[ "${rrc}" == "rc=5" ]] || ok=1
  grep -q '^reason: no_work' <<<"${gate}" || ok=1
  grep -q '^kind: diff' <<<"${gate}" || ok=1
  if grep -q '^reason: report_' <<<"${gate}"; then ok=1; fi
  rm -rf "${root}" "${d}"; rm -f "${errf}"
  return "${ok}"
}

# ── Cases 6b/6c — dispatch-side: unknown-kind journal + writes-guard exemption ────
# Modeled on test-dispatch-architect-degrades.sh: stub worker + architect, ARCHITECT
# gate off, lane-worktree bin stubbed so isolation CANNOT substitute for a writes
# declaration (the exemption is the only thing that can satisfy the guard).
run_dispatch() { # <root> <mission> ; prints dispatch stdout
  CLAUDE_PROJECT_ROOT="$1" LEADV2_PROJECT_ROOT="$1" \
  LEADV2_DISPATCH_CACHE_DIR="$1/cache" \
  LEADV2_DISPATCH_SUBSESSION_BIN="$1/worker" \
  LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
  LEADV2_FOREIGN_ROOT_GUARD=0 \
  LEADV2_DISPATCH_LANE_WORKTREE_BIN="$1/wt-stub.sh" \
    bash "${SCRIPTS_LIVE}/leadv2-dispatch-code.sh" "$2" --kind product --protected 2>&1
}
make_dispatch_repo() { # -> repo path with routing.yaml + worker/wt stubs
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-r.XXXXXX")"
  mkdir -p "${root}/.claude/ref" "${root}/docs/leadv2/.bus-offsets"
  ( cd "${root}" && git init -q && git config user.email test@example.com \
    && git config user.name test && : > seed && git add seed && git commit -qm seed ) >/dev/null 2>&1
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: [safety_gate_publish_payments]\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > "${root}/.claude/ref/leadv2-routing.yaml"
  printf '#!/usr/bin/env bash\nnohup sleep 60 >/dev/null 2>&1 &\nprintf "PID=%%s LABEL=test SESSION_ID=test\\n" "$!"\n' > "${root}/worker"
  # never provides an isolated worktree (echoes the main checkout): the guard's
  # worktree fallback can never fire, so only writes/deliverable can satisfy it.
  printf '#!/usr/bin/env bash\ncase "$1" in ensure) printf "%%s" "${LEADV2_PROJECT_ROOT}"; exit 0;; path-of) exit 1;; esac\nexit 0\n' > "${root}/wt-stub.sh"
  chmod +x "${root}/worker" "${root}/wt-stub.sh"
  printf '%s' "${root}"
}
journal_of() { find "$1/docs/leadv2/tasks" -name journal.md -print -quit 2>/dev/null; }

case_6b_unknown_kind_journal() {
  local root out jr
  root="$(make_dispatch_repo)"
  out="$(run_dispatch "${root}" 'diagnose nothing; no LANE_WRITES here
LANE_DELIVERABLE: artifact:docs/x.md')"
  jr="$(journal_of "${root}")"
  local ok=0
  [[ -n "${jr}" ]] || ok=1
  grep -q 'lane_deliverable .*status=ignored' "${jr}" 2>/dev/null || ok=1
  grep -q 'reason=unknown_kind' "${jr}" 2>/dev/null || ok=1
  rm -rf "${root}"
  return "${ok}"
}
case_6c_guard_exemption() {
  # declared report lane dispatches (no park); undeclared twin parks no_lane_writes.
  local root_decl root_und jr out ok
  root_decl="$(make_dispatch_repo)"
  out="$(run_dispatch "${root_decl}" 'produce the analysis report
LANE_DELIVERABLE: report:docs/handoff/R1/report.md')"
  jr="$(journal_of "${root_decl}")"
  ok=0
  grep -q 'lane_deliverable .*status=declared' "${jr}" 2>/dev/null || ok=1
  grep -q 'lane_writes .*source=report_deliverable' "${jr}" 2>/dev/null || ok=1
  if grep -q 'reason=no_lane_writes' "${jr}" 2>/dev/null; then ok=1; fi
  rm -rf "${root_decl}"
  # undeclared twin: same mission without the declaration must park (minimal pair)
  root_und="$(make_dispatch_repo)"
  run_dispatch "${root_und}" 'produce the analysis report, no declaration at all here' >/dev/null 2>&1
  jr="$(journal_of "${root_und}")"
  grep -q 'reason=no_lane_writes' "${jr}" 2>/dev/null || ok=1
  rm -rf "${root_und}"
  return "${ok}"
}

# ── harness ───────────────────────────────────────────────────────────────────────
CASE_NAMES=(); CASE_RCS=()
run_case() { # <name> <fn> <scripts_dir>
  local name="$1" fn="$2" sd="$3" rc
  # Some gate helpers source strict-mode libraries.  Capture an expected red
  # through an `if` so `errexit` cannot abort the comparison arm before its
  # result is recorded.
  if "${fn}" "${sd}" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  CASE_NAMES+=("${name}"); CASE_RCS+=("${rc}")
  if [[ ${rc} -eq 2 ]]; then
    log "SKIPPED-CANNOT-RUN: ${name}"
  elif [[ ${rc} -eq 0 ]]; then
    log "PASS ${name}"
  else
    log "FAIL ${name}"
  fi
}

if bash -n "${SCRIPTS_LIVE}/leadv2-dispatch-product-close.sh" && \
   bash -n "${SCRIPTS_LIVE}/leadv2-dispatch-code.sh" && \
   bash -n "${SCRIPTS_LIVE}/lib/leadv2-report-deliverable.sh"; then
  pass "bash -n clean (gate scripts + lib)"
else
  fail "bash -n failed on a gate script or the lib"
fi
if /bin/bash -n "${SCRIPTS_LIVE}/leadv2-dispatch-product-close.sh" 2>/dev/null; then
  pass "/bin/bash -n (bash 3.2 syntax) product-close"
else
  fail "/bin/bash -n failed on leadv2-dispatch-product-close.sh"
fi

echo "=== pass 1/2: post-fix (live tree) ==="
run_case "C1-good-report"        case_1_good_report       "${SCRIPTS_LIVE}"
run_case "C2-report-missing"     case_2_missing           "${SCRIPTS_LIVE}"
run_case "C3-report-too-thin"    case_3_thin              "${SCRIPTS_LIVE}"
run_case "C4-diff-lane-golden"   case_4_diff_golden       "${SCRIPTS_LIVE}"
run_case "C5-dead-worker-kind"   case_5_dead_worker       "${SCRIPTS_LIVE}"
run_case "C6a-unknown-kind-gate" case_6a_unknown_kind_gate "${SCRIPTS_LIVE}"
run_case "C6b-unknown-kind-journal" case_6b_unknown_kind_journal "${SCRIPTS_LIVE}"
run_case "C6c-guard-exemption"   case_6c_guard_exemption  "${SCRIPTS_LIVE}"
POST_NAMES=("${CASE_NAMES[@]}"); POST_RCS=("${CASE_RCS[@]}")

echo ""
echo "=== pass 2/2: red-first pre-fix (git archive HEAD) — reds here are EVIDENCE ==="
RF_RED=0; RF_TOTAL=0
if [[ -n "${LEADV2_REPO}" ]]; then
  PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-pre.XXXXXX")"
  git -C "${LEADV2_REPO}" archive HEAD plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
  PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"
  if [[ -f "${PREFIX_SCRIPTS}/leadv2-dispatch-product-close.sh" ]]; then
    CASE_NAMES=(); CASE_RCS=()
    run_case "C1-good-report"      case_1_good_report        "${PREFIX_SCRIPTS}"
    run_case "C2-report-missing"   case_2_missing            "${PREFIX_SCRIPTS}"
    run_case "C3-report-too-thin"  case_3_thin               "${PREFIX_SCRIPTS}"
    run_case "C5-dead-worker-kind" case_5_dead_worker        "${PREFIX_SCRIPTS}"
    run_case "C6a-unknown-kind-gate" case_6a_unknown_kind_gate "${PREFIX_SCRIPTS}"
    # compare by NAME (the pre-fix block runs a subset of the post-fix cases)
    for i in "${!POST_RCS[@]}"; do
      [[ "${POST_RCS[$i]}" == "0" ]] || continue
      local_j=""; pre_rc=""
      for local_j in "${!CASE_NAMES[@]}"; do
        [[ "${CASE_NAMES[$local_j]}" == "${POST_NAMES[$i]}" ]] && pre_rc="${CASE_RCS[$local_j]}"
      done
      [[ -n "${pre_rc}" ]] || continue  # not run in the pre-fix block (C4/C6b/C6c)
      RF_TOTAL=$((RF_TOTAL + 1))
      [[ "${pre_rc}" != "0" ]] && RF_RED=$((RF_RED + 1))
    done
  else
    log "pre-fix reconstruction unavailable (HEAD archive lacks gate script)"
  fi
  rm -rf "${PREFIX_DIR}"
fi

POST_FAIL=0; POST_ERR=()
for i in "${!POST_RCS[@]}"; do
  if [[ "${POST_RCS[$i]}" != "0" && "${POST_RCS[$i]}" != "2" ]]; then
    POST_FAIL=$((POST_FAIL + 1)); POST_ERR+=("${POST_NAMES[$i]}")
  fi
done

echo ""
echo "Results (post-fix, live tree): $(( ${#POST_RCS[@]} - POST_FAIL )) passed, ${POST_FAIL} failed"
[[ ${POST_FAIL} -gt 0 ]] && printf -- 'FAIL: %s\n' "${POST_ERR[@]}"
echo "red-first: ${RF_RED}/${RF_TOTAL} post-fix-passing cases RED against pre-fix"

printf '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
[[ ${POST_FAIL} -gt 0 ]] && exit 1
exit 0
