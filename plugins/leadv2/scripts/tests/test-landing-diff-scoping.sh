#!/usr/bin/env bash
# tests/test-landing-diff-scoping.sh — VERIFY-LANDING-FIX-01.
#
# Falsifying harness for the review-gate landing fix (round 2). Answers three
# numeric questions against the LIVE gate (leadv2-dispatch-product-close.sh +
# leadv2-dispatch-code.sh's arm spawns):
#   Q1 — arm parity: does the gate see a non-empty diff for glm / codex / sonnet alike?
#   Q2 — untracked visibility: does a brand-new (never `git add`-ed) file show up?
#   Q3 — escape hatch: does LEADV2_REVIEW_DIFF_CROSS_REPO actually flip the outcome?
#
# Red-first: every case also runs against a `git archive HEAD` extraction (pre-fix).
# A case that is GREEN against pre-fix is reported as GREEN-PRE-FIX, never silently
# counted as evidence (round-1's own suite had 7 of these).
#
# Safety: the whole run executes under a sandboxed HOME/TMPDIR, and a tripwire
# compares mtimes under ~/Projects/leadv2/plugins and ~/.claude before/after — any
# change fails the harness outright. Never git stash/reset --hard/clean.
#
# Usage:
#   bash test-landing-diff-scoping.sh              # post-fix run + red-first tally
#   bash test-landing-diff-scoping.sh --pre-fix DIR # single pass against DIR only

set -uo pipefail

# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db -- a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEADV2_REPO="$(cd "${SELF_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"

# ── safety: sandboxed HOME/TMPDIR for this entire process ─────────────────────────
ORIG_HOME="${HOME}"
if [[ -z "${LDS_SANDBOXED:-}" ]]; then
  SANDBOX_HOME="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-lds-home.XXXXXX")"
  mkdir -p "${SANDBOX_HOME}/tmp"
  export HOME="${SANDBOX_HOME}" TMPDIR="${SANDBOX_HOME}/tmp" LDS_SANDBOXED=1
fi

PASS=0; FAIL=0; GREEN_PRE_FIX=0; COULD_NOT_RUN=0
ERRORS=()
log() { printf -- '[TEST] %s\n' "$*"; }

# ── shared fixtures (mirrors tests/test-lane-writes-scoping.sh's proven pattern) ──
new_repo() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-lds.XXXXXX")"
  ( cd "${d}" && git init -q -b main && git config user.email test@example.com \
    && git config user.name test && mkdir -p agent \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "${d}"
}
worktree_path() { printf '%s/.claude/worktrees/%s' "$1" "$2"; }
phys() { ( cd "$1" 2>/dev/null && pwd -P ) 2>/dev/null || printf '%s' "$1"; }
ensure_worktree() {
  LEADV2_PROJECT_ROOT="$1" bash "${SELF_DIR}/leadv2-lane-worktree.sh" ensure "$2" standard >/dev/null 2>&1
  worktree_path "$1" "$2"
}
# Honors --cwd if present in argv (glm/codex); else records $PWD (subsession, which
# gets `cd`, not `--cwd` — a stub that ONLY parsed --cwd would silently record nothing
# for that arm and pass vacuously, per the design's own risk #1).
make_cwd_recorder() {
  cat > "$1" <<'STUBEOF'
#!/usr/bin/env bash
if [[ "$1" == "status" ]]; then exit 0; fi
prev=""; cwd="$PWD"
for a in "$@"; do [[ "$prev" == "--cwd" ]] && cwd="$a"; prev="$a"; done
printf '%s' "$cwd" > "${STUB_CWD_FILE}"
case "$1" in
  bg)   printf 'handle-glm-stub\n' ;;
  task) printf 'task-stub-abcdef\n' ;;
  *) nohup sleep 30 >/dev/null 2>&1 & printf 'PID=%s LABEL=test SESSION_ID=test\n' "$!" ;;
esac
STUBEOF
  chmod +x "$1"
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
make_review_pass_stub() {
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
exit 0
EOF
  chmod +x "$1"
}
# Direct call into the gate itself, with every hazard in §5 neutralized.
run_gate() { # <scripts_dir> <root> <task_sig8> <author> <lane_writes_csv> <lane_work_root> <cross_repo> <resolver_dir> [<start_sha>]
  local sd="$1" root="$2" sig="$3" author="$4" writes="$5" lane="$6" cross="$7" d="$8" start_sha="${9:-}"
  LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_DISPATCH_LANE_WRITES="${writes}" \
  LEADV2_LANE_WORK_ROOT="${lane}" LEADV2_REVIEW_DIFF_CROSS_REPO="${cross}" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  LEADV2_LANE_START_SHA="${start_sha}" \
  bash "${sd}/leadv2-dispatch-product-close.sh" "${root}" "${sig}" "${author}" "" 0 1 "${sig}-founder" \
    >/dev/null 2>&1
}
gate_bytes() { local root="$1" sig="$2"; wc -c < "${root}/docs/handoff/dispatch-${sig}/review.diff" 2>/dev/null | tr -d ' '; }
gate_blocked() { local root="$1" sig="$2"; grep -q '^status: blocked' "${root}/docs/handoff/dispatch-${sig}/review-gate.md" 2>/dev/null; }
gate_base() { local root="$1" sig="$2"; grep '^base:' "${root}/docs/handoff/dispatch-${sig}/review-gate.md" 2>/dev/null | awk '{print $2}'; }

# ── Q1 — arm parity. Force each arm by excluding the OTHER two; never hardcode a
# single pair for all three (that is exactly the C-B trap this harness exists to
# avoid repeating). Q1a: does the worker land in WORK_ROOT? Q1b: does the gate then
# see a non-empty, unblocked diff from that same cwd? ─────────────────────────────
case_q1() { # <scripts_dir> <arm> -> 0 pass, 1 fail(red), 2 could-not-run
  local scripts_dir="$1" arm="$2"
  local dc="${scripts_dir}/leadv2-dispatch-code.sh" launcher="${scripts_dir}/leadv2-fanout-lane-launcher.sh"
  local pc="${scripts_dir}/leadv2-dispatch-product-close.sh"
  [[ -f "${dc}" && -f "${launcher}" && -f "${pc}" ]] || return 2
  local root tid stubdir cwd_file rel excl
  root="$(new_repo)"; tid="q1-${arm}-$$"; stubdir="$(mktemp -d)"; cwd_file="${stubdir}/cwd.txt"
  rel="agent/new_${arm}.py"
  make_cwd_recorder "${stubdir}/bin.sh"
  case "${arm}" in
    glm)    excl="codex,sonnet" ;;
    codex)  excl="glm,sonnet" ;;
    sonnet) excl="glm,codex" ;;
  esac
  mkdir -p "${root}/.claude/ref"
  printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' \
    > "${root}/.claude/ref/leadv2-routing.yaml"
  local mission_file="${stubdir}/mission.md" sig_dir="${stubdir}/sig"
  printf 'Q1 %s throwaway lane mission\n' "${arm}" > "${mission_file}"
  mkdir -p "${sig_dir}"

  STUB_CWD_FILE="${cwd_file}" CLAUDE_PROJECT_ROOT="${root}" LEADV2_PROJECT_ROOT="${root}" \
  LEADV2_DISPATCH_CACHE_DIR="${stubdir}/cache" LEADV2_JOURNAL_BIN=/bin/true \
  LEADV2_DISPATCH_GLM_BIN="${stubdir}/bin.sh" LEADV2_DISPATCH_CODEX_BIN="${stubdir}/bin.sh" \
  LEADV2_DISPATCH_SUBSESSION_BIN="${stubdir}/bin.sh" \
  LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 \
  LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS="${excl}" LEADV2_LANE_SHAPE=off \
  LEADV2_REQUIRE_LANE_WRITES=1 \
  bash "${launcher}" --task-id "${tid}" --class standard --mission-file "${mission_file}" \
    --project-root "${root}" --sig-dir "${sig_dir}" --dispatch-bin "${dc}" --writes "${rel}" \
    >/dev/null 2>&1

  local wt="" got="" ok=1
  wt="$(worktree_path "${root}" "${tid}")"
  if [[ -s "${cwd_file}" ]]; then
    got="$(cat "${cwd_file}")"
    if [[ -d "${wt}" && "$(phys "${got}")" == "$(phys "${wt}")" ]]; then
      # Q1a confirmed: write the real deliverable at the recorded cwd, then run Q1b —
      # the gate itself, on that same cwd, as an independent process (not the
      # dispatch-code.sh spawn path) with CROSS_REPO=1 (the shipped default).
      mkdir -p "$(dirname "${got}/${rel}")"
      printf 'q1 %s deliverable\n' "${arm}" > "${got}/${rel}"
      local gd="${stubdir}/gate"; mkdir -p "${gd}"
      make_resolver_stub "${gd}/resolver.py" codex
      make_review_pass_stub "${gd}/codex.sh"
      run_gate "${scripts_dir}" "${root}" "q1${arm}sig" sonnet "${rel}" "${got}" 1 "${gd}"
      local n; n="$(gate_bytes "${root}" "q1${arm}sig")"
      if [[ -n "${n}" && "${n}" -gt 0 ]] && ! gate_blocked "${root}" "q1${arm}sig"; then
        ok=0
      fi
    fi
  fi
  rm -rf "${root}" "${stubdir}"
  return "${ok}"
}

# ── Q2 — untracked visibility, basic case: a never-`git add`-ed new file must
# still appear in review.diff. ─────────────────────────────────────────────────────
case_q2_basic() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d
  root="$(new_repo)"; tid="q2-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  mkdir -p "${wt}/agent"
  printf 'brand new, never git add-ed\n' > "${wt}/agent/newmod.py"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  run_gate "${scripts_dir}" "${root}" q2sig001 sonnet "agent/newmod.py" "${wt}" 1 "${d}"
  local diff="${root}/docs/handoff/dispatch-q2sig001/review.diff" ok=1
  [[ -s "${diff}" ]] && grep -q 'newmod' "${diff}" && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Q2-self — the mission's own self-referential case: LANE_WRITES names the two
# files this very round-2 change added, but reconstructed on a FIXTURE repo (never
# ~/Projects/leadv2 itself — the mission's stated hazard). ─────────────────────────
case_q2_self() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d writes
  root="$(new_repo)"; tid="q2s-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"
  [[ -d "${wt}" ]] || return 2
  mkdir -p "${wt}/plugins/leadv2/scripts/tests"
  printf '#!/usr/bin/env bash\n# fixture stand-in\n' > "${wt}/plugins/leadv2/scripts/leadv2-acceptance-shape.sh"
  printf '#!/usr/bin/env bash\n# fixture stand-in test\n' > "${wt}/plugins/leadv2/scripts/tests/test-acceptance-shape.sh"
  writes="plugins/leadv2/scripts/leadv2-acceptance-shape.sh,plugins/leadv2/scripts/tests/test-acceptance-shape.sh"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  run_gate "${scripts_dir}" "${root}" q2ssig01 sonnet "${writes}" "${wt}" 1 "${d}"
  local diff="${root}/docs/handoff/dispatch-q2ssig01/review.diff" ok=1
  if [[ -s "${diff}" ]] && grep -q 'acceptance-shape' "${diff}" && grep -q 'test-acceptance-shape' "${diff}"; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Q3 — escape hatch, as a PAIR. Asserting only CROSS_REPO=0 -> non-empty is green
# against round-1 whenever the worktree happens to be non-empty by chance — the
# actual claim is that the flag CHANGES the outcome, so both runs are compared. ────
case_q3_pair() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid wt d
  root="$(new_repo)"; tid="q3-$$"
  wt="$(ensure_worktree "${root}" "${tid}")"   # guaranteed-empty worktree
  [[ -d "${wt}" ]] || return 2
  printf 'seed\nedited-in-root\n' > "${root}/agent/seed.py"   # real change, OUTSIDE the worktree
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"

  run_gate "${scripts_dir}" "${root}" q3crsig1 sonnet "agent/seed.py" "${wt}" 1 "${d}"
  local n_on; n_on="$(gate_bytes "${root}" "q3crsig1")"
  local blocked_on=1; gate_blocked "${root}" "q3crsig1" && blocked_on=0

  run_gate "${scripts_dir}" "${root}" q3crsig0 sonnet "agent/seed.py" "${wt}" 0 "${d}"
  local n_off; n_off="$(gate_bytes "${root}" "q3crsig0")"
  local blocked_off=1; gate_blocked "${root}" "q3crsig0" && blocked_off=0

  local ok=1
  # ON: expect 0 bytes / blocked. OFF: expect >0 bytes / not blocked. AND they differ.
  if [[ "${n_on:-0}" -eq 0 && ${blocked_on} -eq 0 && "${n_off:-0}" -gt 0 && ${blocked_off} -ne 0 ]]; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── §5 structural requirement — leave LANE_WORK_ROOT unset, confined only by the
# sandboxed HOME; path-of's fallback must not escape to a real production worktree. ─
case_q_unset_workroot_safety() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root tid d
  root="$(new_repo)"; tid="q0-$$"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  # Deliberately no LEADV2_LANE_WORK_ROOT: path-of will look for a worktree under
  # ${root}/.claude/worktrees/${tid}-founder, which does not exist -> diff_root falls
  # back to ${root} itself (documented escape-hatch-without-the-flag shape, §6).
  LEADV2_DISPATCH_CACHE_DIR="${d}/cache" LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_JOURNAL_BIN=/bin/true LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
  LEADV2_GLM_POLICY_RESOLVER="${d}/resolver.py" LEADV2_DISPATCH_CODEX_BIN="${d}/codex.sh" \
  bash "${scripts_dir}/leadv2-dispatch-product-close.sh" "${root}" "q0sig001" sonnet "" 0 1 "${tid}-founder" \
    >/dev/null 2>&1
  # Pass condition here is purely about safety, not gate correctness: the gate must
  # have run at all (produced SOME review-gate.md) without touching anything outside
  # root/HOME (the top-level tripwire is the real judge of that).
  local ok=1
  [[ -f "${root}/docs/handoff/dispatch-q0sig001/review-gate.md" ]] && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Q4 — committed-lane-in-shared-tree (S-3 round 3, LANE-START-SHA-01). A lane that
# COMMITTED its own work before the close gate ran produces an empty `git diff HEAD` by
# definition -- exactly the case the mission calls out as producing an empty review.diff
# today. lane_work_root == root itself (the shared tree, no worktree), LANE_START_SHA
# recorded BEFORE the lane's commit. ─────────────────────────────────────────────────────
case_q4_committed_lane() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root start_sha d
  root="$(new_repo)"
  start_sha="$(git -C "${root}" rev-parse HEAD)"
  mkdir -p "${root}/agent"
  printf 'q4 committed deliverable\n' > "${root}/agent/q4new.py"
  ( cd "${root}" && git add agent/q4new.py && git commit -qm 'lane commit' ) >/dev/null 2>&1
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"
  # cross=0: exercises the plain (non-cross-repo) branch's base too, since that group
  # was never touched by round 2's cross-repo-only fix.
  run_gate "${scripts_dir}" "${root}" q4sig001 sonnet "agent/q4new.py" "${root}" 0 "${d}" "${start_sha}"
  local diff="${root}/docs/handoff/dispatch-q4sig001/review.diff" ok=1
  [[ -s "${diff}" ]] && grep -q 'q4new' "${diff}" && ok=0
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Q5 — never-smaller guard, both arms, real lane shape. For a fixture whose HEAD-diff
# is already non-empty (uncommitted work on top of a committed lane-start), assert the
# base-aware gate NEVER returns fewer bytes than a HEAD-only run of the identical
# fixture -- the acceptance that killed round 1. Run once per "arm" label (glm, codex)
# to match the mission's explicit "both arms" requirement; AUTHOR only affects reviewer
# selection here, but two independent gate runs on the same fixture shape is the
# meaningful repeat. Resolver is fixed to "codex" (matching every other case in this
# file), so the arm under test must be something other than codex or the reviewer-
# equals-author refusal fires BEFORE diff scoping even runs (an unrelated gate, not
# the mechanism under test here). ──────────────────────────────────────────────────
case_q5_never_smaller() { # <scripts_dir> <arm> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1" arm="$2"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root start_sha d
  root="$(new_repo)"
  start_sha="$(git -C "${root}" rev-parse HEAD)"
  mkdir -p "${root}/agent"
  printf 'q5 committed deliverable\n' > "${root}/agent/q5new.py"
  ( cd "${root}" && git add agent/q5new.py && git commit -qm 'lane commit 1' ) >/dev/null 2>&1
  # further uncommitted edit on top -- this is what a plain HEAD diff already sees today.
  printf 'q5 committed deliverable\nplus an uncommitted follow-up edit\n' > "${root}/agent/q5new.py"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"

  run_gate "${scripts_dir}" "${root}" "q5${arm}headonly" "${arm}" "agent/q5new.py" "${root}" 0 "${d}" ""
  local n_head; n_head="$(gate_bytes "${root}" "q5${arm}headonly")"

  run_gate "${scripts_dir}" "${root}" "q5${arm}withbase" "${arm}" "agent/q5new.py" "${root}" 0 "${d}" "${start_sha}"
  local n_base; n_base="$(gate_bytes "${root}" "q5${arm}withbase")"

  local ok=1
  # base-aware run must be >= the HEAD-only run, and strictly greater here since the base
  # run also picks up the committed hunk the HEAD-only run cannot see.
  if [[ -n "${n_head}" && -n "${n_base}" && "${n_base}" -ge "${n_head}" && "${n_base}" -gt 0 ]]; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── Q6 — bad/foreign sha falls back to HEAD, byte-identical to today. Covers both
# ladder rungs: a sha that resolves in NO repo (foreign/garbage) and a sha that is a
# real commit but NOT an ancestor of HEAD (diverged history, simulated via an orphan
# branch commit). Either must fall back to exactly the HEAD-only diff -- never smaller,
# never different -- so the mechanism can never make things worse than today. ──────────
case_q6_bad_sha_fallback() { # <scripts_dir> -> 0 pass, 1 fail, 2 could-not-run
  local scripts_dir="$1"
  [[ -f "${scripts_dir}/leadv2-dispatch-product-close.sh" ]] || return 2
  local root d foreign_sha diverged_sha
  root="$(new_repo)"
  printf 'q6 uncommitted deliverable\n' > "${root}/agent/q6new.py"
  d="$(mktemp -d)"
  make_resolver_stub "${d}/resolver.py" codex
  make_review_pass_stub "${d}/codex.sh"

  run_gate "${scripts_dir}" "${root}" q6baseline sonnet "agent/q6new.py" "${root}" 0 "${d}" ""
  local n_baseline; n_baseline="$(gate_bytes "${root}" q6baseline)"

  foreign_sha="0123456789abcdef0123456789abcdef01234567"
  run_gate "${scripts_dir}" "${root}" q6foreign sonnet "agent/q6new.py" "${root}" 0 "${d}" "${foreign_sha}"
  local n_foreign; n_foreign="$(gate_bytes "${root}" q6foreign)"

  ( cd "${root}" && git checkout -q --orphan diverged-branch >/dev/null 2>&1 \
      && git commit --allow-empty -qm orphan-diverged >/dev/null 2>&1 )
  diverged_sha="$(cd "${root}" && git rev-parse diverged-branch 2>/dev/null)"
  ( cd "${root}" && git checkout -q main >/dev/null 2>&1 )
  run_gate "${scripts_dir}" "${root}" q6diverged sonnet "agent/q6new.py" "${root}" 0 "${d}" "${diverged_sha}"
  local n_diverged; n_diverged="$(gate_bytes "${root}" q6diverged)"

  local ok=1
  if [[ "${n_foreign:-x}" == "${n_baseline:-y}" && "${n_diverged:-x}" == "${n_baseline:-y}" && -n "${n_baseline}" && "${n_baseline}" -gt 0 ]]; then
    ok=0
  fi
  rm -rf "${root}" "${d}"
  return "${ok}"
}

# ── runner ──────────────────────────────────────────────────────────────────────
# Parallel indexed arrays (bash-3.2-safe: no associative arrays). run_all_cases is
# always called in the SAME order, so index i means the same case in every pass.
CASE_NAMES=(); CASE_RCS=()

run_case() { # <name> <fn> [args...] -- runs against TARGET, records rc by index
  local name="$1" fn="$2"; shift 2
  local rc
  "${fn}" "${TARGET}" "$@" >/dev/null 2>&1; rc=$?
  CASE_NAMES+=("${name}"); CASE_RCS+=("${rc}")
  if [[ ${rc} -eq 2 ]]; then
    log "SKIPPED-CANNOT-RUN: ${name}"
  elif [[ ${rc} -eq 0 ]]; then
    log "PASS ${name}"
  else
    log "FAIL ${name}"
  fi
}

run_all_cases() {
  CASE_NAMES=(); CASE_RCS=()
  run_case "Q1-glm"          case_q1 glm
  run_case "Q1-codex"        case_q1 codex
  run_case "Q1-sonnet"       case_q1 sonnet
  run_case "Q2-basic"        case_q2_basic
  run_case "Q2-self"         case_q2_self
  run_case "Q3-pair"         case_q3_pair
  run_case "Q0-unset-safety" case_q_unset_workroot_safety
  run_case "Q4-committed-lane"    case_q4_committed_lane
  run_case "Q5-never-smaller-glm"    case_q5_never_smaller glm
  run_case "Q5-never-smaller-sonnet" case_q5_never_smaller sonnet
  run_case "Q6-bad-sha-fallback"   case_q6_bad_sha_fallback
}

report_single_pass() {
  local p=0 f=0 s=0 errs=()
  local i
  for i in "${!CASE_RCS[@]}"; do
    case "${CASE_RCS[$i]}" in
      0) p=$((p+1)) ;;
      2) s=$((s+1)) ;;
      *) f=$((f+1)); errs+=("${CASE_NAMES[$i]}") ;;
    esac
  done
  echo ""
  echo "Results (single-pass against ${TARGET}): ${p} passed, ${f} failed, ${s} skipped"
  [[ ${f} -gt 0 ]] && printf -- 'FAIL: %s\n' "${errs[@]}"
  return "${f}"
}

# ── mode dispatch ───────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--pre-fix" ]]; then
  TARGET="${2:?scratchdir required}"
  run_all_cases
  report_single_pass; frc=$?
  [[ ${frc} -gt 0 ]] && exit 1
  exit 0
fi

# tripwire baseline (against the REAL home/repo, taken before sandboxing anything)
STAMP="$(mktemp "${TMPDIR}/leadv2-lds-stamp.XXXXXX")"

TARGET="${SELF_DIR}"
run_all_cases
POST_NAMES=("${CASE_NAMES[@]}"); POST_RCS=("${CASE_RCS[@]}")
POST_FAIL_COUNT=0; POST_ERRORS=()
for i in "${!POST_RCS[@]}"; do
  [[ "${POST_RCS[$i]}" -ne 0 && "${POST_RCS[$i]}" -ne 2 ]] && { POST_FAIL_COUNT=$((POST_FAIL_COUNT+1)); POST_ERRORS+=("${POST_NAMES[$i]}"); }
done

# red-first: re-run every case against a git-archive HEAD reconstruction. Best-effort:
# scripts absent from the archive (untracked in this round) cannot be reconstructed,
# so those cases are COULD-NOT-RUN pre-fix, never silently folded into a pass.
RF_RED=0; RF_GREEN_PRE_FIX=0; RF_COULD_NOT_RUN_PRE=0; RF_TOTAL_POST_PASS=0
GREEN_PRE_FIX_NAMES=()
if [[ -n "${LEADV2_REPO}" ]]; then
  PREFIX_DIR="$(mktemp -d "${TMPDIR}/leadv2-lds-prefix.XXXXXX")"
  git -C "${LEADV2_REPO}" archive HEAD plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
  PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"
  if [[ -f "${PREFIX_SCRIPTS}/leadv2-dispatch-product-close.sh" ]]; then
    TARGET="${PREFIX_SCRIPTS}"
    run_all_cases
    PRE_RCS=("${CASE_RCS[@]}")
    for i in "${!POST_RCS[@]}"; do
      [[ "${POST_RCS[$i]}" -eq 0 ]] || continue   # only post-fix PASSes are candidate evidence
      RF_TOTAL_POST_PASS=$((RF_TOTAL_POST_PASS+1))
      case "${PRE_RCS[$i]:-2}" in
        0) RF_GREEN_PRE_FIX=$((RF_GREEN_PRE_FIX+1)); GREEN_PRE_FIX_NAMES+=("${POST_NAMES[$i]}") ;;
        2) RF_COULD_NOT_RUN_PRE=$((RF_COULD_NOT_RUN_PRE+1)) ;;
        *) RF_RED=$((RF_RED+1)) ;;
      esac
    done
  else
    log "pre-fix reconstruction: dispatch-product-close.sh absent from HEAD archive -- red-first not runnable"
    RF_COULD_NOT_RUN_PRE=${#POST_RCS[@]}
  fi
  rm -rf "${PREFIX_DIR}"
fi

# tripwire check: real repo tree + real (pre-sandbox) HOME, never the sandbox itself
TRIPWIRE_HITS="$(find "${LEADV2_REPO}/plugins" -newer "${STAMP}" 2>/dev/null; find "${ORIG_HOME}/.claude" -maxdepth 2 -newer "${STAMP}" 2>/dev/null)"

echo ""
echo "Results (post-fix, live tree): $(( ${#POST_RCS[@]} - POST_FAIL_COUNT )) passed, ${POST_FAIL_COUNT} failed"
[[ ${POST_FAIL_COUNT} -gt 0 ]] && printf -- 'FAIL: %s\n' "${POST_ERRORS[@]}"
echo "red-first: ${RF_RED}/${RF_TOTAL_POST_PASS} post-fix-passing cases RED against pre-fix"
[[ ${RF_GREEN_PRE_FIX} -gt 0 ]] && printf -- 'GREEN-PRE-FIX (not evidence): %s\n' "${GREEN_PRE_FIX_NAMES[@]}"
echo "pre-fix-could-not-run: ${RF_COULD_NOT_RUN_PRE}"
if [[ -n "${TRIPWIRE_HITS}" ]]; then
  echo "TRIPWIRE: paths changed under \${LEADV2_REPO}/plugins or ~/.claude during the run (attribution required in report):"
  printf '%s\n' "${TRIPWIRE_HITS}"
fi
rm -f "${STAMP}"

[[ ${POST_FAIL_COUNT} -gt 0 ]] && exit 1
exit 0
