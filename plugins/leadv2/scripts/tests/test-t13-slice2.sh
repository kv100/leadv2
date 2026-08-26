#!/usr/bin/env bash
# T13 slice2 — C2 (ARBITER-BENCH-FALLBACK-GAP-01) + C3 (ABANDON-NO-OP-01)
# regression checks plus mutation (negative) controls.
#
# Coverage:
#   1. route_arbiter honours descriptor.allowed_arms — a benched primary
#      arm's fallback re-arbitration can never resurrect it from the
#      capability matrix. Direct unit test on lib/leadv2-route-arbiter.sh
#      (same harness style as tests/test-route-arbiter.sh).
#   2. leadv2-dispatch-code.sh's bench-fallback block (ARBITER-BENCH-
#      FALLBACK-GAP-01) actually calls route_arbiter and emits
#      route_headroom_chosen when the primary candidate is quota-benched.
#      Extract-and-eval harness (same style as tests/test-t13-slice1.sh's
#      extract_guard), stubbing every dependency the block touches.
#   2b. leadv2-dispatch-code.sh's exit76_receipt continuation block (candidate-
#      loop case 7, T13-SLICE1 W3) is a DISTINCT arbiter call site from 2's
#      bench-fallback block: it re-arbitrates over the remaining candidate
#      arms and sets _reenter=1 when GLM's own exit76 sentinel fires. Same
#      extract-and-eval harness.
#   3. leadv2-lanes-snapshot.sh's abandon-answer branch (ABANDON-NO-OP-01)
#      deregisters the active.yaml row on an answered `abandon` decision,
#      and a second reconcile does NOT re-ask (fixture-level, same pattern
#      as tests/test-lanes-snapshot.sh Test 4). Fix-round F2: the row delete
#      must go through the tombstone path -- an ABANDON entry lands in
#      tombstones.yaml BEFORE the row is pruned (R2-4 contract).
#
# Each case has a paired mutation control: revert the fix in a scratch copy
# of the subject file and show the same assertion goes red.
# Run: bash scripts/tests/test-t13-slice2.sh
# Exit 0 = all pass; non-zero = failures found.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${HERE}/.." && pwd)"
ARBITER="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
DISPATCH="${SCRIPTS_DIR}/leadv2-dispatch-code.sh"
LANES_SH="${SCRIPTS_DIR}/leadv2-lanes-snapshot.sh"
STATE_PATH_SH="${SCRIPTS_DIR}/leadv2-state-path.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t13-slice2.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT
PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }

# ── Case 1: allowed_arms filters the capability matrix ─────────────────────
cat >"${TMP}/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"${TMP}/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "${TMP}/live.sh" "${TMP}/free.sh"
quota() { python3 - "$1" "$2" "$3" <<'PY'
import json, sys
g, c, a = map(int, sys.argv[1:])
print(json.dumps({
    'glm': {'status': 'ok', 'five_hour': {'pct': g}, 'weekly': {'pct': g}},
    'codex': {'status': 'ok', 'binding_window': 'primary', 'windows': [{'kind': 'primary', 'used_percent': c}]},
    'anthropic': {'status': 'ok', 'accounts': [{'active': True, 'five_hour_pct': a, 'seven_day_pct': a}]},
}))
PY
}
run_arbiter() { # <arbiter-path> <quota-json> <free-rc> <descriptor-json>
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="${TMP}/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="${TMP}/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="${TMP}/state-$$" \
    ROUTE_TEST_QUOTA="$2" ROUTE_TEST_FREE_RC="${3:-0}" bash -c 'source "$0"; route_arbiter worker "$1"' "$1" "$4"
}

case1() { # <arbiter-path> -> 0 pass
  local arb="$1" out chain
  # Cheap, healthy quotas across the board: without allowed_arms the arbiter
  # would freely pick glm/freepool. Restrict allowed_arms to codex+sonnet
  # only (the still-spawnable set after a hypothetical glm bench) and assert
  # neither glm nor freepool ever appears as the pick or anywhere in chain.
  out="$(run_arbiter "$arb" "$(quota 5 20 20)" 0 '{"kind":"code","size":"standard","allowed_arms":["codex","sonnet"]}')" || return 1
  chain="$(printf '%s\n' "$out" | sed -n 's/.*chain=\([^ ]*\).*/\1/p')"
  [[ "$out" != *'arm=glm '* && "$out" != *'arm=freepool '* && ",${chain}," != *',glm,'* && ",${chain}," != *',freepool,'* ]]
}
if case1 "$ARBITER"; then pass "allowed_arms excludes glm/freepool from pick and chain"; else fail "allowed_arms did not restrict capability matrix"; fi

# Negative control: a scratch arbiter copy with the allowed_arms filter
# clause stripped must let case1 fail (glm/freepool re-enter the pool).
MUT1="${TMP}/route-arbiter.mutated.sh"
sed 's/ and (allowed is None or c\.get(.arm.) in allowed)//' "$ARBITER" > "$MUT1"
if case1 "$MUT1"; then fail "NEGATIVE CONTROL 1: mutated arbiter (no allowed_arms filter) unexpectedly still passed"; else pass "NEGATIVE CONTROL 1: mutated arbiter (no allowed_arms filter) correctly fails case1"; fi

# ── Case 2: dispatch-code.sh bench-fallback block calls route_arbiter ──────
extract_bench_fallback() { # <script>
  # NOTE: unlike extract_guard in test-t13-slice1.sh, this deliberately does
  # NOT unset the caller's stub functions (emit, _arm_provider, ...) -- the
  # eval'd block below calls them directly and relies on the case2()-defined
  # stubs still being in scope.
  local start end
  start="$(grep -n 'local _glm_quota_benched=""' "$1" | head -1 | cut -d: -f1)"
  end="$(grep -n '^  # ROUTER-QUOTA-DRIVEN-01 (T6):' "$1" | head -1 | cut -d: -f1)"
  [[ -n "$start" && -n "$end" && "$end" -gt "$start" ]] || return 2
  eval "$(sed -n "${start},$((end - 1))p" "$1")" || return 1
}

case2() { # <dispatch-script> -> 0 pass
  local s="$1" emitted
  emit() { emitted="${emitted:-}"$'\n'"$*"; }
  _arm_provider() { case "$1" in codex) echo codex ;; glm) echo glm ;; *) echo "$1" ;; esac; }
  _provider_available() { [[ "$1" == "codex" ]] && return 1 || return 0; }
  _lockout_record_field() { printf 'trivial'; }
  _glm_park_deferred() { return 0; }
  _codex_credits_watch() { return 0; }
  route_arbiter() { printf 'arm=glm model=glm-5.2 tier=standard reason=cheapest_capable chain=glm util_glm=10\n'; return 0; }
  # T13 slice2 fix-round (F3): the old `return 0` stub was a no-op, so the
  # block's `arm="${candidate_arms[0]}"` read the PRE-SEEDED array element and
  # the assertion passed without the arbiter pick mattering. This stub is
  # faithful to the real _adopt_v2_chain (dispatch-code.sh): it REBUILDS
  # candidate_arms from the adopted chain= CSV (claude- prefix normalize,
  # empties dropped), so arm= can only come from the ARBITER's chain.
  _adopt_v2_chain() {  # <sig8> <site> <csv-chain> -> 0 when candidate_arms rebuilt
    local _csv="$3" _a
    local -a _tmp=() _norm=()
    IFS=',' read -r -a _tmp <<< "${_csv}"
    for _a in "${_tmp[@]}"; do
      [[ -n "${_a}" ]] || continue
      _norm+=("${_a#claude-}")
    done
    candidate_arms=("${_norm[@]}")
    [[ ${#candidate_arms[@]} -gt 0 && -n "${candidate_arms[0]:-}" ]]
  }
  # Post-bench ladder head is SONNET (codex benched); the arbiter's chain is
  # glm -- arm=glm is reachable ONLY through the arbiter adoption. A no-op
  # adopt stub leaves arm=sonnet and the assertions below go red.
  local sig8="case2sig" mission="m" founder_task_id="ft" kind="code" task_class="standard"
  local -a candidate_arms=(codex sonnet glm)
  emitted=""
  extract_bench_fallback "$s" || return 2
  [[ "${arm:-}" == "glm" && "${router_label:-}" == "arbiter" ]] || return 1
  printf '%s\n' "$emitted" | grep -q 'route_headroom_chosen task=case2sig arm=glm after=primary_arm_benched ordered=glm source=arbiter'
}
if case2 "$DISPATCH"; then pass "bench-fallback re-arbitrates and emits route_headroom_chosen when primary arm benched"; else fail "bench-fallback wiring did not re-arbitrate on primary bench"; fi

# Negative control: a scratch dispatch copy with the ARBITER-BENCH-FALLBACK-GAP-01
# if-block stripped (its 3 declaration/assignment lines removed, so
# _primary_arm_benched is set but never acted on) must fail case2.
# T13 slice2 fix-round (F5): both excision ends are anchored on stable marker
# COMMENTS, not indentation shapes -- the old end-anchor matched the first
# 2-space "  fi" after the start marker, which couples the excision to the
# block's nesting depth and silently excises the wrong lines on any
# re-indent of the block.
MUT2="${TMP}/dispatch.mutated.sh"
python3 - "$DISPATCH" "$MUT2" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().splitlines(keepends=True)
start = end = None
for i, l in enumerate(lines):
    if 'ARBITER-BENCH-FALLBACK-GAP-01: a provider lockout can remove' in l:
        start = i
    if start is not None and 'ROUTER-QUOTA-DRIVEN-01 (T6): filter candidate_arms' in l:
        end = i
        break
assert start is not None and end is not None and end > start, "could not locate bench-fallback block to mutate"
mutated = lines[:start] + lines[end:]
open(dst, 'w').writelines(mutated)
PY
if case2 "$MUT2"; then fail "NEGATIVE CONTROL 2: mutated dispatch (bench-fallback block removed) unexpectedly still passed"; else pass "NEGATIVE CONTROL 2: mutated dispatch (bench-fallback block removed) correctly fails case2"; fi

# ── Case 2b: exit-76 continuation re-arbitrates over remaining candidates ──
# Distinct call site from case2's bench-fallback block: this one fires on
# case-7 (arm refused post-spawn) of the candidate loop when LAST_ARM_OUTCOME
# is exit76_receipt (GLM's own GLM_FALLBACK_TO_SONNET sentinel, T13-SLICE1
# W3) rather than a quota bench. Same extract-and-eval harness style.
extract_exit76_continuation() { # <script>
  local start end
  start="$(grep -n 'if \[\[ "\${LAST_ARM_OUTCOME:-}" == "exit76_receipt" \]\] && declare -F route_arbiter' "$1" | head -1 | cut -d: -f1)"
  [[ -n "$start" ]] || return 2
  end="$(awk -v s="$start" 'NR>s && /^      fi$/{print NR; exit}' "$1")"
  [[ -n "$end" && "$end" -gt "$start" ]] || return 2
  # Wrap in a single-iteration for-loop: the extracted block's own `break`
  # (its early-success exit once arbiter picks a fallback arm) is only
  # meaningful inside a loop, and the eval site here isn't one.
  eval "for _e76_once in 1; do $(sed -n "${start},${end}p" "$1")
done" || return 1
}

case2b() { # <dispatch-script> -> 0 pass
  local s="$1" emitted
  emit() { emitted="${emitted:-}"$'\n'"$*"; }
  # T13 slice2 fix-round (F3): same faithful stub as case2 -- rebuild
  # candidate_arms from the arbiter chain= CSV instead of the old no-op, so
  # the assertion pins the ARBITER's pick (sonnet), not the pre-seeded
  # candidate_arms[0] (glm).
  _adopt_v2_chain() {  # <sig8> <site> <csv-chain> -> 0 when candidate_arms rebuilt
    local _csv="$3" _a
    local -a _tmp=() _norm=()
    IFS=',' read -r -a _tmp <<< "${_csv}"
    for _a in "${_tmp[@]}"; do
      [[ -n "${_a}" ]] || continue
      _norm+=("${_a#claude-}")
    done
    candidate_arms=("${_norm[@]}")
    [[ ${#candidate_arms[@]} -gt 0 && -n "${candidate_arms[0]:-}" ]]
  }
  route_arbiter() { printf 'arm=sonnet model=sonnet tier=standard reason=cheapest_capable chain=sonnet util_glm=10\n'; return 0; }
  local sig8="case2bsig" kind="code" task_class="standard" candidate="glm"
  local -a candidate_arms=(glm codex sonnet) attempted=()
  local LAST_ARM_OUTCOME="exit76_receipt" _fallback_from="" _fallback_reason="" arm="" router_label="" _reenter=""
  emitted=""
  extract_exit76_continuation "$s" || return 2
  # arm MUST be the arbiter's pick (sonnet): the block sets
  # arm="${candidate_arms[0]}" AFTER adopting chain=sonnet, so a no-op adopt
  # stub leaves arm=glm (the pre-seeded head) and this goes red.
  [[ "${_reenter:-}" == "1" && "${arm:-}" == "sonnet" ]] || return 1
  printf '%s\n' "$emitted" | grep -q 'route_headroom_chosen task=case2bsig arm=sonnet after=exit76_continuation ordered=sonnet'
}
if case2b "$DISPATCH"; then pass "exit76_receipt continuation re-arbitrates over remaining candidates and sets _reenter"; else fail "exit76 continuation wiring did not re-arbitrate on exit76_receipt"; fi

# Negative control: a scratch dispatch copy with the exit76-continuation
# if-block's route_arbiter call stripped (replaced with a rc=1 no-op) must
# fail case2b (no _reenter, no route_headroom_chosen emission).
MUT2B="${TMP}/dispatch.mutated2b.sh"
python3 - "$DISPATCH" "$MUT2B" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
needle = '_e76_out="$(route_arbiter worker "${_e76_desc}")"; _e76_rc=$?'
assert needle in text, "could not locate exit76 route_arbiter call to mutate"
mutated = text.replace(needle, '_e76_out=""; _e76_rc=1', 1)
open(dst, 'w').write(mutated)
PY
if case2b "$MUT2B"; then fail "NEGATIVE CONTROL 2b: mutated dispatch (exit76 route_arbiter call broken) unexpectedly still passed"; else pass "NEGATIVE CONTROL 2b: mutated dispatch (exit76 route_arbiter call broken) correctly fails case2b"; fi

# ── Case 3: abandon answer deregisters the active.yaml row ─────────────────
_active_yaml() { LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" PROJECT_ROOT="$1" bash "$STATE_PATH_SH" active.yaml; }
_questions_dir() { LEADV2_PROJECT_ROOT="$1" LEADV2_STATE_ROOT="$2" PROJECT_ROOT="$1" bash "$STATE_PATH_SH" questions; }

setup_abandon_fixture() { # -> prints "<repo> <state> <active_path> <q_dir>"
  local repo state active_path q_dir
  repo="$(mktemp -d "${TMPDIR:-/tmp}/t13s2-repo.XXXXXX")"
  state="$(mktemp -d "${TMPDIR:-/tmp}/t13s2-state.XXXXXX")"
  (cd "$repo" && git init -q)
  mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff" "$repo/.claude/cache"
  active_path="$(_active_yaml "$repo" "$state")"
  mkdir -p "$(dirname "$active_path")"
  cat > "$active_path" <<'YAML'
sessions:
  - task_id: ABANDON-1
    session_id: a1
    started_at: "2020-01-01T00:00:00+00:00"
    phase: build
    pid: 999999
    pid_birth: null
    protocol_version: 1
    backend: tmux
    tmux_window: ABANDON-1
    last_pulse_at: "2020-01-01T00:00:00+00:00"
    stale: false
YAML
  local snap
  snap="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" .supervise-last.json)"
  mkdir -p "$(dirname "$snap")"
  printf -- '{"rendered_at":"2020-01-01T00:00:00+00:00","tasks":{},"reported_events":[],"dead_candidates":{},"reconcile_cycle_count":5}' > "$snap"
  q_dir="$(_questions_dir "$repo" "$state")"
  mkdir -p "$q_dir"
  cat > "${q_dir}/q-abandon-1.yaml" <<'YAML'
task_id: ABANDON-1
question: "Task ABANDON-1 corroborated dead: liveness probe failed. Escalate."
status: answered
answer:
  selected: abandon
YAML
  printf -- '%s %s %s %s\n' "$repo" "$state" "$active_path" "$q_dir"
}

case3() { # <lanes-snapshot-path> -> 0 pass
  local lanes="$1" repo state active_path q_dir still_present tomb_path tombs
  read -r repo state active_path q_dir < <(setup_abandon_fixture)
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_OBSERVE_ONLY=0 bash "$lanes" --json >/dev/null 2>&1 || { rm -rf "$repo" "$state"; return 2; }
  still_present="$(python3 -c "
import yaml
d = yaml.safe_load(open('$active_path')) or {}
print(any(s.get('task_id')=='ABANDON-1' for s in d.get('sessions', [])))
")"
  local rc=0
  [[ "$still_present" == "False" ]] || rc=1
  # T13 slice2 fix-round (F2): the deregistration must leave an ABANDON
  # tombstone behind (the file's own R2-4 contract: tombstone FIRST, prune
  # SECOND) -- a bare row delete with no tombstone is exactly the reviewed bug.
  tomb_path="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" PROJECT_ROOT="$repo" bash "$STATE_PATH_SH" tombstones.yaml)"
  tombs="$(python3 -c "
import yaml
try:
    d = yaml.safe_load(open('${tomb_path}')) or []
except Exception:
    d = []
print(any(isinstance(t, dict) and t.get('task_id')=='ABANDON-1' and t.get('abandon') for t in d))
")"
  [[ "$tombs" == "True" ]] || rc=1
  rm -rf "$repo" "$state"
  return "$rc"
}
if case3 "$LANES_SH"; then pass "answered abandon decision deregisters the active.yaml row"; else fail "abandon answer did not deregister active.yaml row"; fi

case3_no_reask() { # <lanes-snapshot-path> -> 0 pass: second reconcile does not re-surface the same question as pending
  local lanes="$1" repo state active_path q_dir out
  read -r repo state active_path q_dir < <(setup_abandon_fixture)
  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_OBSERVE_ONLY=0 bash "$lanes" --json >/dev/null 2>&1 || { rm -rf "$repo" "$state"; return 2; }
  out="$(LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" \
    LEADV2_SUPERVISE_OBSERVE_ONLY=0 bash "$lanes" --json 2>/dev/null)"
  local rc=0
  [[ "$out" == *'ABANDON-1'*'pending'* ]] && rc=1
  rm -rf "$repo" "$state"
  return "$rc"
}
if case3_no_reask "$LANES_SH"; then pass "second reconcile does not re-ask the abandoned task"; else fail "abandoned task resurfaced as pending on the next reconcile"; fi

# Negative control: a scratch lanes-snapshot copy with the ABANDON-NO-OP-01
# consume-branch stripped (the whole cp_pending "abandon" isinstance/status
# check removed, so answered-abandon rows are just skipped like any other
# non-pending row and the registration survives) must fail case3.
MUT3="${TMP}/lanes-snapshot.mutated.sh"
python3 - "$LANES_SH" "$MUT3" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().splitlines(keepends=True)
start = end = None
for i, l in enumerate(lines):
    if 'ABANDON-NO-OP-01: a dead-lane escalation is actionable' in l:
        start = i - 1  # include the preceding "if not isinstance(qd, dict):" line replacement point
    if start is not None and 'if qd.get("status") != "pending":' in l:
        end = i
        break
assert start is not None and end is not None, "could not locate abandon-consume block to mutate"
# Replace the whole abandon-detection stanza with the pre-fix two-line check.
replacement = [
    '        if not isinstance(qd, dict) or qd.get("status") != "pending":\n',
]
mutated = lines[:start] + replacement + lines[end + 1:]
open(dst, 'w').writelines(mutated)
PY
if case3 "$MUT3"; then fail "NEGATIVE CONTROL 3: mutated lanes-snapshot (abandon consume removed) unexpectedly still passed"; else pass "NEGATIVE CONTROL 3: mutated lanes-snapshot (abandon consume removed) correctly fails case3"; fi

# Negative control (F2): a scratch lanes-snapshot copy with the abandon
# TOMBSTONE writer excised -- pruning directly off _ab_ids, the exact pre-F2
# shape (row deleted, no ABANDON entry in tombstones.yaml) -- must fail
# case3's tombstone assertion.
MUT3B="${TMP}/lanes-snapshot.mutated3b.sh"
python3 - "$LANES_SH" "$MUT3B" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().splitlines(keepends=True)
start = end = None
for i, l in enumerate(lines):
    if '# Tombstone FIRST (R2-4 order' in l:
        start = i
    if start is not None and '_ab_tombstoned = []' in l and i > start:
        end = i
        break
assert start is not None and end is not None and end > start, "could not locate abandon tombstone writer to mutate"
# Pre-F2 shape: no tombstone write at all; every abandon id is pruned directly.
mutated = lines[:start] + ['            _ab_tombstoned = sorted(_ab_ids)\n'] + lines[end + 1:]
open(dst, 'w').writelines(mutated)
PY
if case3 "$MUT3B"; then fail "NEGATIVE CONTROL 3b: mutated lanes-snapshot (abandon tombstone writer removed) unexpectedly still passed"; else pass "NEGATIVE CONTROL 3b: mutated lanes-snapshot (abandon tombstone writer removed) correctly fails case3"; fi

# ── Case 4: phased-path-only invariant (PHASES-ARE-THE-ONLY-PATH-01) ───────
# Trace finding (T13 slice2 C1): leadv2-dispatch-code.sh's CLI already exposes
# exactly one code-writing entrypoint, and PHASES-ARE-THE-ONLY-PATH-01 already
# wires every worker spawn through leadv2-phase-record.sh -- there is no
# separate "single-worker channel" or standalone prepass path left to delete
# (see developer.full.md for the full trace). This case pins that invariant
# structurally so a future change cannot silently reopen a bypass:
#   4a. the top-level CLI case statement recognizes only the documented
#       subcommands (no legacy/bypass subcommand reaching a worker directly).
#   4b. every spawn_worker call site is preceded, in the same function body,
#       by a PHASE_RECORD_BIN build-phase record -- no path launches a worker
#       without first recording it in the phase pipeline. Fix-round F4: the
#       same window must also contain a `route_arbiter worker` call -- no
#       spawn path may select its arm arbiter-free (pre-F1 advance-arm shape).
case4a_cli_surface() { # <script> -> 0 pass
  local s="$1" cases
  # Plain-string match (not a regex) on the case-open line -- BSD/mawk both choke on the
  # literal ${1:-} braces inside an ERE (illegal repetition expression), and there is nothing
  # regex-shaped about this line worth a pattern for.
  cases="$(awk 'index($0, "case \"${1:-}\" in") == 1{f=1;next} f&&/^esac$/{exit} f&&/^  [A-Za-z_-]+\)/{print}' "$s" \
    | sed -E 's/^[[:space:]]*//; s/\).*$//')"
  local -a allowed=(record-review status glm-deferred burn-deferred advance-arm record-quota-lockout retry-dead sweep reconcile -h --help)
  local c found
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    found=0
    local a
    for a in "${allowed[@]}"; do [[ "$c" == "$a" ]] && { found=1; break; }; done
    [[ $found -eq 1 ]] || return 1
  done <<<"$cases"
  return 0
}
if case4a_cli_surface "$DISPATCH"; then pass "CLI dispatch table has no bypass subcommand beyond the documented phased-path set"; else fail "CLI dispatch table exposes an undocumented subcommand"; fi

# Negative control: inject a bogus bypass subcommand into a scratch copy's
# case statement; the same scan must catch it.
MUT4A="${TMP}/dispatch.mutated4a.sh"
sed 's/^  sweep)/  legacy-quick-dispatch) shift; cmd_resolve "$@" ;;\n  sweep)/' "$DISPATCH" > "$MUT4A"
if case4a_cli_surface "$MUT4A"; then fail "NEGATIVE CONTROL 4a: mutated dispatch (bogus bypass subcommand injected) unexpectedly still passed"; else pass "NEGATIVE CONTROL 4a: mutated dispatch (bogus bypass subcommand injected) correctly fails the CLI-surface scan"; fi

case4b_spawn_gated() { # <script> -> 0 pass: every spawn_worker call is preceded by BOTH
  # build-phase gating -- an explicit PHASE_RECORD_BIN build record, or a
  # _phase_precondition_guard call (which itself shells to `PHASE_RECORD_BIN assert` and can
  # refuse before the spawn is ever reached -- PHASES-ARE-THE-ONLY-PATH-01's actual gate) --
  # AND a `route_arbiter worker` call in the same window (T13 slice2 fix-round F4: an
  # arbiter-free arm selection -- the pre-F1 advance-arm shape, spawning a static
  # CSV-position pick with no arbiter call -- is a bypass of the ONE PATH routing
  # contract exactly like a missing phase record, and the scan must flag it).
  # When the spawn lives inside a single-call-site helper (e.g.
  # atomic_dispatch_reserve_spawn_confirm), the window is extended backward through that one
  # caller into ITS enclosing function too, since the gating evidence lives at the call site,
  # not inside the reusable helper.
  local s="$1"
  python3 - "$s" <<'PY'
import re, sys
src = sys.argv[1]
lines = open(src).read().splitlines()
# Function boundaries: "name() {" ... matching closing "}" at column 0.
func_starts = [i for i, l in enumerate(lines) if re.match(r'^[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{', l)]
func_names = [re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\(\)', lines[i]).group(1) for i in func_starts]

def enclosing_func_start(idx):
    best = None
    for fs in func_starts:
        if fs <= idx:
            best = fs
        else:
            break
    return best

def gated(window):
    phase_gated = any(('PHASE_RECORD_BIN' in l and 'build' in l) or '_phase_precondition_guard' in l for l in window)
    arbitered = any('route_arbiter worker' in l for l in window)
    return phase_gated and arbitered

spawn_calls = [i for i, l in enumerate(lines) if 'spawn_worker "' in l and l.strip().startswith(('spawn_out=', 'local spawn_out'))]
if not spawn_calls:
    print("NO_SPAWN_CALLS_FOUND")
    sys.exit(1)
ok = True
for idx in spawn_calls:
    fstart = enclosing_func_start(idx)
    window = lines[fstart:idx] if fstart is not None else lines[:idx]
    if gated(window):
        continue
    # Not gated in its own function -- if this function has exactly ONE call site
    # elsewhere in the file, extend the window back through that call site's own
    # enclosing function (the gating may live at the call site instead).
    fname = func_names[func_starts.index(fstart)] if fstart is not None else None
    call_sites = [i for i, l in enumerate(lines)
                  if fname and re.search(rf'\b{re.escape(fname)}\s+"', l) and i not in func_starts]
    if fname and len(call_sites) == 1:
        cidx = call_sites[0]
        cfstart = enclosing_func_start(cidx)
        cwindow = lines[cfstart:cidx] if cfstart is not None else lines[:cidx]
        if gated(cwindow):
            continue
    ok = False
    print(f"UNGATED_SPAWN line={idx+1}")
sys.exit(0 if ok else 1)
PY
}
if case4b_spawn_gated "$DISPATCH"; then pass "every spawn_worker call site is preceded by a build-phase record AND a route_arbiter worker call"; else fail "a spawn_worker call site launches a worker without a build-phase record or an arbiter-gated arm selection (bypass path)"; fi

# Negative control: strip the _phase_precondition_guard call that gates
# cmd_advance_arm's spawn_worker call (the actual pre-spawn gate on this path -- the
# PHASE_RECORD_BIN build record on this path runs AFTER spawn for bookkeeping and was
# never part of the pre-spawn window); the scan must catch the ungated spawn.
MUT4B="${TMP}/dispatch.mutated4b.sh"
sed '/^  _phase_precondition_guard "\${sig8}" "\${_adv_class}"/d' "$DISPATCH" > "$MUT4B"
if case4b_spawn_gated "$MUT4B"; then fail "NEGATIVE CONTROL 4b: mutated dispatch (cmd_advance_arm precondition guard stripped) unexpectedly still passed"; else pass "NEGATIVE CONTROL 4b: mutated dispatch (cmd_advance_arm precondition guard stripped) correctly fails the spawn-gating scan"; fi

# Negative control (F4): REVERT F1 in a scratch copy -- replace advance-arm's
# route_arbiter call with a broken no-op, restoring the pre-fix arbiter-free
# static-pick spawn -- and the same scan must catch it.
MUT4C="${TMP}/dispatch.mutated4c.sh"
sed 's|_adv_out="$(route_arbiter worker "${_adv_desc}")"; _adv_rc=$?|_adv_out=""; _adv_rc=1|' "$DISPATCH" > "$MUT4C"
if grep -q '_adv_out=""; _adv_rc=1' "$MUT4C"; then
  if case4b_spawn_gated "$MUT4C"; then fail "NEGATIVE CONTROL 4c: mutated dispatch (F1 reverted: advance-arm arbiter call broken) unexpectedly still passed"; else pass "NEGATIVE CONTROL 4c: mutated dispatch (F1 reverted: advance-arm arbiter call broken) correctly fails the spawn-gating scan"; fi
else
  fail "NEGATIVE CONTROL 4c: could not build the F1-reverted scratch copy (mutation pattern not found)"
fi

printf '\n[SUMMARY] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
