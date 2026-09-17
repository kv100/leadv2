#!/usr/bin/env bash
# REVIEW-DIFF-IS-SCOPED-TO-THE-DECLARED-WRITE-SET-01: executable guard for
# plugins/leadv2/scripts/leadv2-review-run.sh's committed-vs-declared diff
# augmentation (_review_augment_diff_to_committed).
#
# Defect measured on lane 18dfa6f6 (2026-09-15): the caller builds the review
# diff from the lane's DECLARED --writes pathspec, the lane had also COMMITTED
# a file outside that set, and the reviewer honestly failed the round with a
# High about a file "missing ... does not exist in the repository" — a verdict
# about a repository state that did not exist. The engine must re-point
# reviewers at an augmented sibling diff that (a) contains every committed
# file the supplied diff failed to show and (b) NAMES the difference, while
# never letting working-tree churn the lane did not commit leak in.
#
# run-all-triggers: leadv2-review-run
#
# SUITE-SELECTION-COVERS-140-OF-390-01: the trigger is the production file
# this suite guards, so `run-all.sh --scope changed` selects it whenever
# leadv2-review-run.sh changes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="${SCRIPT_DIR}/../leadv2-review-run.sh"
PASS=0
FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

bash -n "${ENGINE}" || exit 1
bash -n "${SCRIPT_DIR}/test-review-diff-scope.sh" || exit 1

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

LOG="${TMP}/calls.log"
ROUTING="${TMP}/routing.yaml"
cat > "${ROUTING}" <<'YAML'
router:
  glm_policy:
    protected_path_patterns:
      - "secure/*"
YAML

cat > "${TMP}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:")
print("refusal=")
PY
chmod +x "${TMP}/resolver.py"

# The reviewer emulator reproduces the 18dfa6f6 shape honestly: it can only
# see the diff file its mission names. When that diff REFERENCES the refresh
# script (the call site in the declared file) but never SHOWS the file itself
# (no +++ b/ hunk), it concludes the executable does not exist — the exact
# false High the lane measured. When the diff shows the file, it passes.
cat > "${TMP}/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""; mission=""; task_id=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; --mission-file) mission="$2"; shift 2 ;; --task-id) task_id="$2"; shift 2 ;; *) shift ;; esac; done
printf '%s:%s\n' "$role" "$task_id" >> "${CALL_LOG}"
[[ -f "${mission}" ]] && cp "$mission" "${MISSION_CAPTURE}"
if [[ "$role" == hack-detect || "$(head -n 1 "$mission" 2>/dev/null)" == 'Run hack-detection on the diff at '* ]]; then
  exit 0
fi
diff_path="$(sed -n 's/^Review ONLY the diff at \(.*\)\. You are independent\.*/\1/p' "$mission" | head -1)"
shown="$(cat "${diff_path}" 2>/dev/null || true)"
if printf '%s' "${shown}" | grep -q 'leadv2-ratelimit-refresh-if-stale\.sh' \
   && ! printf '%s' "${shown}" | grep -q '^+++ b/leadv2-ratelimit-refresh-if-stale\.sh$'; then
  printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=0\n'
  printf 'FINDING: severity=High file=leadv2-ratelimit-refresh-if-stale.sh line=1 dimension=correctness desc=default refresh executable is missing, does not exist in the repository\n'
else
  printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
fi
SH
chmod +x "${TMP}/architect.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${TMP}/dispatch.sh"; chmod +x "${TMP}/dispatch.sh"

# build_lane_repo <dest>: a base commit, then one lane commit that touches the
# DECLARED file (leadv2-quota-status.sh, whose change references the refresh
# executable) and also commits the UNDECLARED file itself. Prints the base sha.
build_lane_repo() { # <dest>
  local dest="$1"
  git init -q "${dest}"
  git -C "${dest}" config user.email lane@example.test
  git -C "${dest}" config user.name lane
  mkdir -p "${dest}/plugins/leadv2/scripts"
  printf 'base\n' > "${dest}/base.txt"
  git -C "${dest}" add base.txt
  git -C "${dest}" commit -qm base
  git -C "${dest}" rev-parse HEAD
}
commit_lane_pair() { # <dest>
  local dest="$1"
  cat > "${dest}/plugins/leadv2/scripts/leadv2-quota-status.sh" <<'SH'
#!/usr/bin/env bash
# default refresh executable hook
exec "$(dirname "$0")/leadv2-ratelimit-refresh-if-stale.sh" "$@"
SH
  cat > "${dest}/plugins/leadv2/scripts/leadv2-ratelimit-refresh-if-stale.sh" <<'SH'
#!/usr/bin/env bash
echo refreshed
SH
  git -C "${dest}" add plugins/leadv2/scripts
  git -C "${dest}" commit -qm "lane work: quota status + undeclared refresh script"
}

run_review() { # <stdout-file> <stderr-file> <handoff> <diff> <task> [env assignments...]
  local out="$1" err="$2" handoff="$3" diff="$4" task="$5"; shift 5
  mkdir -p "${handoff}"
  env "$@" CALL_LOG="${LOG}" MISSION_CAPTURE="${TMP}/mission-${task}.md" \
    LEADV2_ROUTING_YAML="${ROUTING}" \
    LEADV2_GLM_POLICY_RESOLVER="${TMP}/resolver.py" \
    LEADV2_DISPATCH_ARCHITECT_BIN="${TMP}/architect.sh" \
    LEADV2_DISPATCH_BIN="${TMP}/dispatch.sh" \
    bash "${ENGINE}" --task "${task}" --root "${REPO}" --handoff "${handoff}" \
      --diff "${diff}" --author glm > "${out}" 2> "${err}"
}

R1="${TMP}/r1"; mkdir -p "${R1}"
REPO="${R1}/repo"
BASE="$(build_lane_repo "${REPO}")"
commit_lane_pair "${REPO}"
# The caller's diff is built from the lane's DECLARED writes only — exactly
# what a dispatch lane hands this engine (LANE-START-SHA-01 path-filtered diff).
H1="${R1}/handoff/dispatch-diffscope1"
mkdir -p "${H1}"
D1="${H1}/build-attempt-1.diff"
git -C "${REPO}" diff "${BASE}" HEAD -- plugins/leadv2/scripts/leadv2-quota-status.sh > "${D1}"
cp "${D1}" "${R1}/caller.diff.before"
O1="${R1}/engine.out"; E1="${R1}/engine.err"
run_review "${O1}" "${E1}" "${H1}" "${D1}" diffscope1 \
  LEADV2_DISPATCH_LANE_WRITES=plugins/leadv2/scripts/leadv2-quota-status.sh \
  LEADV2_LANE_START_SHA="${BASE}"; rc1=$?

grep -q '^status: pass$' "${H1}/review-gate.md" 2>/dev/null \
  && pass "R1 gate: committed-but-undeclared file reaches the reviewer (status: pass, no false High)" \
  || fail "R1 gate: status=$(head -2 "${H1}/review-gate.md" 2>/dev/null | tr '\n' ' ') rc=${rc1}"
AUG1="${H1}/build-attempt-1.review.diff"
if [[ -f "${AUG1}" ]] \
   && grep -q '^+++ b/plugins/leadv2/scripts/leadv2-ratelimit-refresh-if-stale\.sh$' "${AUG1}" \
   && grep -q 'REVIEW-DIFF-IS-SCOPED-TO-THE-DECLARED-WRITE-SET-01' "${AUG1}" \
   && grep -q 'Appended committed files:' "${AUG1}"; then
  pass "R1 augmented sibling shows the undeclared file and names the difference"
else
  fail "R1 augmented sibling missing or incomplete: $(ls "${H1}" 2>/dev/null | tr '\n' ' ')"
fi
grep -q 'leadv2-ratelimit-refresh-if-stale' "${AUG1:-/dev/null}" \
  && grep -q 'build-attempt-1\.review\.diff' "${TMP}/mission-diffscope1.md" 2>/dev/null \
  && pass "R1 reviewer mission points at the augmented diff" \
  || fail "R1 reviewer mission does not point at the augmented diff"
cmp -s "${D1}" "${R1}/caller.diff.before" \
  && pass "R1 caller-supplied diff artifact left byte-identical" \
  || fail "R1 caller-supplied diff artifact was modified in place"
grep -q 'review_diff_scope task=diffscope1 base=[0-9a-f]* appended=1 files=plugins/leadv2/scripts/leadv2-ratelimit-refresh-if-stale.sh' "${E1}" \
  && pass "R1 engine emits the review_diff_scope decision naming the file" \
  || fail "R1 review_diff_scope line: $(grep 'review_diff_scope' "${E1}" || echo none)"

# R2 — scoping is preserved: churn the lane did NOT commit (working-tree edit
# of a tracked file + an untracked file) must never reach the reviewer.
R2="${TMP}/r2"; mkdir -p "${R2}"
REPO="${R2}/repo"
BASE="$(build_lane_repo "${REPO}")"
commit_lane_pair "${REPO}"
printf 'uncommitted edit\n' >> "${REPO}/base.txt"
printf 'echo untracked\n' > "${REPO}/plugins/leadv2/scripts/zzz-untracked-churn.sh"
H2="${R2}/handoff/dispatch-diffscope2"
mkdir -p "${H2}"
D2="${H2}/build-attempt-1.diff"
git -C "${REPO}" diff "${BASE}" HEAD -- plugins/leadv2/scripts/leadv2-quota-status.sh > "${D2}"
O2="${R2}/engine.out"; E2="${R2}/engine.err"
run_review "${O2}" "${E2}" "${H2}" "${D2}" diffscope2 \
  LEADV2_DISPATCH_LANE_WRITES=plugins/leadv2/scripts/leadv2-quota-status.sh \
  LEADV2_LANE_START_SHA="${BASE}"; rc2=$?

grep -q '^status: pass$' "${H2}/review-gate.md" 2>/dev/null \
  && pass "R2 gate: uncommitted churn does not block the round" \
  || fail "R2 gate: status=$(head -2 "${H2}/review-gate.md" 2>/dev/null | tr '\n' ' ') rc=${rc2}"
if [[ -f "${H2}/build-attempt-1.review.diff" ]] \
   && ! grep -q 'zzz-untracked-churn' "${H2}/build-attempt-1.review.diff" \
   && ! grep -q '^+++ b/base\.txt$' "${H2}/build-attempt-1.review.diff"; then
  pass "R2 augmented diff shows committed work only — no working-tree churn leaked in"
else
  fail "R2 scoping leak: $(grep -E 'zzz-untracked-churn|\+\+\+ b/base\.txt' "${H2}/build-attempt-1.review.diff" 2>/dev/null | tr '\n' ' ')"
fi

# R3 — no gap, no augmentation: when the supplied diff already shows every
# committed file, no sibling is created and the mission keeps the original path.
R3="${TMP}/r3"; mkdir -p "${R3}"
REPO="${R3}/repo"
BASE="$(build_lane_repo "${REPO}")"
mkdir -p "${REPO}/plugins/leadv2/scripts"
printf 'only declared work\n' > "${REPO}/plugins/leadv2/scripts/leadv2-quota-status.sh"
git -C "${REPO}" add plugins/leadv2/scripts
git -C "${REPO}" commit -qm "lane work: declared file only"
H3="${R3}/handoff/dispatch-diffscope3"
mkdir -p "${H3}"
D3="${H3}/build-attempt-1.diff"
git -C "${REPO}" diff "${BASE}" HEAD -- plugins/leadv2/scripts/leadv2-quota-status.sh > "${D3}"
O3="${R3}/engine.out"; E3="${R3}/engine.err"
run_review "${O3}" "${E3}" "${H3}" "${D3}" diffscope3 \
  LEADV2_DISPATCH_LANE_WRITES=plugins/leadv2/scripts/leadv2-quota-status.sh \
  LEADV2_LANE_START_SHA="${BASE}"; rc3=$?

[[ -f "${H3}/build-attempt-1.review.diff" ]] \
  && fail "R3 no-op: sibling created despite no gap" \
  || pass "R3 no-op: no augmented sibling when the diff covers every committed file"
grep -q 'build-attempt-1\.diff' "${TMP}/mission-diffscope3.md" 2>/dev/null \
  && ! grep -q 'review_diff_scope' "${E3}" \
  && pass "R3 mission keeps the caller's diff path and no scope line is emitted" \
  || fail "R3 no-op contract broken"

printf '\nreview-diff-scope: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]] || exit 1
exit 0
