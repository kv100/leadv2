#!/usr/bin/env bash
# leadv2-cost-actuals.sh — ARBITER-LEARNS-WHAT-WORK-COSTS-01 (founder order
# 2026-09-12, row 4c06462a1a71): the WRITE half of the observed-cost loop.
#
# A cost estimate is written BEFORE the arm is chosen (leadv2-cost-estimate.sh,
# journaled as `cost_estimate_recorded ... phase=pre_arm_selection`), and until
# now nothing ever recorded what the dispatch ACTUALLY spent, so the arbiter's
# matrix price was the whole answer. This library records the actual, at
# dispatch terminal state, into the ONE journal the dispatcher already writes
# and the arbiter already reads (the per-repo events JSONL that
# ROUTE_ARBITER_EVENTS_JOURNAL points the arbiter at) -- not a second store:
# two writers for one number drift, and this repo has already paid for that.
#
# One entry point:
#   leadv2_cost_actual_record <repo-slug> <sig8> <terminal> <cause> \
#       [class] [work_kind] [model] [tokens]
#
# What it does:
#   1. Reads worker_spawned rows for <sig8> from the same events journal the
#      emitter writes ("<LEADV2_EVENT_LOG_DIR|~/.claude/cache/leadv2-events>/
#      <repo>.jsonl") -- the attribution rule failure memory and the spend
#      forecast already use: one journal, one rule.
#   2. Derives the observed spend: arm = LAST spawn's arm for the sig (a
#      re-dispatch that switched arms prices the arm that actually ran last),
#      rounds = spawn count for the sig (a task re-dispatched 3 times counts
#      3 -- the exact "burns three rounds on a cheap arm" signal the founder
#      named), wall_s = first spawn -> now.
#   3. Appends ONE kind=cost_actual row via leadv2-event.sh (fail-open, same
#      `|| true` licence every emit uses; the emitter's own test-context guard
#      refuses fixture writes to the real journal, so suites cannot pollute
#      live history), and prints a `cost_actual_recorded ...` k=v line on
#      stdout for the caller to `emit decision` -- the actual lands BESIDE the
#      estimate in the same decision journal, same shape, same funnel.
#
# Skips (prints nothing, rc 0) when the sig has NO spawned rows: a refusal
# before any spawn burned no arm work, and failure_memory already owns the
# refusal signal. Tokens are stamped when passed, `-` otherwise -- glm/codex
# report no per-task token telemetry today; a caller that has one (claude
# streams) passes it.
#
# Fail-open by design: a broken python3, an unreadable journal or a missing
# emitter must never change a terminal verdict -- the row is observability for
# the NEXT dispatch, not a gate on THIS one.
set -uo pipefail

# shellcheck source=leadv2-portable-lock.sh
# (no lock needed here: the only write goes through leadv2-event.sh, which
# takes the journal's own seq lock.)

leadv2_cost_actuals_event_bin() {
  printf '%s' "${LEADV2_COST_ACTUAL_EVENT_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../leadv2-event.sh}"
}

# leadv2_lane_token_total <repo-root> <sig8> — the lane's REAL token total.
#
# QUOTA-TELEMETRY-CANNOT-PRICE-AN-ARM-01: cost_actual_recorded.tokens was `-`
# in 100% of live rows (48/48, 2026-09-13) because neither caller computed
# it. The counts already exist in two places — this just joins them, cheapest
# and most direct first:
#   (a) the lane's costs.yaml — leadv2-cost-flush.sh's own extraction of the
#       workers' stream-json usage (a DIRECT observation, immune to
#       turn_events' 48h retention). Pending .cost-pending.yaml markers are
#       flushed first (same script, idempotent by session_id) so a terminal
#       that fires before the daemon's sweep still sees them.
#   (b) SUM(input+output) over burn turn_events for the session ids in the
#       lane's sessions.map — an inference, valid only inside the 48h window.
#   (c) neither -> `-`. NEVER 0: 0 claims the lane was free, `-` claims we
#       do not know — a false zero poisons the observed-cost loop with free
#       lanes (lane decision D5).
# Prints the integer, or `-`. rc 0 ALWAYS: telemetry must never gate a
# terminal verdict (same licence as leadv2_cost_actual_record).
leadv2_lane_token_total() { # <repo-root> <sig8>
  local root="${1:-}" sig8="${2:-}" total=""
  [[ -n "$root" && -n "$sig8" ]] || { printf -- '-'; return 0; }
  local handoff="$root/docs/handoff/dispatch-$sig8"

  # (a) costs.yaml, flushing any still-pending markers through the EXISTING
  # extraction (never a second parser).
  local flush="${LEADV2_COST_FLUSH_SH:-}"
  [[ -n "$flush" ]] || flush="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../leadv2-cost-flush.sh"
  if [[ -d "$handoff" && -f "$flush" ]]; then
    PROJECT_ROOT="$root" bash "$flush" "$handoff" >/dev/null 2>&1 || true
  fi
  if [[ -f "$handoff/costs.yaml" ]]; then
    total="$(python3 - "$handoff/costs.yaml" <<'PY' 2>/dev/null
import re, sys
# Flat reader on purpose: costs.yaml rows are printed by ONE writer
# (leadv2-cost-flush.sh) in ONE shape, and PyYAML is a user-only install on
# this fleet — a lib sourced by every dispatch must not depend on it.
tot, seen = 0, False
with open(sys.argv[1]) as fh:
    for line in fh:
        m = re.match(r"\s*(input_tokens|output_tokens):\s*([0-9]+)\s*$", line)
        if m:
            tot += int(m.group(2))
            seen = True
print(tot if seen else "")
PY
)"
    [[ "$total" =~ ^[0-9]+$ && "$total" != "0" ]] || total=""
  fi

  # (b) turn_events over the lane's session ids (sessions.map col 3).
  if [[ -z "$total" && -f "$handoff/sessions.map" ]]; then
    total="$(python3 - "$handoff/sessions.map" <<'PY' 2>/dev/null
import os, re, sqlite3, sys
sids = []
with open(sys.argv[1]) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 3 and re.match(r"^[0-9a-f-]{36}$", parts[2]):
            sids.append(parts[2])
if not sids:
    raise SystemExit(0)
db = os.path.expanduser(os.environ.get("LEADV2_BURN_DB", "~/.claude/burn/history.db"))
if not os.path.exists(db):
    raise SystemExit(0)
conn = sqlite3.connect(db, timeout=2)
try:
    conn.execute("PRAGMA busy_timeout=2000")
    q = ",".join("?" * len(sids))
    row = conn.execute(
        "SELECT COALESCE(SUM(input + output), 0) FROM turn_events "
        "WHERE session_id IN (%s)" % q, sids).fetchone()
    tot = int(row[0]) if row else 0
    if tot > 0:
        print(tot)
finally:
    conn.close()
PY
)"
    [[ "$total" =~ ^[0-9]+$ && "$total" != "0" ]] || total=""
  fi

  # (c) unknown — a dash, never a fabricated zero.
  printf -- '%s' "${total:--}"
}

leadv2_cost_actual_record() { # <repo> <sig8> <terminal> <cause> [class] [kind] [model] [tokens]
  local repo="${1:-}" sig8="${2:-}" terminal="${3:-}" cause="${4:-}"
  local cls="${5:-unknown}" wk="${6:-code}" model="${7:-unknown}" tokens="${8:--}"
  [[ -n "$repo" && -n "$sig8" ]] || return 0
  # A non-numeric tokens value is an unknown, not a measurement (D5/R5):
  # reject to `-` before it can reach the journal or the arbiter's reader.
  [[ "$tokens" =~ ^[0-9]+$ ]] || tokens="-"
  local evt_bin journal
  evt_bin="$(leadv2_cost_actuals_event_bin)"
  [[ -f "$evt_bin" ]] || return 0
  journal="${LEADV2_EVENT_LOG_DIR:-${HOME}/.claude/cache/leadv2-events}/${repo}.jsonl"

  # Derive rounds/arm/wall from the journal itself. rc 1 = no spawns for this
  # sig -> nothing burned on an arm -> no row (documented skip, not an error).
  local derived
  derived="$(python3 - "$journal" "$sig8" <<'PY' 2>/dev/null
import json, sys, datetime
path, sig = sys.argv[1], sys.argv[2]
def _ts(s):
    try: return datetime.datetime.strptime(s, '%Y-%m-%dT%H:%M:%SZ')
    except Exception: return None
spawns = []
try:
    with open(path) as f:
        for line in f:
            try: r = json.loads(line)
            except Exception: continue
            if str(r.get('kind') or '') != 'worker_spawned': continue
            if str(r.get('task') or '') != sig: continue
            arm = str(r.get('arm') or '')
            t = _ts(str(r.get('ts') or ''))
            if arm and t is not None: spawns.append((str(r.get('ts') or ''), arm, t))
except Exception:
    sys.exit(1)
if not spawns: sys.exit(1)
spawns.sort()
import time
now = datetime.datetime.utcnow()
wall = int((now - spawns[0][2]).total_seconds())
if wall < 0: wall = 0
print('%s %d %d' % (spawns[-1][1], len(spawns), wall))
PY
)" || return 0
  local arm rounds wall_s
  arm="$(printf '%s' "$derived" | awk '{print $1}')"
  rounds="$(printf '%s' "$derived" | awk '{print $2}')"
  wall_s="$(printf '%s' "$derived" | awk '{print $3}')"
  [[ -n "$arm" && "$rounds" =~ ^[0-9]+$ && "$wall_s" =~ ^[0-9]+$ ]] || return 0

  # One space/'='/',' inside a value would corrupt the k=v detail the reader
  # parses -- same sanitize pass model_select_telemetry applies to its cells.
  local cell
  for cell in cls wk model terminal cause tokens; do
    printf -v "$cell" '%s' "$(printf '%s' "${!cell}" | tr ' \t=,\r\n' '_')"
  done

  # Machine surface: the events journal (locked, rotated, test-guarded by the
  # emitter itself).
  bash "$evt_bin" emit --repo "$repo" --kind cost_actual --task "$sig8" --arm "$arm" \
    --detail "class=${cls} kind=${wk} model=${model} rounds=${rounds} wall_s=${wall_s} terminal=${terminal} cause=${cause} tokens=${tokens}" \
    >/dev/null 2>&1 || true
  # Human/decision surface: printed for the caller's `emit decision`, landing
  # beside cost_estimate_recorded in the same journal.
  printf 'cost_actual_recorded task=%s arm=%s model=%s rounds=%s wall_s=%s terminal=%s cause=%s class=%s kind=%s tokens=%s' \
    "$sig8" "$arm" "$model" "$rounds" "$wall_s" "$terminal" "$cause" "$cls" "$wk" "$tokens"
  return 0
}
