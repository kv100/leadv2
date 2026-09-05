#!/usr/bin/env bash
# plugins/leadv2/scripts/tests/test-skill-telemetry.sh — SKILL-USAGE-IS-UNMEASURED-01
#
# Coverage for leadv2-skill-telemetry-collect.sh (transcript -> invocation
# JSONL) and leadv2-skill-rollup.sh (period rollup, three honest buckets).
# Runs the REAL collector/rollup scripts against a fixture transcript tree
# and a fixture repo root — only the transcript dir and repo root are faked,
# never the scripts under test (WAVE4 rule).
#
# Fixture shape:
#   - a fixture "session" transcript with three S1a Skill tool_use calls
#     (ok / error / unresolved-result outcomes) and one slash-command line
#     (must NOT be collected: <command-name> without <skill-format>);
#   - a fixture subagent transcript (session-dir/subagents/agent-*.jsonl)
#     proving that glob is scanned too;
#   - S1b description-matched injections against two fixture worktree lanes,
#     one whose journal resolves dispatch_terminal=landed, one =dead, so
#     lane_outcome / lane_success are exercised against the REAL journal
#     vocabulary (not invented labels);
#   - one S1b row older than the --since window, to prove window filtering
#     (it must show up as INVOKED_PAST_ONLY in the rollup, never as
#     NEVER_INVOKED — that would be a lie).
#
# Negative controls (M1, M2) apply a precise, python3-verified single-line
# insertion to a SCRATCH COPY of the production script (never the original),
# confirms the anchor was found exactly once, then re-runs the fixture
# assertions against the mutated copy and requires them to fail. Anchors are
# scoped to fall strictly inside the target function's body.
# run-all-triggers: leadv2-skill-rollup leadv2-skill-telemetry-collect leadv2-portable-lock
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.

set -uo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SUITE_DIR}/.." && pwd)"
COLLECT="${SCRIPTS_DIR}/leadv2-skill-telemetry-collect.sh"
ROLLUP="${SCRIPTS_DIR}/leadv2-skill-rollup.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '[TEST] PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '[TEST] FAIL: %s\n' "$1"; }
expect() { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got: $1 want: $2)"; }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skill-telemetry.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# ── bash 3.2 (macOS) + modern bash (Linux-representative) syntax check ──────
for b in bash /bin/bash; do
  command -v "$b" >/dev/null 2>&1 || continue
  if "$b" -n "$COLLECT"; then pass "collector syntax ($b)"; else fail "collector syntax ($b)"; fi
  if "$b" -n "$ROLLUP"; then pass "rollup syntax ($b)"; else fail "rollup syntax ($b)"; fi
done

# ══════════════════════════════════════════════════════════════════════════
# Fixture build
# ══════════════════════════════════════════════════════════════════════════
TRANSCRIPTS="$ROOT/transcripts"
FIXREPO="$ROOT/repo"
SESS_DIR="$TRANSCRIPTS/proj"
mkdir -p "$SESS_DIR" "$SESS_DIR/sess-1/subagents"
mkdir -p "$FIXREPO/docs/leadv2/tasks/dispatch-fx0001" "$FIXREPO/docs/leadv2/tasks/dispatch-fx0002"

cat > "$FIXREPO/docs/leadv2/tasks/dispatch-fx0001/journal.md" <<'EOF'
- 2026-09-01T10:00:00.000Z [decision] dispatch_task_bound task=fx0001 founder_task=FIXTURE-LANE-LANDED
- 2026-09-01T10:00:05.000Z [decision] dispatch_classified task=fx0001 class=Standard reason=x
- 2026-09-01T10:05:00.000Z [decision] worker_spawned task=fx0001
- 2026-09-01T10:30:00.000Z [decision] dispatch_terminal task=fx0001 terminal=landed cause=reconciled
EOF

cat > "$FIXREPO/docs/leadv2/tasks/dispatch-fx0002/journal.md" <<'EOF'
- 2026-09-01T11:00:00.000Z [decision] dispatch_task_bound task=fx0002 founder_task=FIXTURE-LANE-DEAD
- 2026-09-01T11:05:00.000Z [decision] worker_spawned task=fx0002
- 2026-09-01T11:30:00.000Z [decision] dispatch_terminal task=fx0002 terminal=dead cause=e2e_regression
EOF

SKILLROOT="$ROOT/skills-root"
for s in fixture-skill-ok fixture-skill-err fixture-skill-noresult \
         fixture-skill-injected fixture-skill-failing fixture-skill-subagent \
         fixture-skill-never fixture-skill-stale; do
  mkdir -p "$SKILLROOT/$s"
  printf '# %s\n' "$s" > "$SKILLROOT/$s/SKILL.md"
done
mkdir -p "$SKILLROOT/fixture-no-md"

python3 - "$SESS_DIR" "$FIXREPO" <<'PYFIX'
import json, os, sys

sess_dir, fixrepo = sys.argv[1], sys.argv[2]
main_cwd = fixrepo
landed_cwd = fixrepo + "/.claude/worktrees/FIXTURE-LANE-LANDED"
dead_cwd = fixrepo + "/.claude/worktrees/FIXTURE-LANE-DEAD"

def w(f, obj):
    f.write(json.dumps(obj) + "\n")

def tool_use(session_id, uuid, ts, cwd, skill, tool_id, branch=None):
    return {
        "type": "assistant", "isSidechain": False, "sessionId": session_id,
        "uuid": uuid, "timestamp": ts, "cwd": cwd, "gitBranch": branch,
        "message": {"role": "assistant", "content": [
            {"type": "tool_use", "id": tool_id, "name": "Skill", "input": {"skill": skill}}
        ]},
    }

def tool_result(session_id, uuid, ts, cwd, tool_id, success):
    return {
        "type": "user", "isSidechain": False, "sessionId": session_id,
        "uuid": uuid, "timestamp": ts, "cwd": cwd,
        "message": {"role": "user", "content": [
            {"type": "tool_result", "tool_use_id": tool_id, "content": "x"}
        ]},
        "toolUseResult": {"success": success},
    }

def injection(session_id, uuid, ts, cwd, skill, agent_id=None, is_sidechain=False):
    text = "<command-message>{0}</command-message>\n<command-name>{0}</command-name>\n<skill-format>true</skill-format>".format(skill)
    d = {
        "type": "user", "isMeta": True, "isSidechain": is_sidechain,
        "sessionId": session_id, "uuid": uuid, "timestamp": ts, "cwd": cwd,
        "message": {"role": "user", "content": [{"type": "text", "text": text}]},
    }
    if agent_id:
        d["agentId"] = agent_id
    return d

def slash_command(session_id, uuid, ts, cwd, name):
    text = "<command-message>{0}</command-message>\n<command-name>{0}</command-name>".format(name)
    return {
        "type": "user", "isMeta": True, "isSidechain": False,
        "sessionId": session_id, "uuid": uuid, "timestamp": ts, "cwd": cwd,
        "message": {"role": "user", "content": [{"type": "text", "text": text}]},
    }

sess_path = os.path.join(sess_dir, "sess-1.jsonl")
with open(sess_path, "w") as f:
    w(f, tool_use("sess-1", "u-ok", "2026-09-01T12:00:00.000Z", main_cwd, "fixture-skill-ok", "tid-ok"))
    w(f, tool_result("sess-1", "u-ok-res", "2026-09-01T12:00:01.000Z", main_cwd, "tid-ok", True))
    w(f, tool_use("sess-1", "u-err", "2026-09-01T12:01:00.000Z", main_cwd, "fixture-skill-err", "tid-err"))
    w(f, tool_result("sess-1", "u-err-res", "2026-09-01T12:01:01.000Z", main_cwd, "tid-err", False))
    w(f, tool_use("sess-1", "u-noresult", "2026-09-01T12:02:00.000Z", main_cwd, "fixture-skill-noresult", "tid-noresult"))
    # slash command: command-name present, NO skill-format tag -> must not collect
    w(f, slash_command("sess-1", "u-slash", "2026-09-01T12:03:00.000Z", main_cwd, "compact"))
    # three injections inside the LANDED lane, timestamped after worker_spawned (10:05)
    for i in range(3):
        w(f, injection("sess-1", "u-inj-landed-{}".format(i), "2026-09-01T10:10:0{}.000Z".format(i), landed_cwd, "fixture-skill-injected"))
    # two injections inside the DEAD lane
    for i in range(2):
        w(f, injection("sess-1", "u-inj-dead-{}".format(i), "2026-09-01T11:10:0{}.000Z".format(i), dead_cwd, "fixture-skill-failing"))
    # one injection far outside the --since window used by the test (window=30d)
    w(f, injection("sess-1", "u-inj-stale", "2020-01-01T00:00:00.000Z", main_cwd, "fixture-skill-stale"))

subagent_path = os.path.join(sess_dir, "sess-1", "subagents", "agent-fx1.jsonl")
with open(subagent_path, "w") as f:
    w(f, injection("sess-1", "u-inj-subagent", "2026-09-01T12:04:00.000Z", main_cwd, "fixture-skill-subagent", agent_id="agent-fx1", is_sidechain=True))
PYFIX
if [[ $? -ne 0 ]]; then
  echo "SUITE-SETUP-FAIL: fixture build failed" >&2
  exit 2
fi

JSONL="$ROOT/skill-invocations.jsonl"
OUTMD="$ROOT/skill-usage-rollup.md"

# ══════════════════════════════════════════════════════════════════════════
# A. Collector: real invocations captured with correct fields
# ══════════════════════════════════════════════════════════════════════════
out1="$(bash "$COLLECT" --since 30d --transcripts-root "$TRANSCRIPTS" --repo-root "$FIXREPO" --out "$JSONL" 2>&1)"
rc1=$?
expect "$rc1" "0" "collector exits 0 on fixture tree"
n_ok=$(grep -c '"skill":"fixture-skill-ok"' "$JSONL")
expect "$n_ok" "1" "one row for fixture-skill-ok"
n_err=$(grep -c '"skill":"fixture-skill-err"' "$JSONL")
expect "$n_err" "1" "one row for fixture-skill-err"
n_noresult=$(grep -c '"skill":"fixture-skill-noresult"' "$JSONL")
expect "$n_noresult" "1" "one row for fixture-skill-noresult"
n_injected=$(grep -c '"skill":"fixture-skill-injected"' "$JSONL")
expect "$n_injected" "3" "three rows for fixture-skill-injected (S1b)"
n_failing=$(grep -c '"skill":"fixture-skill-failing"' "$JSONL")
expect "$n_failing" "2" "two rows for fixture-skill-failing (S1b)"
n_subagent=$(grep -c '"skill":"fixture-skill-subagent"' "$JSONL")
expect "$n_subagent" "1" "subagent transcript glob is scanned"
n_stale=$(grep -c '"skill":"fixture-skill-stale"' "$JSONL")
expect "$n_stale" "0" "row older than --since window is not collected"
n_slash=$(grep -c '"skill":"compact"' "$JSONL")
expect "$n_slash" "0" "slash command without skill-format tag is never collected"

ok_outcome=$(grep '"skill":"fixture-skill-ok"' "$JSONL" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["outcome"])')
expect "$ok_outcome" "ok" "S1a success resolves outcome=ok"
err_outcome=$(grep '"skill":"fixture-skill-err"' "$JSONL" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["outcome"])')
expect "$err_outcome" "error" "S1a failure resolves outcome=error"
noresult_outcome=$(grep '"skill":"fixture-skill-noresult"' "$JSONL" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["outcome"])')
expect "$noresult_outcome" "n_a" "S1a with no matching tool_result is n_a, never guessed ok"
inj_outcome=$(grep '"skill":"fixture-skill-injected"' "$JSONL" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["outcome"])')
expect "$inj_outcome" "n_a" "S1b injection outcome is always n_a (no result record exists)"

inj_lane=$(grep '"skill":"fixture-skill-injected"' "$JSONL" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["lane"])')
expect "$inj_lane" "FIXTURE-LANE-LANDED" "lane derived from cwd worktree basename"
ok_lane=$(grep '"skill":"fixture-skill-ok"' "$JSONL" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["lane"])')
expect "$ok_lane" "main" "lane is 'main' for a non-worktree cwd"
inj_phase=$(grep '"skill":"fixture-skill-injected"' "$JSONL" | head -1 | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["phase"])')
expect "$inj_phase" "build" "phase resolved from nearest preceding real journal event (worker_spawned)"
ok_phase=$(grep '"skill":"fixture-skill-ok"' "$JSONL" | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["phase"])')
expect "$ok_phase" "unknown" "phase is 'unknown' on the main lane, never guessed"

# fixture-skill-stale already proved (above) that the collector's OWN --since
# window permanently excludes an old transcript line from ever being
# collected in a single run -- that is real, correct window-filtering
# behaviour, not a bug. To ALSO exercise the rollup's INVOKED_PAST_ONLY path
# (history exists, but outside the CURRENT rollup window) we seed one line
# directly into $JSONL here, standing in for a row collected by an earlier,
# wider-window collector run long before this test's 30d cutoff. This is
# fixture setup, not a fake of collector or rollup logic (WAVE4 rule) -- it
# runs after the n_stale=0 assertion above so it cannot mask that check.
printf '{"event_id":"seed-fixture-skill-stale-history","ts":"2020-01-01T00:00:00.000Z","skill":"fixture-skill-stale","source":"skill_format_injection","session_id":"seed","agent_id":null,"is_sidechain":false,"cwd":null,"repo":null,"lane":null,"git_branch":null,"phase":"unknown","outcome":"n_a","collected_at":"2020-01-01T00:00:00.000Z"}\n' >> "$JSONL"

# ══════════════════════════════════════════════════════════════════════════
# B. Idempotency under a rerun (simulates a concurrent/repeat collector call)
# ══════════════════════════════════════════════════════════════════════════
n1=$(wc -l < "$JSONL" | tr -d ' ')
out2="$(bash "$COLLECT" --since 30d --transcripts-root "$TRANSCRIPTS" --repo-root "$FIXREPO" --out "$JSONL" 2>&1)"
rc2=$?
n2=$(wc -l < "$JSONL" | tr -d ' ')
expect "$rc2" "0" "second collector run exits 0"
expect "$n1" "$n2" "rerun appends zero duplicate rows (event_id dedup)"

# ══════════════════════════════════════════════════════════════════════════
# D. Rollup: universe union, three buckets, correlation header
# ══════════════════════════════════════════════════════════════════════════
TSV="$ROOT/rollup.tsv"
bash "$ROLLUP" --since 30d --jsonl "$JSONL" --repo-root "$FIXREPO" \
  --skills-root "$SKILLROOT" --format tsv --out "$OUTMD" > "$TSV"
rc3=$?
expect "$rc3" "0" "rollup exits 0"
n_lines=$(( $(wc -l < "$TSV" | tr -d ' ') - 1 ))
expect "$n_lines" "9" "universe (TSV data rows) matches the 9 fixture skill dirs"

if grep -q 'universe=9' "$OUTMD"; then pass "MD prints universe=9"; else fail "MD prints universe=9"; fi
if grep -q 'CORRELATION, NOT PROOF' "$OUTMD"; then pass "MD prints the correlation-not-proof header"; else fail "MD prints the correlation-not-proof header"; fi

bucket_of() { awk -F'\t' -v s="$1" '$1==s{print $7}' "$TSV"; }
lane_success_of() { awk -F'\t' -v s="$1" '$1==s{print $8}' "$TSV"; }

expect "$(bucket_of fixture-skill-injected)" "INVOKED" "all-landed skill buckets INVOKED"
expect "$(bucket_of fixture-skill-failing)" "INVOKED_NO_LANE_SUCCESS" "all-failed-resolved skill buckets INVOKED_NO_LANE_SUCCESS"
expect "$(bucket_of fixture-skill-never)" "NEVER_INVOKED" "zero-rows-ever skill buckets NEVER_INVOKED"
expect "$(bucket_of fixture-no-md)" "no-skill-md" "SKILL.md-less dir is reported, not dropped"
stale_bucket="$(bucket_of fixture-skill-stale)"
if [ "$stale_bucket" != "NEVER_INVOKED" ] && [ -n "$stale_bucket" ]; then
  pass "history-only-outside-window skill is never mislabeled NEVER_INVOKED (got: $stale_bucket)"
else
  fail "history-only-outside-window skill mislabeled (got: $stale_bucket)"
fi

expect "$(lane_success_of fixture-skill-injected)" "100%" "lane_success computed from real dispatch_terminal=landed"
expect "$(lane_success_of fixture-skill-failing)" "0%" "lane_success computed from real dispatch_terminal=dead (0%, not n/a — it IS resolved)"
expect "$(lane_success_of fixture-skill-ok)" "n/a" "lane_success is n/a (never 0%) when no row's lane resolved"

# E. Dynamically pick a NEVER_INVOKED skill and confirm it truly has zero rows
E_SKILL="$(awk -F'\t' '$7=="NEVER_INVOKED"{print $1; exit}' "$TSV")"
if [ -n "$E_SKILL" ]; then
  e_count=$(grep -c "\"skill\":\"$E_SKILL\"" "$JSONL")
  expect "$e_count" "0" "dynamically-picked NEVER_INVOKED skill ($E_SKILL) has zero JSONL rows"
else
  fail "no NEVER_INVOKED skill found to spot-check"
fi

# F. run-all.sh registration (static check; live selection proof is run
# separately via LEADV2_RUN_ALL_SELECT_ONLY=1, see report — this suite only
# proves the EXTRA_SUITE_MAP rows exist)
RUN_ALL="${SCRIPTS_DIR}/../../../tests/run-all.sh"
if [ -f "$RUN_ALL" ] && grep -q 'leadv2-skill-telemetry-collect.sh:plugins/leadv2/scripts/tests/test-skill-telemetry.sh' "$RUN_ALL" \
   && grep -q 'leadv2-skill-rollup.sh:plugins/leadv2/scripts/tests/test-skill-telemetry.sh' "$RUN_ALL"; then
  pass "tests/run-all.sh EXTRA_SUITE_MAP carries both stem rows for this suite"
else
  fail "tests/run-all.sh EXTRA_SUITE_MAP missing a row for this suite"
fi

# ══════════════════════════════════════════════════════════════════════════
# M1 — bucketing negative control (leadv2-skill-rollup.sh :: bucket_for_skill)
# ══════════════════════════════════════════════════════════════════════════
M1_MUT="$ROOT/.nc-mutated-leadv2-skill-rollup.sh"
python3 - "$ROLLUP" "$M1_MUT" <<'PYM1'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    lines = f.readlines()
def_idx = None
next_def_idx = len(lines)
for i, line in enumerate(lines):
    if line.startswith('def bucket_for_skill('):
        def_idx = i
    elif def_idx is not None and line.startswith('def ') and i > def_idx:
        next_def_idx = i
        break
if def_idx is None:
    sys.exit('bucket_for_skill def not found')
anchor = "    count = len(window_rows)\n"
found_at = None
for i in range(def_idx, next_def_idx):
    if lines[i] == anchor:
        found_at = i
        break
if found_at is None:
    sys.exit('anchor not found inside bucket_for_skill body')
lines.insert(found_at + 1, "    count = 1  # M1-mutation: force every skill window-count non-zero\n")
with open(dst, 'w') as f:
    f.writelines(lines)
PYM1
if [[ $? -ne 0 ]]; then
  fail "M1 setup: mutation anchor not found (rollup.sh refactored? update this NC)"
else
  chmod +x "$M1_MUT"
  M1TSV="$ROOT/rollup-m1.tsv"
  bash "$M1_MUT" --since 30d --jsonl "$JSONL" --repo-root "$FIXREPO" \
    --skills-root "$SKILLROOT" --format tsv --out "$ROOT/m1.md" > "$M1TSV" 2>"$ROOT/m1.err"
  m1_rc=$?
  m1_bucket="$(awk -F'\t' '$1=="fixture-skill-never"{print $7}' "$M1TSV")"
  echo "[NC] M1 baseline(GREEN) bucket=NEVER_INVOKED  mutated(RED) rc=${m1_rc} bucket=${m1_bucket}"
  if [ "$m1_bucket" != "NEVER_INVOKED" ]; then
    pass "M1 mutation flips NEVER_INVOKED classification (suite would go red)"
  else
    fail "M1 mutation had no effect — bucket_for_skill() body anchor may be stale"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════
# M2 — collector idempotency negative control (event_id_for)
# ══════════════════════════════════════════════════════════════════════════
M2_MUT="$ROOT/.nc-mutated-leadv2-skill-telemetry-collect.sh"
python3 - "$COLLECT" "$M2_MUT" <<'PYM2'
import sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    lines = f.readlines()
def_idx = None
next_def_idx = len(lines)
for i, line in enumerate(lines):
    if line.startswith('def event_id_for('):
        def_idx = i
    elif def_idx is not None and line.startswith('def ') and i > def_idx:
        next_def_idx = i
        break
if def_idx is None:
    sys.exit('event_id_for def not found')
anchor = "    raw = '{}|{}'.format(session_id or '', uuid or '')\n"
found_at = None
for i in range(def_idx, next_def_idx):
    if lines[i] == anchor:
        found_at = i
        break
if found_at is None:
    sys.exit('anchor not found inside event_id_for body')
lines.insert(found_at + 1, "    raw = raw + '-' + str(__import__('random').randint(0, 999999999))  # M2-mutation\n")
with open(dst, 'w') as f:
    f.writelines(lines)
PYM2
if [[ $? -ne 0 ]]; then
  fail "M2 setup: mutation anchor not found (collector refactored? update this NC)"
else
  chmod +x "$M2_MUT"
  # the mutated copy sources leadv2-portable-lock.sh relative to its own
  # location (SCRIPT_DIR), so the helper must sit next to it in $ROOT too.
  cp "${SCRIPTS_DIR}/leadv2-portable-lock.sh" "$ROOT/leadv2-portable-lock.sh"
  M2JSONL="$ROOT/m2.jsonl"
  bash "$M2_MUT" --since 30d --transcripts-root "$TRANSCRIPTS" --repo-root "$FIXREPO" --out "$M2JSONL" >/dev/null
  m2_n1=$(wc -l < "$M2JSONL" | tr -d ' ')
  bash "$M2_MUT" --since 30d --transcripts-root "$TRANSCRIPTS" --repo-root "$FIXREPO" --out "$M2JSONL" >/dev/null
  m2_rc=$?
  m2_n2=$(wc -l < "$M2JSONL" | tr -d ' ')
  echo "[NC] M2 baseline(GREEN) rows_stable  mutated(RED) rc=${m2_rc} n1=${m2_n1} n2=${m2_n2}"
  if [ "$m2_n1" != "$m2_n2" ]; then
    pass "M2 mutation breaks idempotency (suite would go red)"
  else
    fail "M2 mutation had no effect — event_id_for() body anchor may be stale"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "SUMMARY: PASS=${PASS} FAIL=${FAIL}"
[ "$FAIL" -eq 0 ]
exit $?
