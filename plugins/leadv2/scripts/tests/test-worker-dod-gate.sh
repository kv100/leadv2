#!/usr/bin/env bash
# tests/test-worker-dod-gate.sh — WORKER-DOD-GATE-01.
#
# Exercises lib/leadv2-dod-gate.sh (checks a-e), leadv2-mutation-control.sh
# (the 4 exit-code cases), and the production wiring in
# leadv2-dispatch-product-close.sh (the gate must refuse BEFORE the
# LEADV2_REVIEW_ENGINE branch splits, for both engine=unset and engine=1).
#
# Every fixture lives under a mktemp dir; nothing here touches the real repo
# tree. Each hard-check case is a red+green pair: the red half proves the
# check actually fires, not merely that the happy path is green.
#
# Run: bash plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SCRIPTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOD_GATE_SH="${PLUGIN_SCRIPTS}/lib/leadv2-dod-gate.sh"
MUT_CTL_SH="${PLUGIN_SCRIPTS}/leadv2-mutation-control.sh"
DISPATCH_SH="${PLUGIN_SCRIPTS}/leadv2-dispatch-product-close.sh"

PASS=0
FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/dod-gate-suite.XXXXXX")"
cleanup() { rm -rf "${FIXTURE}"; }
trap cleanup EXIT INT TERM

# ── syntax floor (bash + the macOS 3.2 binary the lanes actually run) ───────
if bash -n "${DOD_GATE_SH}" 2>/dev/null && /bin/bash -n "${DOD_GATE_SH}" 2>/dev/null; then
  pass "bash -n leadv2-dod-gate.sh (incl. 3.2)"
else
  fail "bash -n leadv2-dod-gate.sh"
fi
if bash -n "${MUT_CTL_SH}" 2>/dev/null && /bin/bash -n "${MUT_CTL_SH}" 2>/dev/null; then
  pass "bash -n leadv2-mutation-control.sh (incl. 3.2)"
else
  fail "bash -n leadv2-mutation-control.sh"
fi

# ── source the gate lib (BASH_SOURCE[0] != $0 keeps it non-executing) ──────
# shellcheck source=/dev/null
source "${DOD_GATE_SH}"

# ── fixture repo: a from-scratch git repo, its own identity ────────────────
# `main` is pinned at the base commit and HEAD lives on a separate `lane`
# branch throughout the rest of this fixture's life, so
# _dod_resolve_base()/_dod_worker_diff_hash() (fix-round-2 finding 1) have a
# real, non-trivial merge-base to diff against instead of main==HEAD (which
# would make every hash the trivial empty-diff hash).
REPO="${FIXTURE}/repo"
mkdir -p "${REPO}"
# `git init` checks out the default branch (verified: "main" in this
# environment) and the base commit lands there; `checkout -b lane`
# immediately after leaves `main` parked at that commit forever while `lane`
# (checked out from here on) receives every subsequent commit_all — never
# `git branch -f main HEAD` while main is checked out, which git refuses
# (the branch a repo's sole checkout has open cannot be force-moved).
( cd "${REPO}" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base \
    && git checkout -q -b lane )

TASK_DIR="${REPO}/docs/handoff/T1"
mkdir -p "${TASK_DIR}"

commit_all() { ( cd "${REPO}" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m "step" ) >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# check (a) — report.md exists / committed / headed
# ---------------------------------------------------------------------------
cat > "${TASK_DIR}/brief.md" <<'EOF'
Paste the run-all output. Write report.md with the results.
EOF
commit_all

out="$(_dod_check_a "${REPO}" "${TASK_DIR}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'dod_fail check=report_missing_or_unheaded detail=missing_file'; then
  pass "check_a: missing report.md -> fail"
else
  fail "check_a: missing report.md -> fail (got rc=${rc} out=${out})"
fi

cat > "${TASK_DIR}/report.md" <<'EOF'
# report

no heading here
EOF
commit_all
out="$(_dod_check_a "${REPO}" "${TASK_DIR}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'no_evidence_heading'; then
  pass "check_a: report.md without evidence heading -> fail"
else
  fail "check_a: report.md without evidence heading -> fail (got rc=${rc} out=${out})"
fi

cat > "${TASK_DIR}/report.md" <<'EOF'
# report

## Evidence
here it is
EOF
commit_all
out="$(_dod_check_a "${REPO}" "${TASK_DIR}")"; rc=$?
if [[ ${rc} -eq 0 ]] && printf '%s' "${out}" | grep -q 'dod_pass check=report'; then
  pass "check_a: committed report.md with Evidence heading -> pass"
else
  fail "check_a: compliant report.md -> pass (got rc=${rc} out=${out})"
fi

cat > "${TASK_DIR}/brief.md" <<'EOF'
No deliverable file named here.
EOF
commit_all
rm -f "${TASK_DIR}/report.md"; commit_all
out="$(_dod_check_a "${REPO}" "${TASK_DIR}")"; rc=$?
if [[ ${rc} -eq 3 ]] && printf '%s' "${out}" | grep -q 'dod_skip check=report_not_required'; then
  pass "check_a: brief never mentions report.md -> skip, not fail"
else
  fail "check_a: brief without report.md mention -> skip (got rc=${rc} out=${out})"
fi

# ---------------------------------------------------------------------------
# check (b) — paste-line evidence + mutation-control artifact binding
# ---------------------------------------------------------------------------
cat > "${TASK_DIR}/brief.md" <<'EOF'
Paste the falsifiable output here.
Paste the mutation-control result here.
EOF
cat > "${TASK_DIR}/report.md" <<'EOF'
# report

## Evidence
unrelated text, nothing pasted
EOF
commit_all
DIFF_FILE="${FIXTURE}/round.diff"
printf -- '--- a/foo.sh\n+++ b/foo.sh\n@@\n-old\n+new\n' > "${DIFF_FILE}"
out="$(_dod_check_b "${REPO}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'dod_fail check=paste_evidence_missing'; then
  pass "check_b: paste-line with no matching fenced section -> fail"
else
  fail "check_b: unanswered paste-line -> fail (got rc=${rc} out=${out})"
fi

cat > "${TASK_DIR}/report.md" <<'EOF'
# report

## Falsifiable
```
falsifiable output pasted right here
```

## Mutation-control
```
MUTATION-CONTROL ok diff_hash=abc
```
EOF
commit_all
out="$(_dod_check_b "${REPO}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'mutation_control_not_via_runner'; then
  pass "check_b: mutation-control paste-line present but no bound artifact -> fail"
else
  fail "check_b: ungrounded mutation-control claim -> fail (got rc=${rc} out=${out})"
fi

# fix-round-2 finding 1: lane_diff_hash is the sha256 of `git diff <base> HEAD`
# (mutation-control/ excluded) over the fixture repo's OWN committed history --
# exactly what leadv2-mutation-control.sh and this gate compute. The artifact's
# diff_hash is separately the actual applied mutation diff hash; both are
# required so a mutant cannot be confused with the lane that proved it.
mkdir -p "${TASK_DIR}/mutation-control"

# fix-round-1 finding 2: a hand-written one-line file (worker owns the diff,
# can compute its own sha256) must NOT be accepted — only the full
# leadv2-mutation-control.sh artifact shape is.
LANE_DIFF_HASH="$(_dod_worker_diff_hash "${REPO}")"
printf 'diff_hash=%s\n' "${LANE_DIFF_HASH}" > "${TASK_DIR}/mutation-control/run1.txt"
commit_all
LANE_DIFF_HASH="$(_dod_worker_diff_hash "${REPO}")"
out="$(_dod_check_b "${REPO}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'mutation_control_not_via_runner'; then
  pass "check_b: hand-written one-line diff_hash artifact (no provenance) -> fail"
else
  fail "check_b: forged one-line artifact -> fail (got rc=${rc} out=${out})"
fi
rm -f "${TASK_DIR}/mutation-control/run1.txt"

MUTATION_HASH="$(printf '%s' 'fixture mutation diff' | shasum -a 256 | awk '{print $1}')"
printf 'suite=plugins/leadv2/scripts/tests/test-widget.sh\nfile=plugins/leadv2/scripts/lib/leadv2-widget.sh\nanchor=s/foo/bar/\nbaseline_rc=0\nmutated_rc=1\nred_line=FAIL widget\ndiff_hash=%s\nlane_diff_hash=%s\n' \
  "${MUTATION_HASH}" "${LANE_DIFF_HASH}" > "${TASK_DIR}/mutation-control/run2.txt"
out="$(_dod_check_b "${REPO}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 0 ]] && printf '%s' "${out}" | grep -q 'dod_pass check=paste_evidence'; then
  pass "check_b: real generator-shaped artifact (mutation diff_hash + bound lane_diff_hash) -> pass"
else
  fail "check_b: grounded mutation-control artifact -> pass (got rc=${rc} out=${out})"
fi
commit_all

# fix-round-2 finding 1: no merge-base resolvable (a bare non-git dir) ->
# undetermined, never a silent pass -- the sub-check that used to be gated on
# "no diff_file" is now gated on "no merge-base"; a bare dir with no .git at
# all is the fixture for that.
BARE_DIR="${FIXTURE}/not-a-repo"
mkdir -p "${BARE_DIR}"
out="$(_dod_check_b "${BARE_DIR}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 2 ]] && printf '%s' "${out}" | grep -q 'mutation_control_undetermined'; then
  pass "check_b: no merge-base resolvable (non-git root) -> undetermined (never a silent pass)"
else
  fail "check_b: unresolvable merge-base -> undetermined (got rc=${rc} out=${out})"
fi

# ---------------------------------------------------------------------------
# check (c) — suite registration
# ---------------------------------------------------------------------------
cat > "${DIFF_FILE}" <<'EOF'
--- /dev/null
+++ b/plugins/leadv2/scripts/lib/leadv2-widget.sh
@@
+widget
--- /dev/null
+++ b/plugins/leadv2/scripts/test-widget-dropped-outside-tests-dir.sh
@@
+suite
EOF
out="$(_dod_check_c "${REPO}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 3 ]] && printf '%s' "${out}" | grep -q 'reason=no_run_all'; then
  pass "check_c: no tests/run-all.sh in repo -> skip (portability)"
else
  fail "check_c: absent tests/run-all.sh -> skip (got rc=${rc} out=${out})"
fi

mkdir -p "${REPO}/tests"
cat > "${REPO}/tests/run-all.sh" <<'EOF'
#!/usr/bin/env bash
EXTRA_SUITE_MAP="glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh"
EOF
commit_all
# leadv2-widget-suite.sh is a non-conventional suite path, not in the map -> fail
out="$(_dod_check_c "${REPO}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'dod_fail check=suite_unregistered'; then
  pass "check_c: new suite path touched by diff, unregistered -> fail"
else
  fail "check_c: unregistered suite -> fail (got rc=${rc} out=${out})"
fi

cat > "${REPO}/tests/run-all.sh" <<'EOF'
#!/usr/bin/env bash
EXTRA_SUITE_MAP="glm-coder.sh:plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh
leadv2-widget.sh:plugins/leadv2/scripts/test-widget-dropped-outside-tests-dir.sh"
EOF
commit_all
out="$(_dod_check_c "${REPO}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 0 ]] && printf '%s' "${out}" | grep -q 'dod_pass check=suite_registration'; then
  pass "check_c: suite registered via EXTRA_SUITE_MAP -> pass"
else
  fail "check_c: registered suite -> pass (got rc=${rc} out=${out})"
fi

cat > "${DIFF_FILE}" <<'EOF'
--- /dev/null
+++ b/plugins/leadv2/scripts/tests/test-self-select.sh
@@
+t
EOF
out="$(_dod_check_c "${REPO}" "${TASK_DIR}" "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 0 ]] && printf '%s' "${out}" | grep -q 'dod_pass check=suite_registration'; then
  pass "check_c: conventional tests/test-*.sh path self-selects, no map row required -> pass"
else
  fail "check_c: self-selecting suite path -> pass (got rc=${rc} out=${out})"
fi

# ---------------------------------------------------------------------------
# check (d) — runtime-state path in the diff
# ---------------------------------------------------------------------------
cat > "${DIFF_FILE}" <<'EOF'
--- a/docs/leadv2/active.yaml
+++ b/docs/leadv2/active.yaml
@@
-x
+y
EOF
out="$(_dod_check_d "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'dod_fail check=runtime_state_in_diff'; then
  pass "check_d: runtime-state path in diff -> fail"
else
  fail "check_d: runtime-state path -> fail (got rc=${rc} out=${out})"
fi

cat > "${DIFF_FILE}" <<'EOF'
--- a/plugins/leadv2/scripts/leadv2-helpers.sh
+++ b/plugins/leadv2/scripts/leadv2-helpers.sh
@@
-x
+y
EOF
out="$(_dod_check_d "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 0 ]] && printf '%s' "${out}" | grep -q 'dod_pass check=runtime_state'; then
  pass "check_d: clean diff -> pass"
else
  fail "check_d: clean diff -> pass (got rc=${rc} out=${out})"
fi

# fix-round-1 finding 1: a pure DELETION of a runtime-state path (the path
# only appears on the `--- a/` side; `+++ /dev/null` on the new side) must
# still fail. Live-probed by the round-1 reviewer against the +++-only parse.
cat > "${DIFF_FILE}" <<'EOF'
--- a/docs/leadv2/active.yaml
+++ /dev/null
@@
-x
-y
EOF
out="$(_dod_check_d "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'dod_fail check=runtime_state_in_diff'; then
  pass "check_d: deletion-only diff of runtime-state path -> fail"
else
  fail "check_d: deletion-only runtime-state path -> fail (got rc=${rc} out=${out})"
fi

out="$(_dod_check_d "${FIXTURE}/nope.diff")"; rc=$?
if [[ ${rc} -eq 2 ]] && printf '%s' "${out}" | grep -q 'runtime_state_undetermined'; then
  pass "check_d: missing diff_file -> undetermined, never a silent pass"
else
  fail "check_d: missing diff_file -> undetermined (got rc=${rc} out=${out})"
fi

# fix-round-2 finding 3: three shapes that emit neither `--- a/` nor `+++ b/`
# because git generates no content hunk for them — live-verified against
# real `git diff`/`git diff --cached -M` output before this fix (see
# report.md). All three must still fail.
cat > "${DIFF_FILE}" <<'EOF'
diff --git a/docs/leadv2/empty.yaml b/docs/leadv2/empty.yaml
new file mode 100644
index 0000000..e69de29
EOF
out="$(_dod_check_d "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'dod_fail check=runtime_state_in_diff'; then
  pass "check_d: empty-file creation of a runtime-state path (no ---/+++ lines) -> fail"
else
  fail "check_d: empty-file creation -> fail (got rc=${rc} out=${out})"
fi

cat > "${DIFF_FILE}" <<'EOF'
diff --git a/scratch/notes.yaml b/docs/leadv2/notes.yaml
similarity index 100%
rename from scratch/notes.yaml
rename to docs/leadv2/notes.yaml
EOF
out="$(_dod_check_d "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'dod_fail check=runtime_state_in_diff'; then
  pass "check_d: 100% rename into a runtime-state path (no ---/+++ lines) -> fail"
else
  fail "check_d: 100% rename -> fail (got rc=${rc} out=${out})"
fi

cat > "${DIFF_FILE}" <<'EOF'
diff --git a/docs/leadv2/active.yaml b/docs/leadv2/active.yaml
old mode 100644
new mode 100755
EOF
out="$(_dod_check_d "${DIFF_FILE}")"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${out}" | grep -q 'dod_fail check=runtime_state_in_diff'; then
  pass "check_d: mode-only change of a runtime-state path (no ---/+++ lines) -> fail"
else
  fail "check_d: mode-only change -> fail (got rc=${rc} out=${out})"
fi

# ---------------------------------------------------------------------------
# check (e) — report-only, never affects rc
# ---------------------------------------------------------------------------
cat > "${TASK_DIR}/report.md" <<'EOF'
# report

## Evidence
The endpoint has a rate limit of 100/min, per docs say so above.
EOF
commit_all
out="$(_dod_check_e "${TASK_DIR}")"
if printf '%s' "${out}" | grep -q 'dod_note check=unverified_claim'; then
  pass "check_e: external claim w/o evidence:/UNVERIFIED nearby -> dod_note emitted"
else
  fail "check_e: expected dod_note for ungrounded claim (got: ${out})"
fi

cat > "${TASK_DIR}/report.md" <<'EOF'
# report

## Evidence
The endpoint has a rate limit of 100/min. evidence: curl output above.
EOF
commit_all
out="$(_dod_check_e "${TASK_DIR}")"
if [[ -z "${out}" ]]; then
  pass "check_e: claim immediately followed by evidence: -> no note"
else
  fail "check_e: grounded claim should not note (got: ${out})"
fi

# ---------------------------------------------------------------------------
# lv2_dod_gate_run — end-to-end: compliant fixture passes, violating one fails
# ---------------------------------------------------------------------------
cat > "${TASK_DIR}/brief.md" <<'EOF'
Nothing further needed from the worker for this fixture.
EOF
rm -f "${TASK_DIR}/report.md"
commit_all
cat > "${DIFF_FILE}" <<'EOF'
--- a/plugins/leadv2/scripts/leadv2-helpers.sh
+++ b/plugins/leadv2/scripts/leadv2-helpers.sh
@@
-x
+y
EOF
OUT_MD="${FIXTURE}/dod-gate-out.md"
gate_out="$(lv2_dod_gate_run "${REPO}" "${TASK_DIR}" "${DIFF_FILE}" "${OUT_MD}")"; rc=$?
if [[ ${rc} -eq 0 ]] && [[ -f "${OUT_MD}" ]]; then
  pass "lv2_dod_gate_run: fully-compliant fixture -> rc=0, out file written"
else
  fail "lv2_dod_gate_run: compliant fixture -> rc=0 (got rc=${rc})"
fi

cat > "${DIFF_FILE}" <<'EOF'
--- a/docs/leadv2/active.yaml
+++ b/docs/leadv2/active.yaml
@@
-x
+y
EOF
gate_out="$(lv2_dod_gate_run "${REPO}" "${TASK_DIR}" "${DIFF_FILE}" "${OUT_MD}")"; rc=$?
if [[ ${rc} -eq 1 ]] && grep -q 'dod_fail check=runtime_state_in_diff' "${OUT_MD}"; then
  pass "lv2_dod_gate_run: runtime-state violation -> rc=1, reason recorded in out file"
else
  fail "lv2_dod_gate_run: violating fixture -> rc=1 (got rc=${rc})"
fi

# fix-round-2 finding 2: an out dir that CANNOT be created (mkdir -p fails —
# a regular file occupies the parent path component) must still name its
# cause on stdout/stderr, never collapse to an empty out_md and dod_unknown.
BLOCKED_PARENT="${FIXTURE}/blocked-parent"
: > "${BLOCKED_PARENT}"
UNWRITABLE_OUT_MD="${BLOCKED_PARENT}/dod-gate.md"
gate_out="$(lv2_dod_gate_run "${REPO}" "${TASK_DIR}" "${DIFF_FILE}" "${UNWRITABLE_OUT_MD}" 2>&1)"; rc=$?
if [[ ${rc} -eq 1 ]] && printf '%s' "${gate_out}" | grep -q 'dod_fail check=runtime_state_in_diff' \
   && [[ ! -e "${UNWRITABLE_OUT_MD}" ]]; then
  pass "lv2_dod_gate_run: unwritable out dir -> cause still named on stdout/stderr, never dod_unknown"
else
  fail "lv2_dod_gate_run: unwritable out dir -> cause still named (got rc=${rc} out=${gate_out})"
fi
rm -f "${BLOCKED_PARENT}"

# ---------------------------------------------------------------------------
# leadv2-mutation-control.sh — 4 exit-code cases (own scratch fixture, no
# shared state with the gate-lib fixture above)
# ---------------------------------------------------------------------------
MC_REPO="${FIXTURE}/mc-repo"
mkdir -p "${MC_REPO}/lib"
( cd "${MC_REPO}" && git init -q )

cat > "${MC_REPO}/lib/target.sh" <<'EOF'
#!/usr/bin/env bash
add() { echo $(( $1 + $2 )); }
EOF
cat > "${MC_REPO}/suite.sh" <<'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/target.sh"
result="$(add 2 3)"
if [[ "${result}" == "5" ]]; then
  echo "PASS: add(2,3)=5"
  exit 0
else
  echo "FAIL: add(2,3) expected 5 got ${result}"
  exit 1
fi
EOF
( cd "${MC_REPO}" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m base )
MC_TASK_DIR="${FIXTURE}/mc-task"
mkdir -p "${MC_TASK_DIR}"
# fix-round-2 finding 1: leadv2-mutation-control.sh now computes its own
# diff_hash internally (no more caller-supplied 4th positional) via the same
# LEADV2_LANE_START_SHA-first base ladder lib/leadv2-dod-gate.sh's
# _dod_resolve_base() uses. Pin it to this fixture's own base commit so every
# call below resolves a real, stable merge-base.
MC_BASE_SHA="$(cd "${MC_REPO}" && git rev-parse HEAD)"

( cd "${MC_REPO}" && LEADV2_LANE_START_SHA="${MC_BASE_SHA}" bash "${MUT_CTL_SH}" \
    suite.sh lib/target.sh 's/ + / - /' "${MC_TASK_DIR}" ) \
    >"${FIXTURE}/mc-ok.out" 2>&1
mc_rc=$?
if [[ ${mc_rc} -eq 0 ]] && grep -q 'MUTATION-CONTROL ok' "${FIXTURE}/mc-ok.out" \
   && ls "${MC_TASK_DIR}/mutation-control"/*.txt >/dev/null 2>&1; then
  pass "mutation-control: mutation applied, suite went red -> exit 0 ok + artifact written"
else
  fail "mutation-control: expected exit0/ok (got rc=${mc_rc}, out=$(cat "${FIXTURE}/mc-ok.out"))"
fi

MC_FIRST_ARTIFACT="$(find "${MC_TASK_DIR}/mutation-control" -type f -name '*.txt' -print | sort | tail -1)"
MC_FIRST_HASH="$(sed -n 's/^diff_hash=//p' "${MC_FIRST_ARTIFACT}" | head -1)"
if [[ "${MC_FIRST_HASH}" =~ ^[0-9a-f]{64}$ ]] \
   && [[ "${MC_FIRST_HASH}" != e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]] \
   && grep -q '^lane_diff_hash=[0-9a-f]\{64\}$' "${MC_FIRST_ARTIFACT}"; then
  pass "mutation-control: diff_hash is a non-empty applied-mutant hash and lane binding is separate"
else
  fail "mutation-control: generated artifact hash fields are not distinct, non-empty proofs"
fi

( cd "${MC_REPO}" && LEADV2_LANE_START_SHA="${MC_BASE_SHA}" bash "${MUT_CTL_SH}" \
    suite.sh lib/target.sh 's/ + / % /' "${MC_TASK_DIR}" ) \
    >"${FIXTURE}/mc-second.out" 2>&1
mc_rc=$?
MC_SECOND_ARTIFACT="$(find "${MC_TASK_DIR}/mutation-control" -type f -name '*.txt' -print | sort | tail -1)"
MC_SECOND_HASH="$(sed -n 's/^diff_hash=//p' "${MC_SECOND_ARTIFACT}" | head -1)"
if [[ ${mc_rc} -eq 0 ]] && [[ -n "${MC_FIRST_ARTIFACT}" && "${MC_SECOND_ARTIFACT}" != "${MC_FIRST_ARTIFACT}" ]] \
   && [[ "${MC_FIRST_HASH}" != "${MC_SECOND_HASH}" ]]; then
  pass "mutation-control: two different applied mutations produce different diff_hash values"
else
  fail "mutation-control: distinct mutations collided (rc=${mc_rc}, first=${MC_FIRST_HASH}, second=${MC_SECOND_HASH})"
fi

( cd "${MC_REPO}" && LEADV2_LANE_START_SHA="${MC_BASE_SHA}" bash "${MUT_CTL_SH}" suite.sh lib/target.sh 's/NOPE_NO_MATCH_ANCHOR/x/' "${MC_TASK_DIR}" ) \
  >"${FIXTURE}/mc-anchor.out" 2>&1
mc_rc=$?
if [[ ${mc_rc} -eq 2 ]] && grep -q 'reason=anchor_count' "${FIXTURE}/mc-anchor.out"; then
  pass "mutation-control: absent anchor -> exit 2 control_not_applied reason=anchor_count"
else
  fail "mutation-control: absent anchor -> exit 2 (got rc=${mc_rc}, out=$(cat "${FIXTURE}/mc-anchor.out"))"
fi

cat > "${MC_REPO}/suite.sh" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: baseline is already red"
exit 1
EOF
( cd "${MC_REPO}" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m redbase )
( cd "${MC_REPO}" && LEADV2_LANE_START_SHA="${MC_BASE_SHA}" bash "${MUT_CTL_SH}" suite.sh lib/target.sh 's/ + / - /' "${MC_TASK_DIR}" ) \
  >"${FIXTURE}/mc-baseline.out" 2>&1
mc_rc=$?
if [[ ${mc_rc} -eq 2 ]] && grep -q 'reason=baseline_not_green' "${FIXTURE}/mc-baseline.out"; then
  pass "mutation-control: non-green baseline -> exit 2 control_not_applied reason=baseline_not_green"
else
  fail "mutation-control: red baseline -> exit 2 (got rc=${mc_rc}, out=$(cat "${FIXTURE}/mc-baseline.out"))"
fi

cat > "${MC_REPO}/suite.sh" <<'EOF'
#!/usr/bin/env bash
echo "PASS: suite ignores lib/target.sh entirely"
exit 0
EOF
( cd "${MC_REPO}" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m greenbase-nocov )
( cd "${MC_REPO}" && LEADV2_LANE_START_SHA="${MC_BASE_SHA}" bash "${MUT_CTL_SH}" suite.sh lib/target.sh 's/ + / - /' "${MC_TASK_DIR}" ) \
  >"${FIXTURE}/mc-survived.out" 2>&1
mc_rc=$?
if [[ ${mc_rc} -eq 1 ]] && grep -q 'mutant_survived' "${FIXTURE}/mc-survived.out"; then
  pass "mutation-control: suite does not cover the mutated file -> exit 1 mutant_survived"
else
  fail "mutation-control: uncovered mutation -> exit 1 (got rc=${mc_rc}, out=$(cat "${FIXTURE}/mc-survived.out"))"
fi

# ---------------------------------------------------------------------------
# Wiring proof — the gate must refuse BEFORE the LEADV2_REVIEW_ENGINE branch
# splits, for both engine=unset (production default) and engine=1. Extracted
# by anchor comment (not a hardcoded line range) so this stays correct across
# reformatting; both anchors are asserted present first.
# ---------------------------------------------------------------------------
if grep -q '# WORKER-DOD-GATE-01: deterministic bash DoD gate, called HERE' "${DISPATCH_SH}" \
   && grep -q '# ONE-PATH-EVERYWHERE-01: when LEADV2_REVIEW_ENGINE=1' "${DISPATCH_SH}"; then
  START_LINE="$(grep -n '# WORKER-DOD-GATE-01: deterministic bash DoD gate, called HERE' "${DISPATCH_SH}" | head -1 | cut -d: -f1)"
  END_LINE="$(grep -n '# ONE-PATH-EVERYWHERE-01: when LEADV2_REVIEW_ENGINE=1' "${DISPATCH_SH}" | head -1 | cut -d: -f1)"
  END_LINE=$((END_LINE - 1))
  BLOCK_FILE="${FIXTURE}/dod-block.sh"
  sed -n "${START_LINE},${END_LINE}p" "${DISPATCH_SH}" > "${BLOCK_FILE}"

  WT_REPO="${FIXTURE}/wire-repo"
  mkdir -p "${WT_REPO}/docs/handoff/WIRETEST"
  cat > "${WT_REPO}/docs/handoff/WIRETEST/brief.md" <<'EOF'
Nothing further needed from the worker for this fixture.
EOF
  cat > "${FIXTURE}/wire.diff" <<'EOF'
--- a/docs/leadv2/active.yaml
+++ b/docs/leadv2/active.yaml
@@
-x
+y
EOF

  run_wire_case() {
    local engine="$1" label="$2"
    local harness="${FIXTURE}/wire-harness-${label}.sh"
    {
      printf '#!/usr/bin/env bash\nset -uo pipefail\n'
      printf 'ROOT=%q\n' "${WT_REPO}"
      printf 'SCRIPT_DIR=%q\n' "${PLUGIN_SCRIPTS}"
      printf 'FOUNDER_TASK_ID=WIRETEST\n'
      printf 'HANDOFF=%q\n' "${WT_REPO}/docs/handoff/WIRETEST"
      printf 'TASK=WIRETEST\n'
      printf 'diff_file=%q\n' "${FIXTURE}/wire.diff"
      printf '_dl_note() { printf "DL_NOTE %%s\\n" "$*"; }\n'
      printf '_stamp_review_terminal() { printf "STAMP %%s\\n" "$1"; }\n'
      printf 'emit() { printf "EMIT %%s\\n" "$*"; }\n'
      cat "${BLOCK_FILE}"
      printf 'printf "REACHED_ENGINE_SPLIT\\n"\n'
    } > "${harness}"
    LEADV2_REVIEW_ENGINE="${engine}" bash "${harness}"
  }

  wire_out_unset="$(run_wire_case '' unset 2>&1)"; wire_rc_unset=$?
  wire_out_e1="$(run_wire_case '1' e1 2>&1)"; wire_rc_e1=$?

  if [[ ${wire_rc_unset} -eq 7 ]] \
     && printf '%s' "${wire_out_unset}" | grep -q 'EMIT decision review_gate task=WIRETEST status=fail round=0 reason=dod_runtime_state_in_diff' \
     && ! printf '%s' "${wire_out_unset}" | grep -q 'REACHED_ENGINE_SPLIT' \
     && grep -q 'status: fail' "${WT_REPO}/docs/handoff/WIRETEST/review-gate.md" \
     && grep -q 'reason: dod_runtime_state_in_diff' "${WT_REPO}/docs/handoff/WIRETEST/review-gate.md"; then
    pass "wiring: LEADV2_REVIEW_ENGINE unset (production default) -> exit 7 before engine split, review-gate.md written"
  else
    fail "wiring: engine-unset case (rc=${wire_rc_unset}, out=${wire_out_unset})"
  fi

  if [[ ${wire_rc_e1} -eq 7 ]] \
     && printf '%s' "${wire_out_e1}" | grep -q 'EMIT decision review_gate task=WIRETEST status=fail round=0 reason=dod_runtime_state_in_diff' \
     && ! printf '%s' "${wire_out_e1}" | grep -q 'REACHED_ENGINE_SPLIT'; then
    pass "wiring: LEADV2_REVIEW_ENGINE=1 -> identical refusal, exit 7 before engine split"
  else
    fail "wiring: engine=1 case (rc=${wire_rc_e1}, out=${wire_out_e1})"
  fi
else
  fail "wiring: anchor comments missing from leadv2-dispatch-product-close.sh — cannot extract gate block"
fi

printf -- '[TEST] %s: %d passed, %d failed\n' "test-worker-dod-gate" "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
