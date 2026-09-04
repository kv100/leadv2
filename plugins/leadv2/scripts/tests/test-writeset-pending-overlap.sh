#!/usr/bin/env bash
# test-writeset-pending-overlap.sh — WRITESET-PENDING-BLOCKS-WITHOUT-ANY-OVERLAP-01.
#
# A write-less incumbent row inside its LEADV2_WRITESET_PENDING_WINDOW_SEC
# used to refuse every concurrent dispatch (rc=5, reason=pending_resolution)
# BEFORE any path comparison — two lanes with zero files in common both
# blocked. The defect was not the fail-closed rule (an unknown set cannot be
# proven disjoint, and the window closes a real two-lane declaration race);
# it was that rows with no write set existed ROUTINELY. This suite proves the
# repair at all four layers, against the REAL registry / fanout writer /
# dispatch refusal parser:
#   1. the routine case stops firing: a creator that can know its write set
#      (fanout's pid=null dispatch reservation, which read the lane contract
#      only AFTER reserving before this lane) now declares it on the
#      reservation row — a later candidate with a DISJOINT declared set
#      proceeds (rc=0) where it previously ate a blanket pending refusal;
#   2. the race case still refuses AND says why: a genuinely write-less row
#      records writes_reason=<why>, the registry's pending line carries it,
#      and the real _emit_writeset_refusal surfaces it end-to-end;
#      a legacy row without the key says undeclared;
#   3. the pending window's clock survives recreation: first_seen_at is
#      carried across the remove+append a pid=None placeholder suffers when
#      dispatch re-registers, so a row re-created every couple of minutes
#      can no longer stay pending forever (the window was unreachable);
#   4. true positives preserved: declared sets that genuinely overlap still
#      refuse with paths=.
# Negative controls live in mutation-control/ (leadv2-mutation-control.sh
# artifacts): reverting _lv2_ws_pending to started_at redden case 3,
# stripping the fanout declaration redden case 1.
#
# Technique: same as test-writeset-refusal-names-blocker.sh — source the REAL
# leadv2-dispatch-code.sh function bodies by truncating just before its
# trailing dispatch-case block, extract _fanout_register_session verbatim by
# function bounds, and drive the REAL registry against a scratch
# LEADV2_STATE_ROOT so every assertion runs on the wire formats these
# scripts actually emit today.
#
# Run: bash plugins/leadv2/scripts/tests/test-writeset-pending-overlap.sh
# run-all-triggers: leadv2-active-registry.sh leadv2-fanout.sh leadv2-dispatch-code.sh

set -uo pipefail

# Ambient-harness hygiene (measured 2026-09-04 on the sibling suite): a
# hostile ambient LEADV2_WRITESET_PENDING_WINDOW_SEC=1 (leaked by a hook so
# this lane's own dispatch is not blocked) silently expires every incumbent;
# the burn governor reads the host's real history.db and reds on `exit 6`.
# Pinned per-case below where a non-default window is the point.
export LEADV2_BURN_GOVERNOR=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH_SH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
REGISTRY_SH="${SCRIPTS_DIR}/leadv2-active-registry.sh"
FANOUT_SH="${SCRIPTS_DIR}/leadv2-fanout.sh"
source "${SCRIPTS_DIR}/leadv2-temp.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

RUN_ID="ws-pend-$$-$(date +%s 2>/dev/null || echo 0)"
TMPDIR_ROOT="$(lv2_mktemp_dir "${RUN_ID}")"

# _emit_writeset_refusal comes from the REAL dispatch-code.sh, truncated
# before the trailing dispatch-case block (nothing dispatches/spawns).
FUNCS_SH="${SCRIPTS_DIR}/.test-ws-pend-funcs.$$.sh"
CUT_LINE="$(grep -n '^# ── dispatch ──' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
if [[ -z "${CUT_LINE}" ]]; then
  CUT_LINE="$(grep -n 'dispatch ─' "${DISPATCH_SH}" | tail -1 | cut -d: -f1)"
fi
if [[ -z "${CUT_LINE}" ]]; then
  echo "[TEST] SETUP FAILED: no truncation marker in ${DISPATCH_SH}" >&2
  exit 1
fi
head -n "$((CUT_LINE - 1))" "${DISPATCH_SH}" > "${FUNCS_SH}"

# _fanout_register_session verbatim, by function bounds (never a copy).
FAN_START="$(grep -n '^_fanout_register_session() {' "${FANOUT_SH}" | cut -d: -f1)"
FAN_END="$(awk -v s="${FAN_START}" 'NR>s && /^}$/ {print NR; exit}' "${FANOUT_SH}")"
if [[ -z "${FAN_START}" || -z "${FAN_END}" ]]; then
  echo "[TEST] SETUP FAILED: cannot bound _fanout_register_session in ${FANOUT_SH}" >&2
  exit 1
fi
FANOUT_FUNCS_SH="${SCRIPTS_DIR}/.test-ws-pend-fanout.$$.sh"
sed -n "${FAN_START},${FAN_END}p" "${FANOUT_SH}" > "${FANOUT_FUNCS_SH}"

cleanup() { rm -rf "${TMPDIR_ROOT}"; rm -f "${FUNCS_SH}" "${FANOUT_FUNCS_SH}"; }
trap cleanup EXIT

# _scratch_root <label> — fresh git repo the registry can own.
_scratch_root() {
  local r="${TMPDIR_ROOT}/c-$1"
  mkdir -p "${r}"
  ( cd "${r}" && git init -q && git config user.email t@e.com && git config user.name t \
    && : > seed && git add seed && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "${r}"
}

# ════ 1. routine case: a creator that can know, now declares ══════════════
out1="$( bash -s "${REGISTRY_SH}" "${FANOUT_FUNCS_SH}" "${TMPDIR_ROOT}" <<'EOF'
set -uo pipefail
source "$1"; set +e
FANFUNCS="$2"
root="$3/c1"; mkdir -p "$root"
export LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" LEADV2_BURN_GOVERNOR=0
export LEADV2_WRITESET_PENDING_WINDOW_SEC=900
git -C "$root" init -q && git -C "$root" config user.email t@e.com && git -C "$root" config user.name t
# The taught creator: fanout's dispatch reservation, declaring the write set
# its task row carries (16th arg) instead of landing write-less.
source "${FANFUNCS}"
PROJECT_ROOT="$root"
_fanout_register_session "WSO-INC" Standard "null" "dispatch-code: WSO-INC (reserving)" "true" "true" \
  "dispatch-code" "" "" "" "" "" "" "" "" "res/a.txt" "" >/dev/null 2>&1
echo "reserve_rc=$?"
python3 - "$root/docs/leadv2/active.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
row = next((s for s in d["sessions"] if s["task_id"] == "WSO-INC"), {})
print("row_writes=%s" % row.get("writes"))
print("row_reason=%s" % row.get("writes_reason"))
PY
# The dispatch that previously refused (blanket pending) now PROCEEDS:
# a disjoint declared candidate is compared on paths, not blanket-refused.
leadv2_active_register "WSO-CAND" Standard "$root" wt-cand false "" "" "cand/b.txt" >/dev/null 2>/dev/null
echo "cand_rc=$?"
EOF
)" || true
if printf '%s' "${out1}" | grep -q 'reserve_rc=0' \
  && printf '%s' "${out1}" | grep -q 'row_writes=res/a.txt' \
  && printf '%s' "${out1}" | grep -q 'row_reason=None' \
  && printf '%s' "${out1}" | grep -q 'cand_rc=0'; then
  ok "1: fanout reservation declares res/a.txt; disjoint declared candidate proceeds rc=0 (was blanket pending-refused)"
else
  bad "1: out=[${out1}]"
fi

# ════ 2. race case still refuses, and now says why ════════════════════════
ws_case2() {
  local inc_reason="$1"
  bash -s "${REGISTRY_SH}" "${FUNCS_SH}" "${TMPDIR_ROOT}" "WSO-PEND-${inc_reason}" "${inc_reason}" <<'EOF'
set -uo pipefail
source "$1"; set +e
FUNCS="$2"; base="$3"; INC="$4"; REASON="$5"
root="${base}/c2-${INC}"; mkdir -p "$root"
export LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" LEADV2_BURN_GOVERNOR=0
export LEADV2_WRITESET_PENDING_WINDOW_SEC=900
git -C "$root" init -q && git -C "$root" config user.email t@e.com && git -C "$root" config user.name t
leadv2_active_register "${INC}" Standard "$root" wt false "" "" "" "${REASON}" >/dev/null 2>&1
reg_err="$(LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" \
  leadv2_active_register "WSO-CAND" Standard "$root" wt-cand false "" "" "cand/b.txt" 2>&1 >/dev/null)"
echo "reg_rc=$?"
echo "$reg_err" | grep -o 'reason=pending_resolution writes_reason=[a-z_]*' | head -1
source "${FUNCS}"; set +e
_emit_writeset_refusal "WSOTEST2" "cand/b.txt" "${reg_err}" "FOUNDER-TASK" 2>&1
EOF
}
out2="$(ws_case2 prepass_pending)" || true
line2="$(printf '%s\n' "${out2}" | grep -m1 'dispatch_refused')"
if printf '%s' "${out2}" | grep -q 'reg_rc=5' \
  && printf '%s' "${out2}" | grep -q 'reason=pending_resolution writes_reason=prepass_pending' \
  && printf '%s' "${line2}" | grep -q 'reason=writeset_pending task=WSOTEST2 blocked_by=WSO-PEND-prepass_pending' \
  && printf '%s' "${line2}" | grep -q 'writes_reason=prepass_pending'; then
  ok "2: genuinely write-less incumbent still refuses rc=5; registry AND dispatch refusal both carry writes_reason=prepass_pending"
else
  bad "2: line=[${line2:-<none>}] out=[${out2}]"
fi
out2b="$(ws_case2 '-')" || true
if printf '%s' "${out2b}" | grep -q 'reg_rc=5' \
  && printf '%s' "${out2b}" | grep -q 'writes_reason=undeclared'; then
  ok "2b: legacy row without writes_reason says undeclared in both refusal layers"
else
  bad "2b: out=[${out2b}]"
fi

# ════ 3. the window's clock survives recreation (first_seen_at) ═══════════
out3="$( bash -s "${REGISTRY_SH}" "${FANOUT_FUNCS_SH}" "${TMPDIR_ROOT}" <<'EOF'
set -uo pipefail
source "$1"; set +e
FANFUNCS="$2"
root="$3/c3"; mkdir -p "$root"
# Window pinned SHORT but with a WIDE margin (5s window, 6s sleep): the
# mutation control M1 measured that a 1s window is dilutable — one slow
# python spawn between the recreation and the candidate expires it even
# under the pre-fix started_at clock, and the mutant survives. With 5s the
# pre-fix clock (age ~0.3s at the candidate) still blanket-refuses while
# the fix (age ~6s) has already expired.
export LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" LEADV2_BURN_GOVERNOR=0
export LEADV2_WRITESET_PENDING_WINDOW_SEC=5
git -C "$root" init -q && git -C "$root" config user.email t@e.com && git -C "$root" config user.name t
source "${FANFUNCS}"
PROJECT_ROOT="$root"
# t0: pid=null reservation declares res/a.txt (first_seen_at starts here).
_fanout_register_session "WSO-REINC" Standard "null" "reserving" "true" "true" \
  "dispatch-code" "" "" "" "" "" "" "" "" "res/a.txt" "" >/dev/null 2>&1
sleep 6
# t2: dispatch re-registers the same task_id; pid=None reads as not-alive so
# the old row is removed and a fresh one appended (started_at resets).
leadv2_active_register "WSO-REINC" Standard "$root" wt false "" "" "" "" >/dev/null 2>&1
echo "recreate_rc=$?"
python3 - "$root/docs/leadv2/active.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
row = next((s for s in d["sessions"] if s["task_id"] == "WSO-REINC"), {})
fs, st = row.get("first_seen_at"), row.get("started_at")
print("carried_writes=%s" % row.get("writes"))
print("clock_preserved=%s" % (fs is not None and fs != st))
PY
# t2+eps: with the clock measured from FIRST sight the window already
# expired (age ~6s > 5s), so the candidate is NOT pending-blocked. The
# pre-fix code measured from the recreation (age ~0.3s) and refused.
leadv2_active_register "WSO-CAND" Standard "$root" wt-cand false "" "" "cand/b.txt" 2>/dev/null >/dev/null
echo "cand_rc=$?"
EOF
)" || true
if printf '%s' "${out3}" | grep -q 'recreate_rc=0' \
  && printf '%s' "${out3}" | grep -q 'carried_writes=res/a.txt' \
  && printf '%s' "${out3}" | grep -q 'clock_preserved=True' \
  && printf '%s' "${out3}" | grep -q 'cand_rc=0'; then
  ok "3: recreation carries writes=res/a.txt + first_seen_at; expired window no longer blocks (cand rc=0)"
else
  bad "3: out=[${out3}]"
fi

# ════ 3b. same recreation, but the row is STILL write-less after it ════════
# The clock discriminator must not be diluted by the carry-over: a row that
# never declared (write-less reservation, write-less recreation) is judged by
# the pending window ALONE -- measured from first_seen_at, it has already
# expired here (age ~6s > 5s window); measured from started_at (the pre-fix
# clock), it is fresh and blanket-refuses. This is the case the mutation
# control M1 redden.
out3b="$( bash -s "${REGISTRY_SH}" "${FANOUT_FUNCS_SH}" "${TMPDIR_ROOT}" <<'EOF'
set -uo pipefail
source "$1"; set +e
FANFUNCS="$2"
root="$3/c3b"; mkdir -p "$root"
export LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" LEADV2_BURN_GOVERNOR=0
export LEADV2_WRITESET_PENDING_WINDOW_SEC=5
git -C "$root" init -q; git -C "$root" config user.email t@e.com; git -C "$root" config user.name t
source "${FANFUNCS}"
PROJECT_ROOT="$root"
# t0: pid=null reservation that CANNOT declare (no writes on the task row).
_fanout_register_session "WSO-RE2" Standard "null" "reserving" "true" "true" \
  "dispatch-code" "" "" "" "" "" "" "" "" "" "task_row_undeclared" >/dev/null 2>&1
sleep 6
# t2: dispatch re-registers; pid=None -> remove+append; nothing to carry.
# The candidate follows IMMEDIATELY: under the pre-fix clock (started_at,
# reset by this recreation) the fresh window blanket-refuses it (age ~0.3s
# vs a 5s window — one slow python spawn no longer dilutes the control,
# the M1 mutant_survived failure that forced this margin); under the fix
# (first_seen_at, t0) the window has already expired (age ~6s > 5s).
leadv2_active_register "WSO-RE2" Standard "$root" wt false "" "" "" "" >/dev/null 2>&1
leadv2_active_register "WSO-CAND" Standard "$root" wt-cand false "" "" "cand/b.txt" 2>/dev/null >/dev/null
echo "cand_rc=$?"
python3 - "$root/docs/leadv2/active.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
row = next((s for s in d["sessions"] if s["task_id"] == "WSO-RE2"), {})
print("still_writeless=%s" % (row.get("writes") is None))
print("reason_carried=%s" % row.get("writes_reason"))
PY
EOF
)" || true
if printf '%s' "${out3b}" | grep -q 'still_writeless=True' \
  && printf '%s' "${out3b}" | grep -q 'reason_carried=task_row_undeclared' \
  && printf '%s' "${out3b}" | grep -q 'cand_rc=0'; then
  ok "3b: write-less recreated row exits the pending window by FIRST sight (cand rc=0; pre-fix clock would blanket-refuse)"
else
  bad "3b: out=[${out3b}]"
fi

# ════ 4. true positive preserved: declared sets that overlap still refuse ══
out4="$( bash -s "${REGISTRY_SH}" "${TMPDIR_ROOT}" <<'EOF'
set -uo pipefail
source "$1"; set +e
root="$2/c4"; mkdir -p "$root"
export LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" LEADV2_BURN_GOVERNOR=0
export LEADV2_WRITESET_PENDING_WINDOW_SEC=900
git -C "$root" init -q && git -C "$root" config user.email t@e.com && git -C "$root" config user.name t
leadv2_active_register "WSO-OVL" Standard "$root" wt false "" "" "shared/x.txt" >/dev/null 2>&1
err="$(leadv2_active_register "WSO-CAND" Standard "$root" wt-cand false "" "" "shared/x.txt/nested.md" 2>&1 >/dev/null)"
echo "reg_rc=$?"
echo "$err" | grep -o 'paths=[^ ]*' | head -1
EOF
)" || true
if printf '%s' "${out4}" | grep -q 'reg_rc=5' \
  && printf '%s' "${out4}" | grep -q 'paths=shared/x.txt'; then
  ok "4: genuine overlap between declared sets still refuses rc=5 naming the path"
else
  bad "4: out=[${out4}]"
fi

# ════ 5. fanout spawn-site rows record why they are write-less ════════════
out5="$( bash -s "${REGISTRY_SH}" "${FANOUT_FUNCS_SH}" "${TMPDIR_ROOT}" <<'EOF'
set -uo pipefail
source "$1"; set +e
FANFUNCS="$2"
root="$3/c5"; mkdir -p "$root"
export LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" LEADV2_BURN_GOVERNOR=0
export LEADV2_WRITESET_PENDING_WINDOW_SEC=900
git -C "$root" init -q && git -C "$root" config user.email t@e.com && git -C "$root" config user.name t
source "${FANFUNCS}"
PROJECT_ROOT="$root"
# Pre-dispatch spawn site: no writes arg at all (old call shape, 14 args).
_fanout_register_session "WSO-SPAWN" Standard "$$" "leadv2: WSO-SPAWN" "true" "false" \
  "headless" "" "" "" "" "" "" "" >/dev/null 2>&1
python3 - "$root/docs/leadv2/active.yaml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
row = next((s for s in d["sessions"] if s["task_id"] == "WSO-SPAWN"), {})
print("spawn_writes=%s" % row.get("writes"))
print("spawn_reason=%s" % row.get("writes_reason"))
PY
EOF
)" || true
if printf '%s' "${out5}" | grep -q 'spawn_writes=None' \
  && printf '%s' "${out5}" | grep -q 'spawn_reason=pre_dispatch_spawn'; then
  ok "5: legacy-shape spawn row lands write-less WITH writes_reason=pre_dispatch_spawn (legible, not silent)"
else
  bad "5: out=[${out5}]"
fi

printf '[TEST] SUMMARY: pass=%s fail=%s\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
