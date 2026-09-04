#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# run-all-triggers: leadv2-dispatch-code leadv2-phase-record
# test-phase-gate-default-class.sh — PHASE-GATE-DEFAULT-CLASS-ESCAPES-IT-01
#
# The phase gate's permissive default, closed. Two rules under test, both in
# _phase_precondition_guard (leadv2-dispatch-code.sh):
#   (A) the class reaching the gate is canonicalized before the enforce/warn
#       case; an unrecognized spelling (ledger-borne `heavy`, `garbage`) used
#       to fall into warn — the permissive default (census: 31/77 live lanes
#       in the 24h to 2026-09-04T17:00Z dispatched with zero gate trace).
#   (B) every passage of the gate leaves a journal line: bootstrap admission
#       -> phase_precondition_bootstrap (with would_be_missing), satisfied
#       pass -> phase_precondition_pass, warn+missing -> phase_precondition_warn.
#
# Real functions throughout: the guard body is sed-extracted from the live
# dispatch-code.sh bytes, the assert is the real leadv2-phase-record.sh against
# a sandbox store, and T6 drives the REAL dispatcher with the REAL
# leadv2-journal.sh (no LEADV2_JOURNAL_BIN stub — the stub-lie that hid the
# dropped bootstrap event is exactly what this suite must not reproduce).
set -uo pipefail

# BURN-GOVERNOR-01: same as every suite here — never read the host burn db.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"
DISPATCH_BIN="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
LIB_GUARD="${SCRIPT_DIR}/../lib/leadv2-lane-guard.sh"

TMP_ROOT="$(mktemp -d /tmp/leadv2-pgdc-XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; }

# ── extract the REAL guard from the REAL file (empty extraction = fatal) ─────
GUARD_SH="${TMP_ROOT}/guard-extracted.sh"
sed -n '/^_phase_precondition_guard() {/,/^}$/p' "${DISPATCH_BIN}" > "${GUARD_SH}"
if [[ ! -s "${GUARD_SH}" ]] || ! grep -q '^_phase_precondition_guard()' "${GUARD_SH}"; then
  printf '[PHASE-GATE-DEFAULT-CLASS] extraction of _phase_precondition_guard failed\n'
  exit 3
fi

# ── direct-guard driver: real guard + real assert, stubbed emit/log only ─────
CASE_LOG="${TMP_ROOT}/emit.log"
run_guard() { # <root> <sig8> <class> -> rc; lines land in $CASE_LOG
  local root="$1" sig="$2" cls="$3"
  : > "${CASE_LOG}"
  (
    cd "${root}" || exit 9
    unset REQUIRE_PHASES REQUIRE_PHASES_ENV_SET LEADV2_REQUIRE_PHASES PHASE_GUARD_SCOPE
    export LEADV2_PROJECT_ROOT="${root}" PROJECT_ROOT="${root}"
    export PHASE_RECORD_BIN="${PHASE_RECORD}"
    export EMIT_LOG="${CASE_LOG}" GUARD_SH LIB_GUARD
    bash -c '
      source "${LIB_GUARD}"
      source "${GUARD_SH}"
      emit() { local j="$1"; shift; printf "%s\n" "$*" >> "${EMIT_LOG}"; }
      log() { :; }
      log_err() { :; }
      _phase_precondition_guard "$1" "$2" ""
    ' _ "${sig}" "${cls}"
  )
}
emit_has() { grep -q "$1" "${CASE_LOG}" 2>/dev/null; }
emit_lacks() { ! grep -q "$1" "${CASE_LOG}" 2>/dev/null; }

fresh_root() { # <name> -> echoes a new sandbox store root
  local r="${TMP_ROOT}/$1"
  mkdir -p "${r}"
  printf '%s' "${r}"
}
record() { # <root> <sig8> <phase> [extra args...]
  local root="$1" sig="$2" phase="$3"; shift 3
  ( cd "${root}" && LEADV2_PROJECT_ROOT="${root}" PROJECT_ROOT="${root}" \
      bash "${PHASE_RECORD}" record "${sig}" "${phase}" --owner test "$@" ) >/dev/null 2>&1
}

# T1: ledger-borne lowercase `heavy` (measured live, dispatch-4ab257f9) is
# canonicalized -> ENFORCED, not warned. Non-bootstrap lane (classify recorded,
# mirroring the dispatcher's own record at cmd_resolve) so plan/gate1 missing
# must REFUSE with the canonical class in the line.
R="$(fresh_root t1)"; record "$R" s1 classify --status done
run_guard "$R" s1 heavy; rc=$?
if [[ $rc -eq 1 ]]; then ok; else fail "T1: lowercase heavy should refuse (rc=$rc)"; fi
if emit_has 'phase_precondition_refused task=s1 class=Heavy'; then ok; else fail "T1: refused line must carry canonical class=Heavy (log=$(cat "${CASE_LOG}" 2>/dev/null | tr '\n' ' '))"; fi
if emit_lacks 'phase_precondition_config_error'; then ok; else fail "T1: canonicalized Heavy must not hit the invalid-class rc=4 path"; fi
if emit_lacks 'phase_precondition_warn'; then ok; else fail "T1: enforced class must not warn"; fi

# T2: a garbage class string defaults to Standard -> ENFORCED (fail-closed).
R="$(fresh_root t2)"; record "$R" s2 classify --status done
run_guard "$R" s2 garbage; rc=$?
if [[ $rc -eq 1 ]]; then ok; else fail "T2: garbage class should refuse as Standard (rc=$rc)"; fi
if emit_has 'phase_precondition_refused task=s2 class=Standard'; then ok; else fail "T2: refused line must carry class=Standard (log=$(cat "${CASE_LOG}" 2>/dev/null | tr '\n' ' '))"; fi

# T3: fresh Standard lane (zero records) — the dispatch-96d97702 shape. The
# bootstrap admission must leave a TRACE naming what it waived.
R="$(fresh_root t3)"
run_guard "$R" s3 Standard; rc=$?
if [[ $rc -eq 0 ]]; then ok; else fail "T3: bootstrap admission should proceed (rc=$rc)"; fi
if emit_has 'phase_precondition_bootstrap task=s3 class=Standard would_be_missing=classify,plan,gate1'; then ok; else fail "T3: bootstrap trace with class+would_be_missing expected (log=$(cat "${CASE_LOG}" 2>/dev/null | tr '\n' ' '))"; fi

# T4: satisfied Standard (classify+plan+gate1 recorded, real artifact for plan)
# — a pass must be VISIBLE, not silent.
R="$(fresh_root t4)"
mkdir -p "$R/docs/handoff/dispatch-s4"
printf '# brief\n\nfixture lead-authored plan\n' > "$R/docs/handoff/dispatch-s4/brief.md"
record "$R" s4 classify --status done
record "$R" s4 plan --status done --artifact docs/handoff/dispatch-s4/brief.md
record "$R" s4 gate1 --status done --reason 'fixture Gate 1 decision'
run_guard "$R" s4 Standard; rc=$?
if [[ $rc -eq 0 ]]; then ok; else fail "T4: satisfied Standard should pass (rc=$rc)"; fi
if emit_has 'phase_precondition_pass task=s4 class=Standard mode=1 scope=pre-build'; then ok; else fail "T4: pass trace expected (log=$(cat "${CASE_LOG}" 2>/dev/null | tr '\n' ' '))"; fi

# T5/T5b: Light and Trivial KEEP the historical warn default — the gate must be
# correct, not merely strict (negative control (c) targets exactly this).
R="$(fresh_root t5)"; record "$R" s5 classify --status done
run_guard "$R" s5 Light; rc=$?
if [[ $rc -eq 0 ]]; then ok; else fail "T5: Light warn mode must proceed (rc=$rc)"; fi
if emit_has 'phase_precondition_warn task=s5 class=Light missing='; then ok; else fail "T5: warn line with class+missing expected (log=$(cat "${CASE_LOG}" 2>/dev/null | tr '\n' ' '))"; fi
if emit_has 'phase_precondition_warn task=s5 class=Light missing=.*build'; then ok; else fail "T5: Light full-scope missing must include build"; fi
if emit_lacks 'phase_precondition_refused'; then ok; else fail "T5: Light must not be refused"; fi
R="$(fresh_root t5b)"; record "$R" s5b classify --status done
run_guard "$R" s5b Trivial; rc=$?
if [[ $rc -eq 0 ]]; then ok; else fail "T5b: Trivial warn mode must proceed (rc=$rc)"; fi
if emit_has 'phase_precondition_warn task=s5b class=Trivial'; then ok; else fail "T5b: warn line expected (log=$(cat "${CASE_LOG}" 2>/dev/null | tr '\n' ' '))"; fi

# ── T6: e2e — the REAL dispatcher + the REAL leadv2-journal.sh ───────────────
# No LEADV2_JOURNAL_BIN stub on purpose: dispatch's own emit has the right argv
# shape, but the bootstrap event used to reach the journal only through
# phase-record's _emit (<event> <detail> — dropped by the real journal.sh CLI,
# `append <task-id> <type> <text>`), so live lanes showed nothing. This case
# goes red the moment the caller-side trace disappears again.
E2E_SANDBOX="${TMP_ROOT}/e2e"
E2E_REPO="${E2E_SANDBOX}/repo"
mkdir -p "${E2E_REPO}"
( cd "${E2E_REPO}" && git init -q -b main \
  && git config user.email t@e.com && git config user.name t \
  && printf 'seed\n' > .gitignore && git add .gitignore && git commit -qm seed )
GLM_STUB="${E2E_SANDBOX}/glm-stub.sh"
cat > "${GLM_STUB}" <<'SH'
#!/usr/bin/env bash
RUNS="${LEADV2_STUB_GLM_RUNS:-/tmp/leadv2-stub-glm-runs}"
case "${1:-}" in
  bg)
    mkdir -p "$RUNS" 2>/dev/null
    handle="stub-run-$(date +%s)-$$"
    printf '%s' "$handle" > "$RUNS/$handle" 2>/dev/null
    printf '%s\n' "$handle"
    exit 0
    ;;
  status)
    if [[ -n "${2:-}" && -f "$RUNS/$2" ]]; then printf 'status: complete\n'; exit 0; fi
    exit 1
    ;;
  *) exit 0 ;;
esac
SH
chmod +x "${GLM_STUB}"
POLICY_STUB="${E2E_SANDBOX}/glm-policy-resolve-stub.py"
cat > "${POLICY_STUB}" <<'PY'
#!/usr/bin/env python3
print("arm=glm\nrule=none\nreason=e2e_stub\ntier=")
PY
chmod +x "${POLICY_STUB}"
STUB_RUNS="${E2E_SANDBOX}/glm-runs"
mkdir -p "${STUB_RUNS}"
M6='PGDC fixture Standard lane through the real journal writer'
SIG8="$(printf '%s' "${M6}" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}' | cut -c1-8)"
rc6=0
(
  cd "${E2E_REPO}" || exit 9
  unset LEADV2_JOURNAL_BIN REQUIRE_PHASES REQUIRE_PHASES_ENV_SET LEADV2_REQUIRE_PHASES PHASE_GUARD_SCOPE PROJECT_ROOT
  export LEADV2_PROJECT_ROOT="${E2E_REPO}" CLAUDE_PROJECT_DIR="${E2E_REPO}"
  export LEADV2_DISPATCH_CACHE_DIR="${E2E_SANDBOX}/cache" LEADV2_STATE_BASE="${E2E_SANDBOX}/state"
  export LEADV2_DISPATCH_GLM_BIN="${GLM_STUB}" LEADV2_STUB_GLM_RUNS="${STUB_RUNS}"
  export GLM_POLICY_RESOLVER="${POLICY_STUB}"
  export LEADV2_ROUTER_V2=0 LEADV2_LANE_SHAPE=off LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0
  export LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_DISPATCH_PENDING_TTL_S=5 LEADV2_DISPATCH_CONFIRMED_TTL_S=10
  bash "${DISPATCH_BIN}" --kind tooling --task-class Standard "${M6}"
) >/dev/null 2>&1 || rc6=$?
REAL_JOURNAL="${E2E_REPO}/docs/leadv2/tasks/dispatch-${SIG8}/journal.md"
if [[ $rc6 -eq 0 ]]; then ok; else fail "T6: dispatch should exit 0 (rc=$rc6)"; fi
if grep -q 'dispatch_classified task='"${SIG8}" "${REAL_JOURNAL}" 2>/dev/null; then ok; else fail "T6: real journal missing dispatch_classified (journal=${REAL_JOURNAL})"; fi
if grep -q 'phase_precondition_bootstrap task='"${SIG8}"' class=Standard would_be_missing=' "${REAL_JOURNAL}" 2>/dev/null; then
  ok
else
  fail "T6: real journal (no stub) must carry phase_precondition_bootstrap with class+would_be_missing (journal=${REAL_JOURNAL})"
fi

printf '\n[PHASE-GATE-DEFAULT-CLASS] pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
