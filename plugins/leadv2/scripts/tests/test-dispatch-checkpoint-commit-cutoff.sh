#!/usr/bin/env bash
# test-dispatch-checkpoint-commit-cutoff.sh — STOP-GATE-CHECKPOINT-DEDUP-01 regression.
#
# _dispatch_checkpointed_cutoff (leadv2-dispatch-code.sh) used to accept ONLY the
# model-written docs/handoff/dispatch-<sig8>/CHECKPOINT.md note as proof a dead worker's
# row was checkpointed-and-cut-off. That note is frequently absent (the model does not
# always write it -- leadv2-turncap-checkpoint-commit.sh:22) even though the MACHINE-
# written STOP-GATE checkpoint commit (`wip(<sig8>): auto-checkpoint on worker exit
# (STOP-GATE)`, pc_stop_gate_autocommit in leadv2-dispatch-product-close.sh) always lands
# in the lane's own worktree. This suite proves the new commit-based OR path, without
# regressing the note path, the completion-sentinel guard, or fail-closed behavior on a
# missing worktree.
#
# Technique: this file sources the REAL leadv2-dispatch-code.sh function bodies (never a
# hand-reimplemented copy) by truncating the shipped script just before its trailing
# `case "$1" in ...` dispatch block (so nothing actually dispatches/spawns), and sourcing
# that truncation FROM WITHIN scripts/ itself (a sibling temp file, cleaned up on exit) --
# the file's own top-of-script `source "${SCRIPT_DIR}/leadv2-*.sh"` lines resolve
# SCRIPT_DIR from BASH_SOURCE, so the truncation must live next to its siblings, not in
# a scratch dir. This is exactly the shape test-leadv2-dispatch-outcome-ledger.sh's own
# header describes wanting ("never a hand-reimplemented copy of the decision logic"), one
# level more surgical: unit-level function calls instead of a full CLI subprocess per case,
# because the behavior under test is pure post-liveness decision logic, not spawn/poll.
#
# Run: bash plugins/leadv2/scripts/tests/test-dispatch-checkpoint-commit-cutoff.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
source "${SCRIPTS_DIR}/leadv2-temp.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

RUN_ID="dispatch-ckpt-cutoff-$$-$(date +%s 2>/dev/null || echo 0)"
TMPDIR_ROOT="$(lv2_mktemp_dir "${RUN_ID}")"
ROOT="${TMPDIR_ROOT}/repo"
LANE="${TMPDIR_ROOT}/lane"
LANE_STUB="${TMPDIR_ROOT}/fake-lane-worktree.sh"

# Truncation lives beside its siblings in SCRIPTS_DIR (SCRIPT_DIR-relative `source`
# lines inside leadv2-dispatch-code.sh require this) -- a private dotfile, removed on
# exit alongside the rest of the fixture.
FUNCS_SH="${SCRIPTS_DIR}/.test-dispatch-ckpt-cutoff-funcs.$$.sh"
cleanup() { rm -rf "${TMPDIR_ROOT}"; rm -f "${FUNCS_SH}"; }
trap cleanup EXIT

CUT_LINE="$(grep -n '^# .. dispatch ..*$' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
[[ -z "${CUT_LINE}" ]] && CUT_LINE="$(grep -n 'dispatch ─' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
if [[ -z "${CUT_LINE}" ]]; then
  echo "[TEST] SETUP FAILED: could not locate trailing dispatch-case marker in ${DISPATCH_SH}" >&2
  exit 1
fi
head -n "$((CUT_LINE - 1))" "${DISPATCH_SH}" > "${FUNCS_SH}"

mkdir -p "${ROOT}/.claude/ref"
( cd "${ROOT}" && git init -q && git config user.email t@e.com && git config user.name t \
  && printf 'router:\n  glm_policy:\n    sonnet_exceptions: []\n    opus_only_mission_kinds: []\n    codex_fitting_mission_kinds: []\n' > .claude/ref/leadv2-routing.yaml \
  && : > seed && git add seed .claude/ref/leadv2-routing.yaml && git commit -qm seed )

mkdir -p "${LANE}"
( cd "${LANE}" && git init -q && git config user.email t@e.com && git config user.name t \
  && : > seed && git add seed && git commit -qm seed )

# Fake leadv2-lane-worktree.sh: `path-of <ref>` prints $LV2_TEST_LANE_PATH when ref ==
# $LV2_TEST_LANE_SIG8, empty otherwise -- mirrors the real script's one-arg contract
# without depending on its actual lane-naming/registry internals.
cat > "${LANE_STUB}" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  path-of)
    shift
    if [[ "${1:-}" == "${LV2_TEST_LANE_SIG8:-}" ]]; then
      printf '%s' "${LV2_TEST_LANE_PATH:-}"
    fi
    ;;
esac
exit 0
EOS
chmod +x "${LANE_STUB}"

# Runs the real _dispatch_checkpointed_cutoff in a fresh subshell so each case starts
# clean (no leaked _DISPATCH_CHECKPOINT_SHA / CHECKPOINT_CUTOFF from a prior case).
# Prints "<rc> <sha>" on stdout.
_run_cutoff() {  # <sig8> <created_epoch> <lane_sig8_for_stub> <lane_path_for_stub>
  local sig8="$1" created="$2" stub_sig8="$3" stub_path="$4"
  ( set -uo pipefail
    CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}" \
    LEADV2_DISPATCH_LANE_WORKTREE_BIN="${LANE_STUB}" \
    LV2_TEST_LANE_SIG8="${stub_sig8}" LV2_TEST_LANE_PATH="${stub_path}" \
    bash -c '
      cd "'"${ROOT}"'" || exit 9
      source "'"${FUNCS_SH}"'"
      _dispatch_checkpointed_cutoff "'"${sig8}"'" "'"${created}"'"
      rc=$?
      printf "%s %s\n" "${rc}" "${_DISPATCH_CHECKPOINT_SHA:-}"
    '
  )
}

_write_checkpoint_commit() {  # <lane_dir> <sig8> <committer_epoch>
  local lane="$1" sig8="$2" epoch="$3"
  ( cd "${lane}" && printf 'partial work\n' >> partial.txt && git add partial.txt \
    && GIT_AUTHOR_DATE="@${epoch} +0000" GIT_COMMITTER_DATE="@${epoch} +0000" \
       git commit -q -m "wip(${sig8}): auto-checkpoint on worker exit (STOP-GATE)" )
}

NOW="$(date +%s)"

# ── 1. dead row + checkpoint COMMIT newer than created -> freed ─────────────────────
SIG1="aaaaaaaa"
LANE1="${TMPDIR_ROOT}/lane1"; mkdir -p "${LANE1}"
( cd "${LANE1}" && git init -q && git config user.email t@e.com && git config user.name t && : > seed && git add seed && git commit -qm seed )
_write_checkpoint_commit "${LANE1}" "${SIG1}" "$((NOW - 10))"
out1="$(_run_cutoff "${SIG1}" "$((NOW - 100))" "${SIG1}" "${LANE1}")"
rc1="${out1%% *}"; sha1="${out1#* }"
if [[ "${rc1}" == "0" && -n "${sha1}" ]]; then
  ok "1: checkpoint commit newer than created frees the row (sha=${sha1})"
else
  bad "1: expected rc=0 with sha, got '${out1}'"
fi

# ── 2. dead row + checkpoint COMMIT older than created -> still blocked ─────────────
SIG2="bbbbbbbb"
LANE2="${TMPDIR_ROOT}/lane2"; mkdir -p "${LANE2}"
( cd "${LANE2}" && git init -q && git config user.email t@e.com && git config user.name t && : > seed && git add seed && git commit -qm seed )
_write_checkpoint_commit "${LANE2}" "${SIG2}" "$((NOW - 1000))"
out2="$(_run_cutoff "${SIG2}" "${NOW}" "${SIG2}" "${LANE2}")"
rc2="${out2%% *}"
if [[ "${rc2}" != "0" ]]; then
  ok "2: checkpoint commit older than created (stale attempt) stays blocked"
else
  bad "2: expected non-zero rc, got '${out2}'"
fi

# ── 3. dead row + phase8-passed.flag present -> still blocked (sentinel wins) ───────
SIG3="cccccccc"
LANE3="${TMPDIR_ROOT}/lane3"; mkdir -p "${LANE3}"
( cd "${LANE3}" && git init -q && git config user.email t@e.com && git config user.name t && : > seed && git add seed && git commit -qm seed )
_write_checkpoint_commit "${LANE3}" "${SIG3}" "$((NOW - 10))"
mkdir -p "${ROOT}/docs/handoff/dispatch-${SIG3}"
: > "${ROOT}/docs/handoff/dispatch-${SIG3}/phase8-passed.flag"
out3="$(_run_cutoff "${SIG3}" "$((NOW - 100))" "${SIG3}" "${LANE3}")"
rc3="${out3%% *}"
if [[ "${rc3}" != "0" ]]; then
  ok "3: phase8-passed.flag present stays blocked despite a fresh checkpoint commit"
else
  bad "3: expected non-zero rc, got '${out3}'"
fi

# ── 4. existing NOTE-based path still frees a row (no regression) ───────────────────
SIG4="dddddddd"
mkdir -p "${ROOT}/docs/handoff/dispatch-${SIG4}"
: > "${ROOT}/docs/handoff/dispatch-${SIG4}/CHECKPOINT.md"
out4="$(_run_cutoff "${SIG4}" "$((NOW - 100))" "" "")"
rc4="${out4%% *}"; sha4="${out4#* }"
if [[ "${rc4}" == "0" && -z "${sha4}" ]]; then
  ok "4: model-written CHECKPOINT.md note still frees the row (no commit sha attached)"
else
  bad "4: expected rc=0 with empty sha, got '${out4}'"
fi

# ── 5. missing/unreadable worktree -> still blocked (fail-closed, no cwd fallback) ──
# ROOT (PROJECT_ROOT / this subshell's cwd) itself carries a fresh matching STOP-GATE
# commit for SIG5 -- if the guard ever silently fell back to searching cwd/PROJECT_ROOT
# when lane resolution fails, this would wrongly free the row. It must not: the function
# is scoped to the LANE worktree only.
SIG5="eeeeeeee"
_write_checkpoint_commit "${ROOT}" "${SIG5}" "$((NOW - 10))"
out5="$(_run_cutoff "${SIG5}" "$((NOW - 100))" "${SIG5}" "${TMPDIR_ROOT}/does-not-exist")"
rc5="${out5%% *}"
if [[ "${rc5}" != "0" ]]; then
  ok "5: missing lane worktree fails closed, no fallback to PROJECT_ROOT's own commit"
else
  bad "5: expected non-zero rc, got '${out5}'"
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[[ ${FAIL} -eq 0 ]]
