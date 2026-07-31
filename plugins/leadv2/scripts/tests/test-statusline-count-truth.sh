#!/usr/bin/env bash
# STATUSLINE-COUNT-TRUTH-02: leadv2-lane-liveness.sh's --all discovery and
# resolve() state machine. Never runs against the real plugin tree -- see
# the containment pattern in test-lane-liveness-authoritative.sh
# (TEST-DESTROYS-PRODUCTION-SCRIPT-01): every helper here runs against a
# throwaway COPY of scripts/ under $tmp, and an EXIT tripwire re-checks the
# real repo's leadv2-lane-liveness.sh md5 so any escape aborts loudly
# instead of destroying it quietly. No lane id, task id, or suffix below is
# copied from a live snapshot -- all synthetic (dispatch-aaaaaaaa etc, or
# repeated-letter sig8 shapes that cannot collide with a real dispatch id).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
tmp="$(lv2_mktemp_dir statusline-count-truth)"; trap 'rm -rf "$tmp"' EXIT

PLUGIN_DIR="$tmp/plugin"
mkdir -p "$PLUGIN_DIR"
cp -a "${REAL_PLUGIN_DIR}/scripts" "$PLUGIN_DIR/"
case "$PLUGIN_DIR" in
  "$tmp"/*) ;;
  *) printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s did not resolve under the scratch root %s\n' "$PLUGIN_DIR" "$tmp" >&2; exit 90 ;;
esac
case "$PLUGIN_DIR" in
  "$REAL_PLUGIN_DIR"|"$REAL_PLUGIN_DIR"/*)
    printf '[TEST-SAFETY] ABORT: PLUGIN_DIR %s resolves inside the real plugin tree %s -- refusing to run\n' "$PLUGIN_DIR" "$REAL_PLUGIN_DIR" >&2
    exit 90
    ;;
esac

_lv2_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | awk '{print $1}'; }
REAL_HELPER="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
REAL_HELPER_MD5_BEFORE="$(_lv2_md5 "$REAL_HELPER")"
lv2_tripwire() {
  local after
  after="$(_lv2_md5 "$REAL_HELPER")"
  if [[ "$after" != "$REAL_HELPER_MD5_BEFORE" ]]; then
    printf '[TEST-SAFETY] FATAL: test mutated a production path %s\n  before=%s\n  after=%s\n' \
      "$REAL_HELPER" "$REAL_HELPER_MD5_BEFORE" "$after" >&2
    exit 91
  fi
  printf '[TEST-SAFETY] tripwire OK: %s unchanged (md5 %s before and after)\n' "$REAL_HELPER" "$after"
}
trap 'lv2_tripwire; rm -rf "$tmp"' EXIT

HELPER="${PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
repo="$tmp/repo"; state="$tmp/state"
mkdir -p "$repo/docs/leadv2" "$repo/docs/handoff" "$state"
printf 'sessions: []\n' > "$repo/docs/leadv2/active.yaml"

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '[PASS] %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '[FAIL] %s\n%s\n' "$1" "${2:-}"; }

run_all() {
  CODEX_TASK_SH=/bin/false LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$HELPER" --project-root "$repo" --all --json --no-codex
}
run_lane() {
  CODEX_TASK_SH=/bin/false LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" \
    bash "$HELPER" --project-root "$repo" --lane "$1" --json --no-codex
}
touch_at() { # <path> <epoch>
  : > "$1"
  python3 - "$1" "$2" <<'PY'
import os, sys
os.utime(sys.argv[1], (float(sys.argv[2]), float(sys.argv[2])))
PY
}
now="$(python3 -c 'import time; print(int(time.time()))')"

# ---------------------------------------------------------------------
# A6/R1: --no-codex is a real flag (never "unknown arg"), and never crashes
# even when CODEX_TASK_SH points at a binary that produces no usable output
# -- this exercises the provider_jobs() dict-vs-list fix directly (an empty
# CODEX_RAW used to return [] where every caller expects a dict, which
# --no-codex's own empty CODEX_RAW now hits on every single statusline
# repaint).
# ---------------------------------------------------------------------
out="$(run_all)"; rc=$?
if [[ $rc -eq 0 ]]; then ok "R1: --no-codex accepted, rc=0"; else bad "R1: --no-codex rejected" "rc=$rc"; fi
echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null \
  && ok "R1: --no-codex output is valid JSON (provider_jobs dict-vs-list fix holds)" \
  || bad "R1: --no-codex output is not valid JSON" "$out"

# ---------------------------------------------------------------------
# A8: zero lanes -> lanes=[], count_live=0 (present, not absent -- a real
# zero must be distinguishable from a broken/missing read).
# ---------------------------------------------------------------------
zero_check="$(echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["lanes"] == [], d["lanes"]
assert d["count_live"] == 0, d["count_live"]
print("ok")
' 2>&1)"
[[ "$zero_check" == "ok" ]] && ok "A8/R2: zero lanes -> lanes=[] and count_live=0 (present, not absent)" || bad "A8/R2 failed" "$zero_check"

# ---------------------------------------------------------------------
# A7/R0: a bare developer.stream.jsonl (no session.log/fanout.log, no
# active.yaml row) is discovered by --all. Pre-fix, --all only globbed
# session.log/fanout.log -- nothing in the live tree still writes those
# (leadv2-dispatch-code.sh/leadv2-fanout.sh/leadv2-fanout-lane-launcher.sh
# all write developer.stream.jsonl) -- so this lane was invisible.
# ---------------------------------------------------------------------
mkdir -p "$repo/docs/handoff/dispatch-aaaaaaaa"
touch_at "$repo/docs/handoff/dispatch-aaaaaaaa/developer.stream.jsonl" "$now"
r7="$(run_all)"
check7="$(echo "$r7" | python3 -c '
import json, sys
d = json.load(sys.stdin)
lanes = {r["lane"]: r for r in d["lanes"]}
assert lanes.get("dispatch-aaaaaaaa", {}).get("verdict") == "alive", lanes.get("dispatch-aaaaaaaa")
assert d["count_live"] == 1, d["count_live"]
print("ok")
' 2>&1)"
[[ "$check7" == "ok" ]] && ok "A7/R0: bare developer.stream.jsonl discovered by --all, count_live=1" || bad "A7/R0 failed" "$check7 || $r7"

# ---------------------------------------------------------------------
# D1 + composed-child-signal: the REAL live-tree shape is a parent dir with
# NOTHING in it, and its architect-prepass sibling dispatch-<sig8>-architect/
# holding the actual architect.stream.jsonl (claude-subsession.sh writes
# $HANDOFF_DIR/$ROLE.stream.jsonl, and the architect prepass's HANDOFF_DIR
# IS the -architect suffix dir, never the parent). The parent must resolve
# 'starting:' from that composed signal, and the child must NEVER appear as
# its own row (S0 fold).
# ---------------------------------------------------------------------
mkdir -p "$repo/docs/handoff/dispatch-bbbbbbbb" "$repo/docs/handoff/dispatch-bbbbbbbb-architect"
touch_at "$repo/docs/handoff/dispatch-bbbbbbbb-architect/architect.stream.jsonl" "$now"
r_d1="$(run_all)"
check_d1="$(echo "$r_d1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
lanes = {r["lane"]: r for r in d["lanes"]}
assert "dispatch-bbbbbbbb-architect" not in lanes, "child rendered its own row"
row = lanes.get("dispatch-bbbbbbbb")
assert row is not None, "parent never discovered"
assert row["verdict"].startswith("starting:"), row["verdict"]
print("ok")
' 2>&1)"
[[ "$check_d1" == "ok" ]] && ok "D1/R-6: prepass-only parent resolves starting: via composed child stream, child never its own row" || bad "D1/R-6 failed" "$check_d1 || $r_d1"

# ---------------------------------------------------------------------
# D2: a parent AND its -architect child BOTH writing the legacy
# session.log convention must fold to exactly ONE row (the parent), never
# two -- this is the double-count defect measured on the live tree (59 of
# 173 dispatch-* dirs were -architect siblings, each counted as its own
# lane pre-fix).
# ---------------------------------------------------------------------
mkdir -p "$repo/docs/handoff/dispatch-dddddddd" "$repo/docs/handoff/dispatch-dddddddd-architect"
touch_at "$repo/docs/handoff/dispatch-dddddddd/session.log" "$now"
touch_at "$repo/docs/handoff/dispatch-dddddddd-architect/session.log" "$now"
r_d2="$(run_all)"
check_d2="$(echo "$r_d2" | python3 -c '
import json, sys
d = json.load(sys.stdin)
lane_ids = [r["lane"] for r in d["lanes"]]
assert lane_ids.count("dispatch-dddddddd") == 1, lane_ids
assert "dispatch-dddddddd-architect" not in lane_ids, lane_ids
print("ok")
' 2>&1)"
[[ "$check_d2" == "ok" ]] && ok "D2: parent+child both counted -> exactly one row, the parent" || bad "D2 failed" "$check_d2 || $r_d2"

# ---------------------------------------------------------------------
# D3: a lane dir containing ONLY a hand-written .md (the lead's own
# review-critic-opus.md, touched hours after the worker died) must never
# resolve alive via a "newest file in the dir" fallback -- that fallback
# was deleted entirely, not just deprioritized.
# ---------------------------------------------------------------------
mkdir -p "$repo/docs/handoff/dispatch-eeeeeeee"
touch_at "$repo/docs/handoff/dispatch-eeeeeeee/review-critic-opus.md" "$now"
r_d3="$(run_lane dispatch-eeeeeeee)"
verdict_d3="$(echo "$r_d3" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])')"
[[ "$verdict_d3" != alive* ]] && ok "D3: hand-written .md alone never resolves alive (verdict=$verdict_d3)" \
  || bad "D3 failed -- resolved alive via newest-file fallback" "$r_d3"

# ---------------------------------------------------------------------
# D4: a stream older than ABANDON_MAX (default 3600s) is dead, not
# unbounded silent -- excluded from count_live and from the tail's digest
# (verdict no longer starts with 'silent:').
# ---------------------------------------------------------------------
mkdir -p "$repo/docs/handoff/dispatch-ffffffff"
touch_at "$repo/docs/handoff/dispatch-ffffffff/developer.stream.jsonl" "$((now-7200))"
r_d4="$(run_all)"
check_d4="$(echo "$r_d4" | python3 -c '
import json, sys
d = json.load(sys.stdin)
lanes = {r["lane"]: r for r in d["lanes"]}
v = lanes.get("dispatch-ffffffff", {}).get("verdict", "")
assert v.startswith("dead:"), v
assert not v.startswith("silent:"), v
' 2>&1)"
[[ -z "$check_d4" ]] && ok "D4: 7200s-old stream is dead:*, never unbounded silent:*" || bad "D4 failed" "$check_d4 || $r_d4"

# ---------------------------------------------------------------------
# R2/1b: count_live agrees with an INDEPENDENT re-derivation over the same
# lanes[] payload (alive+starting, children already excluded by the
# producer) -- proves the numerator has exactly one definition, not one
# computed twice that could silently drift apart.
# ---------------------------------------------------------------------
final_all="$(run_all)"
agree="$(echo "$final_all" | python3 -c '
import json, sys, re
d = json.load(sys.stdin)
FOLD = re.compile(r"^(dispatch-[0-9a-f]{8})-(.+)$")
def is_child(tid):
    m = FOLD.match(tid)
    return bool(m) and m.group(2) in ("architect",)
kept = [r for r in d["lanes"] if not is_child(r["lane"])]
independent = sum(1 for r in kept if r["verdict"] == "alive" or r["verdict"].startswith("starting:"))
assert d["count_live"] == independent, (d["count_live"], independent)
print("ok")
' 2>&1)"
[[ "$agree" == "ok" ]] && ok "R2/1b: count_live agrees with an independent fold over the same lanes[]" || bad "R2/1b disagreement" "$agree || $final_all"

# ---------------------------------------------------------------------
# R-1: performance -- --all must resolve well inside the statusline's
# ~2s repaint / 8s prober-timeout budget even at production scale (measured
# live: 173 dispatch-* dirs). 250 synthetic dispatch dirs here, each with
# its own developer.stream.jsonl, is a deliberately harder case than the
# live tree (which is mostly empty/child dirs) -- proves bsd_mtime -> pure
# os.stat (no per-lane subprocess) actually removed the bottleneck.
# ---------------------------------------------------------------------
perf_repo="$tmp/perf-repo"; mkdir -p "$perf_repo/docs/leadv2" "$perf_repo/docs/handoff"
printf 'sessions: []\n' > "$perf_repo/docs/leadv2/active.yaml"
for i in $(seq 1 250); do
  d="$perf_repo/docs/handoff/dispatch-perf$(printf '%06d' "$i")"
  mkdir -p "$d"
  printf '{"type":"assistant"}\n' > "$d/developer.stream.jsonl"
done
start_ns="$(python3 -c 'import time; print(time.time())')"
perf_out="$(CODEX_TASK_SH=/bin/false LEADV2_PROJECT_ROOT="$perf_repo" LEADV2_STATE_ROOT="$state" \
  bash "$HELPER" --project-root "$perf_repo" --all --json --no-codex)"
end_ns="$(python3 -c 'import time; print(time.time())')"
elapsed="$(python3 -c "print(${end_ns} - ${start_ns})")"
lane_count="$(echo "$perf_out" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["lanes"]))')"
if [[ "$lane_count" == "250" ]] && python3 -c "import sys; sys.exit(0 if ${elapsed} < 1.0 else 1)"; then
  ok "R-1: --all resolves 250 lanes in ${elapsed}s (< 1.0s budget)"
else
  bad "R-1: perf/count assertion failed" "lanes=$lane_count elapsed=${elapsed}s"
fi

printf '\n=== test-statusline-count-truth: pass=%s fail=%s ===\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
