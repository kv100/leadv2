#!/usr/bin/env bash
# test-land-is-one-command.sh — LANDING-A-LANE-MUST-BE-ONE-COMMAND-01
# run-all-triggers: leadv2-land
#
# Hermetic consumer/plugin fixtures for the one-command land contract. The
# plugin scripts deliberately live OUTSIDE the consumer repository, which is
# the installed-plugin/symlink shape that used to resolve ROOT incorrectly.
# Every case has a bare origin and scratch state directory; no live checkout,
# worktree registry, or control-plane state is used.
#
# Negative controls are run separately through leadv2-mutation-control.sh:
# (1) replacing the caller-root line inside land_resolve_root, (2) restoring
# the default behind bound inside land_refuse_behind's caller, and (3) forcing
# push inside land_push_or_verify. Each mutant must make its named case RED.
# Bash 3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASS=0
FAIL=0
DIRS=()

ok() { PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }
assert() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi; }
assert_eq() { [[ "$2" == "$3" ]] && ok "$1" || fail "$1 (expected [$2], got [$3])"; }
assert_contains() { case "$2" in *"$3"*) ok "$1" ;; *) fail "$1 (missing [$3])" ;; esac; }

cleanup() {
  local d
  for d in ${DIRS[@]+"${DIRS[@]}"}; do rm -rf "$d" 2>/dev/null || true; done
}
trap cleanup EXIT

_commit() { # <repo> <path> <contents> <message>
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$4"
}

_field() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$2" 2>/dev/null; }
_remote_tip() { git -C "$CONSUMER" ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1}'; }
_last_row() { tail -n 1 "$LEDGER" 2>/dev/null || true; }

_mk_case() { # <name> — plugin is separate from CONSUMER on purpose
  local name="$1" base f
  base="$(mktemp -d "${TMPDIR:-/tmp}/land-one-${name}.XXXXXX")"
  DIRS=(${DIRS[@]+"${DIRS[@]}"} "$base")
  CONSUMER="${base}/consumer"
  PLUGIN="${base}/plugin"
  ORIGIN="${base}/origin.git"
  STATE="${base}/state"
  mkdir -p "$PLUGIN"
  for f in leadv2-land.sh leadv2-branch-merged.sh leadv2-merge-queue.sh \
           leadv2-merge-safety-gate.sh leadv2-state-path.sh \
           leadv2-portable-lock.sh; do
    cp "${SRC_DIR}/${f}" "${PLUGIN}/${f}"
  done
  # A real git plugin checkout makes the old SCRIPT_DIR-derived ROOT mutation
  # deterministically select PLUGIN instead of CONSUMER.
  git init -q "$PLUGIN"
  git -C "$PLUGIN" checkout -q -b main
  git -C "$PLUGIN" add -A
  git -C "$PLUGIN" -c user.name=t -c user.email=t@t commit -q -m plugin
  LAND="${PLUGIN}/leadv2-land.sh"

  git init -q "$CONSUMER"
  git -C "$CONSUMER" checkout -q -b main
  _commit "$CONSUMER" README "base ${name}" base
  git init -q --bare "$ORIGIN"
  git -C "$CONSUMER" remote add origin "$ORIGIN"
  git -C "$CONSUMER" push -q -u origin main
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  LEDGER="${STATE}/$(basename "$CONSUMER")/land-ledger/$(basename "$CONSUMER").jsonl"
}

_land() { # <lane> [land args]
  local lane="$1"; shift
  ( cd "$CONSUMER" && env LEADV2_STATE_BASE="$STATE" LEADV2_MERGE_TIMEOUT_SEC=20 \
      bash "$LAND" "$lane" "$@" )
}

# A plugin installed outside the caller's repository must land the consumer
# branch without LEADV2_LAND_PROBE_ROOT or any project-root pinning.
case_caller_root() {
  _mk_case caller-root
  git -C "$CONSUMER" checkout -q -b lane-root
  _commit "$CONSUMER" src/root.txt root-work root-work
  local tip; tip="$(git -C "$CONSUMER" rev-parse lane-root)"
  git -C "$CONSUMER" checkout -q main
  assert 'root: plugin has no consumer lane' bash -c "! git -C '$PLUGIN' rev-parse --verify lane-root >/dev/null 2>&1"
  _land lane-root >/dev/null 2>&1; local rc=$?
  assert_eq 'root: one invocation rc=0' 0 "$rc"
  assert_eq 'root: consumer main reached lane tip' "$tip" "$(git -C "$CONSUMER" rev-parse main)"
  assert_eq 'root: consumer origin reached lane tip' "$tip" "$(_remote_tip)"
  assert_eq 'root: plugin main stayed separate' 1 "$(git -C "$PLUGIN" rev-list --count main)"
}

# Main drift is merged automatically with the safety gate still in the path.
case_behind_lands() {
  _mk_case behind
  git -C "$CONSUMER" checkout -q -b lane-behind
  _commit "$CONSUMER" src/lane.txt lane-work lane-work
  local lane_tip; lane_tip="$(git -C "$CONSUMER" rev-parse lane-behind)"
  git -C "$CONSUMER" checkout -q main
  _commit "$CONSUMER" src/main.txt main-work main-advance
  local main_before; main_before="$(git -C "$CONSUMER" rev-parse main)"
  assert_eq 'behind: setup is one commit behind' 1 "$(git -C "$CONSUMER" rev-list --count lane-behind..main)"
  _land lane-behind >/dev/null 2>&1; local rc=$?
  assert_eq 'behind: one invocation rc=0' 0 "$rc"
  assert 'behind: landed commit is a real merge' test "$(git -C "$CONSUMER" rev-list --count "${main_before}..main")" -ge 1
  assert 'behind: lane is ancestor of landed main' git -C "$CONSUMER" merge-base --is-ancestor "$lane_tip" main
  local row; row="$(_last_row)"
  assert_eq 'behind: ledger outcome=landed' landed "$(_field "$row" outcome)"
  assert_eq 'behind: ledger auto_no_ff' auto_no_ff "$(_field "$row" mode)"
}

# --no-push retains the transaction's queue, gate, and ledger but leaves the
# remote tip untouched and says so truthfully in the ledger.
case_no_push() {
  _mk_case no-push
  git -C "$CONSUMER" checkout -q -b lane-no-push
  _commit "$CONSUMER" src/local.txt local-work local-work
  local tip remote_before; tip="$(git -C "$CONSUMER" rev-parse lane-no-push)"; remote_before="$(_remote_tip)"
  git -C "$CONSUMER" checkout -q main
  _land lane-no-push --no-push >/dev/null 2>&1; local rc=$?
  assert_eq 'no-push: one invocation rc=0' 0 "$rc"
  assert_eq 'no-push: local main reached lane tip' "$tip" "$(git -C "$CONSUMER" rev-parse main)"
  assert_eq 'no-push: origin remains unchanged' "$remote_before" "$(_remote_tip)"
  local row; row="$(_last_row)"
  assert_eq 'no-push: ledger outcome=landed' landed "$(_field "$row" outcome)"
  assert_eq 'no-push: ledger pushed=false' False "$(_field "$row" pushed)"
}

# Raising the drift bound must not turn the safety gate into an allow-all.
case_conflict_refused() {
  _mk_case conflict
  git -C "$CONSUMER" checkout -q -b lane-conflict
  _commit "$CONSUMER" README lane-value lane-edits-readme
  git -C "$CONSUMER" checkout -q main
  _commit "$CONSUMER" README main-value main-edits-readme
  local main_before; main_before="$(git -C "$CONSUMER" rev-parse main)"
  assert_eq 'conflict: setup is one commit behind' 1 "$(git -C "$CONSUMER" rev-list --count lane-conflict..main)"
  _land lane-conflict >/dev/null 2>&1; local rc=$?
  assert_eq 'conflict: safety gate refuses rc=1' 1 "$rc"
  assert_eq 'conflict: main remains unmoved' "$main_before" "$(git -C "$CONSUMER" rev-parse main)"
  local row; row="$(_last_row)"
  assert_eq 'conflict: ledger outcome=refused' refused "$(_field "$row" outcome)"
  assert_eq 'conflict: ledger records safety gate error' safety_gate_error "$(_field "$row" reason)"
}

case_caller_root
case_behind_lands
case_no_push
case_conflict_refused

printf '# land-is-one-command pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ ${FAIL} -eq 0 ]]
