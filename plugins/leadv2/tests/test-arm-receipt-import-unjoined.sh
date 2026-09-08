#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-arm-receipts-import.sh
# tests/test-arm-receipt-import-unjoined.sh — offline tests for
# plugins/leadv2/scripts/leadv2-arm-receipts-import.sh (ARM-RECEIPTS-AND-HISTORICAL-IMPORT-01, P3 Part A).
#
# Builds a tiny 4-store fixture (one claude costs.yaml, two glm meta.yaml —
# one joinable, one not — one unjoinable freepool meta.yaml, one joinable
# codex rollout) with a KNOWN correct split, then asserts the printed tally
# line exactly: imported=3 unjoined=2 stores=claude:1,glm:2,freepool:1,codex:1.
# Asserting the tally (not just that 5 rows landed in the ledger) is the
# point — a join function that fabricates matches can still produce 5 rows
# while getting every single one wrong.
#
# E2E-KILLRATE-01 negative control this suite is the RED half of:
#   2. replace the identifier-existence join in resolve_decision_id() with
#      nearest-timestamp matching. The unjoinable glm/freepool runs (whose
#      cwd never names a real docs/handoff id) would then falsely join to
#      whichever real dispatch happens to be nearest in time, and the tally
#      would read imported=5 unjoined=0 — still 5 rows, still red here.
#
# Also asserts idempotency: a second run against the same ledger adds zero
# new records.
# Usage: bash tests/test-arm-receipt-import-unjoined.sh
# Exit 0 = all pass; non-zero = failure count.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORTER="${SELF_DIR}/../scripts/leadv2-arm-receipts-import.sh"

PASS=0
FAIL=0
pass() { printf -- 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() { printf -- 'FAIL: %s\n' "$1"; FAIL=$(( FAIL + 1 )); }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FX_REPO="${TMP}/repo"
FX_GLM="${TMP}/glm"
FX_FREEPOOL="${TMP}/freepool"
FX_CODEX="${TMP}/codex"
mkdir -p "${FX_REPO}/docs/handoff/dispatch-fixture-abc" \
         "${FX_GLM}/RUN1" "${FX_GLM}/RUN2" \
         "${FX_FREEPOOL}/RUN3" \
         "${FX_CODEX}/sub"

# --- claude store: one real dispatch dir, joined by construction -----------
cat > "${FX_REPO}/docs/handoff/dispatch-fixture-abc/costs.yaml" <<'YAML'
# leadv2 cost telemetry
- role: developer
  model: sonnet
  provider: claude
  session_id: sess-claude-1
  input_tokens: 100
  output_tokens: 200
  cost_usd: 0.01
  duration_sec: 30
  timestamp: 2026-09-01T00:00:00Z
  cache_hit_rate: null
  prompt_prefix_checksum: deadbeef
YAML

# --- glm: RUN1 cwd names the real dispatch dir -> joined --------------------
cat > "${FX_GLM}/RUN1/meta.yaml" <<YAML
run_id: RUN1
cwd: ${FX_REPO}/.claude/worktrees/fixture-abc
model: glm-5.3
status: success
turns: 5
duration_s: 60
tokens_in: 1000
tokens_out: 500
cache_read_input_tokens: 10
cache_creation_input_tokens: 5
usage_source: stream_proxy
usage_is_estimate: true
started_at: 2026-09-01T00:00:00Z
finished_at: 2026-09-01T00:01:00Z
YAML

# --- glm: RUN2 cwd names nothing real -> must stay unjoined ------------------
cat > "${FX_GLM}/RUN2/meta.yaml" <<'YAML'
run_id: RUN2
cwd: /tmp/somewhere-else/not-a-worktree
model: glm-5.3
status: failed
turns: 2
duration_s: 20
tokens_in: 50
tokens_out: 10
cache_read_input_tokens: 0
cache_creation_input_tokens: 0
usage_source: assistant_events
usage_is_estimate: false
started_at: 2026-09-01T00:00:00Z
finished_at: 2026-09-01T00:00:20Z
YAML

# --- freepool: RUN3 cwd names a worktree id with NO real dispatch dir -------
# This is the case a nearest-timestamp fallback is most tempted to "fix":
# a plausible-looking id that simply never had a real decision behind it.
cat > "${FX_FREEPOOL}/RUN3/meta.yaml" <<YAML
run_id: RUN3
cwd: ${FX_REPO}/.claude/worktrees/no-such-dispatch-id
model: freepool-default
status: failed
turns: 1
duration_s: 10
tokens_in: 5
tokens_out: 5
cache_read_input_tokens: 0
cache_creation_input_tokens: 0
usage_source: assistant_events
usage_is_estimate: false
started_at: 2026-09-01T00:00:00Z
finished_at: 2026-09-01T00:00:10Z
YAML

# --- codex: one rollout whose session_meta.cwd names the real dispatch -----
python3 - "${FX_CODEX}/sub/rollout-test.jsonl" "${FX_REPO}" <<'PY'
import json, sys
out_path, fx_repo = sys.argv[1], sys.argv[2]
cwd = fx_repo + "/.claude/worktrees/fixture-abc"
lines = [
    {"timestamp": "2026-09-01T00:00:00.000Z", "type": "session_meta",
     "payload": {"id": "codex-attempt-1", "session_id": "codex-sess-1", "cwd": cwd}},
    {"timestamp": "2026-09-01T00:00:01.000Z", "type": "turn_context",
     "payload": {"turn_id": "t1", "cwd": "/Users/x", "model": "gpt-5-codex"}},
    {"timestamp": "2026-09-01T00:00:05.000Z", "type": "event_msg",
     "payload": {"type": "token_count", "info": {"total_token_usage": {
         "input_tokens": 300, "cached_input_tokens": 20,
         "output_tokens": 40, "reasoning_output_tokens": 10, "total_tokens": 370}}}},
    {"timestamp": "2026-09-01T00:00:10.000Z", "type": "event_msg",
     "payload": {"type": "task_complete", "turn_id": "t1"}},
]
with open(out_path, "w") as fh:
    for l in lines:
        fh.write(json.dumps(l) + "\n")
PY

run_importer() {
  LEADV2_ARM_RECEIPTS_REPO_ROOT="${FX_REPO}" \
  LEADV2_ARM_RECEIPTS_LEDGER="${TMP}/ledger.jsonl" \
  LEADV2_ARM_RECEIPTS_GLM_ROOT="${FX_GLM}" \
  LEADV2_ARM_RECEIPTS_FREEPOOL_ROOT="${FX_FREEPOOL}" \
  LEADV2_ARM_RECEIPTS_CODEX_ROOT="${FX_CODEX}" \
  bash "${IMPORTER}"
}

out1="$(run_importer)"
tally1="$(printf '%s\n' "${out1}" | head -n 1)"
new1="$(printf '%s\n' "${out1}" | sed -n 's/^new_records=//p')"

expected_tally='imported=3 unjoined=2 stores=claude:1,glm:2,freepool:1,codex:1'
if [[ "${tally1}" == "${expected_tally}" ]]; then
  pass "tally: first run reports '${expected_tally}'"
else
  fail "tally: expected '${expected_tally}', got '${tally1}'"
fi

if [[ "${new1}" == "5" ]]; then
  pass "first_run_writes: first run appends all 5 walked records"
else
  fail "first_run_writes: expected new_records=5 on first run, got new_records=${new1}"
fi

# --- unjoined rows must carry usage_src=unjoined and a null decision_id -----
unjoined_shape="$(python3 -c '
import json, sys
n_unjoined = 0
bad = 0
with open(sys.argv[1]) as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        if rec.get("usage_src") == "unjoined":
            n_unjoined += 1
            if rec.get("decision_id") is not None:
                bad += 1
print("%d %d" % (n_unjoined, bad))
' "${TMP}/ledger.jsonl")"
read -r unjoined_count unjoined_bad <<< "${unjoined_shape}"
if [[ "${unjoined_count}" == "2" && "${unjoined_bad}" == "0" ]]; then
  pass "unjoined_shape: both unjoined rows carry usage_src=unjoined and a null decision_id"
else
  fail "unjoined_shape: unjoined_count=${unjoined_count} rows_with_a_decision_id=${unjoined_bad} (want 2 / 0)"
fi

# --- idempotency: a second run against the same ledger adds nothing --------
out2="$(run_importer)"
tally2="$(printf '%s\n' "${out2}" | head -n 1)"
new2="$(printf '%s\n' "${out2}" | sed -n 's/^new_records=//p')"

if [[ "${tally2}" == "${expected_tally}" ]]; then
  pass "tally: second run reports the same tally '${expected_tally}'"
else
  fail "tally: second run expected '${expected_tally}', got '${tally2}'"
fi

if [[ "${new2}" == "0" ]]; then
  pass "idempotent: second run adds zero new records"
else
  fail "idempotent: expected new_records=0 on second run, got new_records=${new2}"
fi

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
