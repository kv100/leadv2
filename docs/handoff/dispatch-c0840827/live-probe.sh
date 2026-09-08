#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01);
# EXTRA_SUITE_MAP rows for the same stems live in tests/run-all.sh at the repo root.
# run-all-triggers: leadv2-dispatch-code leadv2-route-arbiter leadv2-routing.yaml leadv2-glm-policy-resolve.py
# Real registry reachability, hard pool/pin restrictions and argv capture.
# GLM/freepool remain on their existing adapters; incapable fable/code refuses.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT='/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/da195ecf5abc/plugins/leadv2'
DISPATCH_BIN="${PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"
ROUTING="${PLUGIN_ROOT}/config/leadv2-routing.yaml"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "${2:-}"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/arm-pool-reach.XXXXXX")"
trap '[[ "${POOLREACH_KEEP_LOGS:-0}" == "1" ]] || rm -rf "$TMP"' EXIT

bash -n "$DISPATCH_BIN" || { fail "bash syntax: dispatch"; printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"; exit 1; }
pass "bash syntax: dispatch"

HEALTHY='{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":20,"seven_day_pct":20}]}}'
CLAUDE_CAPPED='{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":99,"seven_day_pct":99}]}}'

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$ROUTE_TEST_QUOTA"\n' > "$TMP/live.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/free.sh"
cat > "$TMP/worker.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$REACH_CAPTURE"
printf 'PID=%s LABEL=t SESSION_ID=t\n' "$REACH_PID"
EOF
printf '#!/usr/bin/env bash\nprintf %%s "{\\"complexity\\":\\"simple\\",\\"estimate_source\\":\\"judge\\"}"\n' > "$TMP/task-judge.sh"
chmod +x "$TMP/live.sh" "$TMP/free.sh" "$TMP/worker.sh" "$TMP/task-judge.sh"

setup_repo() { # <dir>
  local repo="$1"
  mkdir -p "$repo/.claude/ref" "$repo/docs/leadv2" "$repo/docs/leadv2/tasks"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@e.com; git -C "$repo" config user.name t
  : > "$repo/seed"; git -C "$repo" add seed; git -C "$repo" commit -qm seed
  cp "$ROUTING" "$repo/.claude/ref/leadv2-routing.yaml"
}

# run <dispatch_bin> <repo> <suffix> <quota_json> [extra args...] -> stdout,
# with rc preserved in REACH_RC (never pipe this: exit codes are the M3 signal).
run_dispatch() {
  local bin="$1" repo="$2" suffix="$3" quota="$4"; shift 4
  local -a spawn_args=(--no-spawn)
  [[ "${REACH_SPAWN:-0}" == 1 ]] && spawn_args=()
  (cd "$repo" && LEADV2_LANE_WORK_ROOT="$repo" LEADV2_DISPATCH_LANE_WORKTREE_BIN="$TMP/free.sh" LEADV2_STATE_ROOT="$TMP/state-root-$suffix" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" GLM_POLICY_QUOTA_LIVE="$TMP/live.sh" LEADV2_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-dispatch-$suffix" \
    ROUTE_TEST_QUOTA="$quota" REACH_CAPTURE="$TMP/$suffix.argv" REACH_PID="$$" \
    CLAUDE_PROJECT_ROOT="$repo" LEADV2_PROJECT_ROOT="$repo" \
    LEADV2_DISPATCH_CACHE_DIR="$TMP/cache-$suffix" \
    LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 \
    LEADV2_REQUIRE_PHASES=0 \
    LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off \
    LEADV2_BURN_GOVERNOR=0 LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_TEST_CONTEXT=1 LEADV2_PULSE_MODE=0 LEADV2_ARM_LANE_PULSE_WATCH=0 LEADV2_SINGLE_LEAD_BEAT=0 \
    LEADV2_DISPATCH_COST_ESTIMATE=0 LEADV2_JOURNAL_BIN="$TMP/free.sh" LEADV2_EVENT_BIN="$TMP/free.sh" \
    LEADV2_TASK_JUDGE_BIN="$TMP/task-judge.sh" \
    LEADV2_DISPATCH_SUBSESSION_BIN="${PLUGIN_ROOT}/scripts/claude-subsession.sh" \
    bash "$bin" "Reply exactly P1B_LIVE_OK. Do not edit any files or invoke tools." \
      --kind plan --task-class light "${spawn_args[@]}" --writes src/x.py "$@" 2>&1)
}

expect_rc() { # <label> <actual> <want>
  [[ "$2" == "$3" ]] && { pass "$1 (rc=$2)"; return 0; }
  fail "$1" "rc=$2 want=$3"
  return 1
}


REPO_LIVE="$TMP/live-repo"; setup_repo "$REPO_LIVE"
mkdir -p "$REPO_LIVE/.claude/agents"
printf '%s\n' 'You are a probe. Reply P1B_LIVE_OK and stop. Do not use tools.' > "$REPO_LIVE/.claude/agents/developer.md"
QUOTA_LIVE="$(python3 - <<'PYQ'
import json
q=json.load(open('/tmp/p1b-live-quota/current.json'))
print(json.dumps({'anthropic':q, 'codex':{'status':'unknown'},'glm':{'status':'unknown'}}))
PYQ
)"
export LEADV2_SUBSESSION_MAX_TURNS=1 LEADV2_SUBSESSION_SLIM_MCP=0
out="$(REACH_SPAWN=1 run_dispatch "$DISPATCH_BIN" "$REPO_LIVE" live "$QUOTA_LIVE" --kind recon --pin-arm haiku --requested-profile work)"
rc=$?
printf '%s\nLIVE_DISPATCH_RC=%s\n' "$out" "$rc"
pid="$(printf '%s\n' "$out" | sed -n 's/.*handle=PID=\([0-9]*\).*/\1/p' | head -1)"
if [[ -n "$pid" ]]; then
  for ((i=0; i<45; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    echo "LIVE_WORKER_STOPPED_AT_BOUND pid=$pid"
  fi
fi
find "$REPO_LIVE/docs/handoff" -name developer.stream.jsonl -exec tail -c 2000 {} \;
exit "$rc"
