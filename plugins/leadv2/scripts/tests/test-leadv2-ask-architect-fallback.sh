#!/usr/bin/env bash
# ASK-ARCHITECT-FALLBACK-01: on question timeout, an architect decides instead
# of parking straight to a human. Stubs the real claude-subsession.sh call
# (too slow/live for a smoke test) via LEADV2_ASK_ARCHITECT_BIN, mimicking its
# real contract: write docs/handoff/<task-id>/architect.full.md and exit 0.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASK_SH="${SCRIPT_DIR}/../leadv2-ask.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

new_fixture() {
  local root="$1"
  mkdir -p "$root/docs/leadv2" "$root/docs/handoff"
  cat >"$root/docs/tasks.yaml" <<'YAML'
tasks:
  - id: ST-ARCH-SIM
    title: Simulated architect-decided timeout
    lane: action
    status: in_progress
    claim: {by: lane-arch, lease_expires: null}
YAML
}

# ── Case 1: stubbed architect succeeds -> decided_by=architect, rc=0 ────────
ROOT1="$TMP_DIR/ok"; STATE1="$TMP_DIR/state-ok"; new_fixture "$ROOT1"
STUB_OK="$TMP_DIR/stub-architect-ok.sh"
cat >"$STUB_OK" <<'EOF'
#!/usr/bin/env bash
# Mimics claude-subsession.sh's real contract: write the artifact to the
# handoff dir, never to stdout (PREPASS-READS-ARTIFACT-01).
TASK_ID=""; PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) TASK_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done
ADIR="${PROJECT_ROOT}/docs/handoff/${TASK_ID}"
mkdir -p "$ADIR"
{
  printf 'DECISION_OPTION: risky\n'
  printf 'RATIONALE: precedent shows the risky path is reversible within 1h\n'
  printf 'DELIVERABLE_COMPLETE\n'
} > "${ADIR}/architect.full.md"
exit 0
EOF
chmod +x "$STUB_OK"

out="$(env -u LEADV2_PROJECT_ROOT LEADV2_STATE_ROOT="$STATE1" PROJECT_ROOT="$ROOT1" LEADV2_ASK_POLL_INTERVAL=0.05 \
  LEADV2_ASK_ARCHITECT_BIN="$STUB_OK" \
  bash "$ASK_SH" ST-ARCH-SIM 'Use reversible route?' --option 'safe|Leave unchanged' --option 'risky|Publish now' \
  --timeout 1 2>"$TMP_DIR/ok.err")"
qfile="$(find "$STATE1/questions" -name 'q-*.yaml' -print -quit)"
grep -q '^status: timed_out$' "$qfile"
grep -q 'selected: risky' "$qfile"
grep -q 'decided_by: architect' "$qfile"
grep -q 'rationale: precedent shows the risky path is reversible within 1h' "$qfile"
grep -q 'architect decided risky' "$ROOT1/docs/leadv2/tasks/ST-ARCH-SIM/journal.md"
[[ "$out" == risky ]]

# ── Case 2: stubbed architect fails -> falls back to declared default ───────
ROOT2="$TMP_DIR/fail"; STATE2="$TMP_DIR/state-fail"; new_fixture "$ROOT2"
STUB_FAIL="$TMP_DIR/stub-architect-fail.sh"
cat >"$STUB_FAIL" <<'EOF'
#!/usr/bin/env bash
echo "[stub] architect unavailable" >&2
exit 1
EOF
chmod +x "$STUB_FAIL"

out2="$(env -u LEADV2_PROJECT_ROOT LEADV2_STATE_ROOT="$STATE2" PROJECT_ROOT="$ROOT2" LEADV2_ASK_POLL_INTERVAL=0.05 \
  LEADV2_ASK_ARCHITECT_BIN="$STUB_FAIL" \
  bash "$ASK_SH" ST-ARCH-SIM 'Use reversible route?' --option 'safe|Leave unchanged' --option 'risky|Publish now' \
  --default-option safe --timeout 1 2>"$TMP_DIR/fail.err")"
qfile2="$(find "$STATE2/questions" -name 'q-*.yaml' -print -quit)"
grep -q 'decided_by: timeout_default' "$qfile2"
[[ "$out2" == safe ]]

# ── Case 3: LEADV2_ASK_ARCHITECT_FALLBACK=0 restores pre-fallback behavior ──
ROOT3="$TMP_DIR/rollback"; STATE3="$TMP_DIR/state-rollback"; new_fixture "$ROOT3"
out3="$(env -u LEADV2_PROJECT_ROOT LEADV2_STATE_ROOT="$STATE3" PROJECT_ROOT="$ROOT3" LEADV2_ASK_POLL_INTERVAL=0.05 \
  LEADV2_ASK_ARCHITECT_BIN="$STUB_OK" LEADV2_ASK_ARCHITECT_FALLBACK=0 \
  bash "$ASK_SH" ST-ARCH-SIM 'Use reversible route?' --option 'safe|Leave unchanged' --option 'risky|Publish now' \
  --default-option safe --timeout 1 2>"$TMP_DIR/rollback.err")"
qfile3="$(find "$STATE3/questions" -name 'q-*.yaml' -print -quit)"
grep -q 'decided_by: timeout_default' "$qfile3"
! grep -q 'decided_by: architect' "$qfile3"
[[ "$out3" == safe ]]

# ── Case 4: LEADV2_ASK_ARCHITECT_FALLBACK=0 restores the 1800s default too ──
# (BLOCKING :76 — one flag = full old behavior, not just the disabled
# architect step; help text is derived from the same constant, MINOR :67).
help_default="$(bash "$ASK_SH" 2>&1 >/dev/null || true)"
grep -q 'sec=900' <<<"$help_default"
help_rollback="$(LEADV2_ASK_ARCHITECT_FALLBACK=0 bash "$ASK_SH" 2>&1 >/dev/null || true)"
grep -q 'sec=1800' <<<"$help_rollback"

# ── Case 5: a founder answer landing DURING the architect call wins the race ──
ROOT4="$TMP_DIR/race"; STATE4="$TMP_DIR/state-race"; new_fixture "$ROOT4"
STUB_SLOW="$TMP_DIR/stub-architect-slow.sh"
cat >"$STUB_SLOW" <<'EOF'
#!/usr/bin/env bash
TASK_ID=""; PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
while [[ $# -gt 0 ]]; do
  case "$1" in --task-id) TASK_ID="$2"; shift 2 ;; *) shift ;; esac
done
sleep 2
ADIR="${PROJECT_ROOT}/docs/handoff/${TASK_ID}"; mkdir -p "$ADIR"
{ printf 'DECISION_OPTION: risky\nRATIONALE: architect would have picked risky\n'; } > "${ADIR}/architect.full.md"
exit 0
EOF
chmod +x "$STUB_SLOW"

env -u LEADV2_PROJECT_ROOT LEADV2_STATE_ROOT="$STATE4" PROJECT_ROOT="$ROOT4" LEADV2_ASK_POLL_INTERVAL=0.05 \
  LEADV2_ASK_ARCHITECT_BIN="$STUB_SLOW" \
  bash "$ASK_SH" ST-ARCH-SIM 'Use reversible route?' --option 'safe|Leave unchanged' --option 'risky|Publish now' \
  --timeout 1 >"$TMP_DIR/race.out" 2>"$TMP_DIR/race.err" &
race_pid=$!
qid4=""
for _ in $(seq 1 100); do
  # `|| true`: grep exits 1 while the qid line hasn't been written yet (every
  # early iteration) — under `set -o pipefail` that would abort the whole
  # script via errexit on a bare assignment, not just fail this iteration.
  qid4="$(grep -oE 'qid=q-[0-9a-f]+' "$TMP_DIR/race.err" 2>/dev/null | head -1 | cut -d= -f2 || true)"
  [[ -n "$qid4" ]] && break
  sleep 0.05
done
[[ -n "$qid4" ]] || { printf 'FAIL: no qid observed for race test\n' >&2; exit 1; }
sleep 1.1   # let the 1s poll deadline pass so ask.sh is mid architect-decide (stub sleeps 2s)
env -u LEADV2_PROJECT_ROOT LEADV2_STATE_ROOT="$STATE4" bash "${SCRIPT_DIR}/../leadv2-answer.sh" "$qid4" safe >/dev/null
wait "$race_pid"
out4="$(cat "$TMP_DIR/race.out")"
qfile4="$(find "$STATE4/questions" -name 'q-*.yaml' -print -quit)"
grep -q 'decided_by: founder' "$qfile4"
! grep -q 'decided_by: architect' "$qfile4"
[[ "$out4" == safe ]]

# ── Case 6: legacy-store degrade path records decided_by before returning ──
# (MAJOR :341-360 — the degrade path previously left the pending record
# unresolved). Force the V2 control-plane write to fail by pre-occupying its
# target path with a plain file, so ask.sh's own `mkdir -p "$QDIR"` fails.
ROOT5="$TMP_DIR/legacy"; STATE5="$TMP_DIR/state-legacy"; new_fixture "$ROOT5"
mkdir -p "$STATE5"; : > "$STATE5/questions"

out5="$(env -u LEADV2_PROJECT_ROOT LEADV2_STATE_ROOT="$STATE5" PROJECT_ROOT="$ROOT5" LEADV2_ASK_POLL_INTERVAL=0.05 \
  LEADV2_ASK_ARCHITECT_BIN="$STUB_FAIL" \
  bash "$ASK_SH" ST-ARCH-SIM 'Use reversible route?' --option 'safe|Leave unchanged' --option 'risky|Publish now' \
  --default-option safe --timeout 1 2>"$TMP_DIR/legacy.err")"
legacy_answered="$(find "$ROOT5/docs/handoff" -name '*-answered.yaml' -print -quit)"
[[ -n "$legacy_answered" ]] || { printf 'FAIL: no legacy answered record written\n' >&2; exit 1; }
grep -q 'decided_by: timeout_default' "$legacy_answered"
grep -q '^chosen: safe$' "$legacy_answered"
grep -q '^status: timed_out$' "$legacy_answered"
[[ "$out5" == safe ]]

printf 'PASS: architect decides on timeout (rc=0, rationale recorded); architect failure falls back to default; LEADV2_ASK_ARCHITECT_FALLBACK=0 rolls back timeout default to 1800s too; founder answer mid-architect-call wins the race; legacy-store degrade path records decided_by\n'
