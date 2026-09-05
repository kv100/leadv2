#!/usr/bin/env bash
# test-writeset-carousel.sh — WRITESET-CAROUSEL-01.
#
# An incumbent row with no declared write set means the overlap is UNKNOWN, not
# that it conflicts. The guard blocked it as hard as a proven path intersection,
# and because new placeholder rows appear faster than the 900s window closes,
# the refusal never lifted — it just moved to the next-youngest row. Measured on
# the live registry 2026-09-05T02:52Z: five rows were refusing every dispatch in
# the repo, aged 211-531s, and every one of them had **pid: None** — no process
# at all. Thirteen more of the same shape sat outside the window, warning.
#
# The fix asks the question that actually decides the danger: does this
# incumbent have a LIVE WORKER that might be writing right now? Only then is an
# unknown write set worth a refusal. A row with no pid, a dead pid, or a pid
# that belongs to an interactive LEAD session (the bystander-pid case: the
# liveness check honestly says "alive", because it is — it just is not a worker)
# falls through to the existing unknown policy, where LEADV2_WRITESET_ENFORCE
# still decides.
#
# run-all-triggers: leadv2-active-registry.sh
#
# WHAT IS REAL HERE. Every case drives the real leadv2_active_register against a
# real active.yaml in a scratch LEADV2_STATE_ROOT. Incumbent rows are written as
# real YAML in the real wire format — the layer below. Nothing stubs
# _lv2_ws_live_worker, _lv2_ws_pending, _proc_kind or the register op.
#
# DECLARED NEGATIVE CONTROLS (mutation-control/, tests/mutations/catalog.yaml),
# both applied by REGEX to a line INSIDE _lv2_ws_live_worker's body:
#   WRITESET-PIDLESS-ROW-COUNTS-AS-A-WORKER   the no-pid early return flips to
#     True, so a row with no process blocks again. Kills (1),(5),(6).
#   WRITESET-BYSTANDER-LEAD-COUNTS-AS-A-WORKER  the proc_kind test flips to
#     True, so a lead's own pid holds the lock again. Kills (3).
set -uo pipefail
export LEADV2_BURN_GOVERNOR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REGISTRY_SH="${SCRIPTS_DIR}/leadv2-active-registry.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; [[ -n "${FAKE_LEAD_PID:-}" ]] && kill "${FAKE_LEAD_PID}" 2>/dev/null' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# A process that looks exactly like an interactive lead to _proc_kind: its argv
# carries `claude --dangerously-skip-permissions` and no ` -p`, which is the
# same reading _proc_kind takes off a real lead session.
bash -c 'exec -a "claude --dangerously-skip-permissions" sleep 120' >/dev/null 2>&1 &
FAKE_LEAD_PID=$!
sleep 0.3

# newroot <name> -> a scratch project/state root with an empty registry
newroot(){ local r="$TMP/$1"; mkdir -p "$r/docs/leadv2"; printf '%s' "$r"; }

# seed_rows <root> <python-list-literal-of-row-dicts>
seed_rows(){ python3 - "$1/docs/leadv2/active.yaml" "$2" <<'PY'
import sys, yaml, datetime, ast
path, spec = sys.argv[1], sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc)
rows = []
for r in ast.literal_eval(spec):
    age = r.pop("age_s", 60)
    ts = (now - datetime.timedelta(seconds=age)).strftime("%Y-%m-%dT%H:%M:%SZ")
    row = {"session_id": "s-" + r["task_id"], "worktree": "/tmp/x", "branch": "b",
           "started_at": ts, "first_seen_at": ts, "phase": "spawning",
           "class": "Standard", "stale": False}
    row.update(r)
    rows.append(row)
yaml.dump({"meta": {}, "sessions": rows}, open(path, "w"), default_flow_style=False, sort_keys=False)
PY
}

# candidate <root> <writes> [enforce] -> prints "rc=<n>" then stderr
candidate(){
  local root="$1" writes="$2" enforce="${3:-warn}" err rc
  err="$(LEADV2_PROJECT_ROOT="$root" LEADV2_STATE_ROOT="$root" \
         LEADV2_WRITESET_PENDING_WINDOW_SEC=900 LEADV2_WRITESET_ENFORCE="$enforce" \
         bash -c 'source "$0"; leadv2_active_register "WS-CAND" Standard "$1" wt-cand false "" "" "$2"' \
         "$REGISTRY_SH" "$root" "$writes" 2>&1 >/dev/null)"; rc=$?
  printf 'rc=%d\n%s\n' "$rc" "$err"
}

# ── 1. THE CAROUSEL. A young, write-less, PID-LESS incumbent must not refuse.
R="$(newroot c1)"
seed_rows "$R" "[{'task_id':'INC-NOPID','pid':None,'age_s':300}]"
OUT="$(candidate "$R" "cand/b.txt")"
if [[ "$OUT" == rc=0* ]] && printf '%s' "$OUT" | grep -q 'pending downgraded.*reason=no_live_worker'; then
  ok "a write-less incumbent with NO process no longer refuses (and the downgrade is journaled)"
else
  bad "1: $(printf '%s' "$OUT" | tr '\n' ' ')"
fi

# ── 2. THE GUARD THAT MUST SURVIVE. A live process under the row is the whole
#      reason the pending rule exists — an unknown write set is only dangerous
#      when something might be writing it right now.
R="$(newroot c2)"
seed_rows "$R" "[{'task_id':'INC-LIVE','pid':$$,'age_s':60}]"
OUT="$(candidate "$R" "cand/b.txt")"
if [[ "$OUT" == rc=5* ]] && printf '%s' "$OUT" | grep -q 'reason=pending_resolution'; then
  ok "a write-less incumbent WITH a live process still refuses (rc=5, pending_resolution)"
else
  bad "2: $(printf '%s' "$OUT" | tr '\n' ' ')"
fi

# ── 3. THE BYSTANDER PID. A row whose pid belongs to an interactive lead is
#      alive and is not a worker. The liveness check was answering honestly and
#      the guard was reading the answer to the wrong question.
R="$(newroot c3)"
seed_rows "$R" "[{'task_id':'INC-LEADPID','pid':${FAKE_LEAD_PID},'age_s':60}]"
OUT="$(candidate "$R" "cand/b.txt")"
if [[ "$OUT" == rc=0* ]] && printf '%s' "$OUT" | grep -q 'proc_kind=interactive'; then
  ok "a live LEAD pid attached to a lane no longer holds the lock (proc_kind=interactive)"
else
  bad "3: $(printf '%s' "$OUT" | tr '\n' ' ')"
fi

# ── 4. DOWNGRADED IS NOT ALLOWED. The third state routes to the unknown policy,
#      not past it: LEADV2_WRITESET_ENFORCE=block still refuses, with its own
#      distinct code (6), never the conflict code (5).
R="$(newroot c4)"
seed_rows "$R" "[{'task_id':'INC-NOPID','pid':None,'age_s':300}]"
OUT="$(candidate "$R" "cand/b.txt" block)"
if [[ "$OUT" == rc=6* ]] && printf '%s' "$OUT" | grep -q 'writeset unknown'; then
  ok "the downgrade lands in the unknown policy, not past it (enforce=block still refuses, rc=6)"
else
  bad "4: $(printf '%s' "$OUT" | tr '\n' ' ')"
fi

# ── 5. NO LOOSENING OF A REAL CONFLICT. A declared, genuinely intersecting
#      write set still refuses with paths= — that is a proven fact about the
#      world and has nothing to do with who is alive.
R="$(newroot c5)"
seed_rows "$R" "[{'task_id':'INC-DECL','pid':None,'age_s':300,'writes':'cand/b.txt'}]"
OUT="$(candidate "$R" "cand/b.txt")"
if [[ "$OUT" == rc=5* ]] && printf '%s' "$OUT" | grep -q 'paths='; then
  ok "a PROVEN path overlap still refuses, pid or no pid (paths= named)"
else
  bad "5: $(printf '%s' "$OUT" | tr '\n' ' ')"
fi

# ── 6. THE MEASURED SHAPE. Five young pid-less rows is not a hypothetical: it
#      is what the live registry held at 02:52Z, and each one on its own was
#      enough to refuse every dispatch in the repo.
R="$(newroot c6)"
seed_rows "$R" "[{'task_id':'CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01','pid':None,'age_s':531},
                 {'task_id':'LANE-LIVENESS-PROVE-03','pid':None,'age_s':528},
                 {'task_id':'RESUME-LAND','pid':None,'age_s':526},
                 {'task_id':'WAVE-B1-SALVAGE-THE-SEVENTEEN-01','pid':None,'age_s':524},
                 {'task_id':'GATE-PROVES-ITS-OWN-CONTROL-01','pid':None,'age_s':211}]"
OUT="$(candidate "$R" "cand/b.txt")"
if [[ "$OUT" == rc=0* ]] && [[ "$(printf '%s' "$OUT" | grep -c 'no_live_worker')" -eq 5 ]]; then
  ok "the live 02:52Z registry shape (5 young pid-less rows) stops blocking, and all 5 are named"
else
  bad "6: $(printf '%s' "$OUT" | tr '\n' ' ')"
fi

printf '[WRITESET-CAROUSEL] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
