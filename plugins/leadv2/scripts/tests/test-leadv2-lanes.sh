#!/usr/bin/env bash
# FOUNDER-LANE-VIEW-01: the founder lane view judges liveness by PROCESS
# existence, folds child prepass ids into their parent, ignores lanes that
# merely mention an id, and hides artifact-stale dead lanes.  Fully offline:
# the ps snapshot comes from a committed fixture via LEADV2_LANE_VIEW_PS_FILE.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
tmp="$(lv2_mktemp_dir lane-view)"; trap 'rm -rf "$tmp"' EXIT

FIXTURE_PS="${REAL_PLUGIN_DIR}/scripts/tests/fixtures/lane-view-ps.txt"
LANES="${REAL_PLUGIN_DIR}/scripts/leadv2-lanes.sh"
LIVENESS="${REAL_PLUGIN_DIR}/scripts/leadv2-lane-liveness.sh"
STATE_PATH="${REAL_PLUGIN_DIR}/scripts/leadv2-state-path.sh"

# Fixture repo: handoff dirs with controlled artifact mtimes. aaaaaaaa is the
# 886a5711 regression shape — live processes, ZERO artifacts. dddddddd has a
# 19-day-old artifact and no process (must NOT print). bbbbbbbb/eeeeeeee have
# fresh/stale-ish artifacts to pin the ordering.
repo="$tmp/repo"; state="$tmp/state"
mkdir -p "$repo/docs/handoff" "$repo/docs/leadv2/tasks/dispatch-eeeeeeee" "$state"
active="$(LEADV2_PROJECT_ROOT="$repo" LEADV2_STATE_ROOT="$state" PROJECT_ROOT="$repo" bash "$STATE_PATH" active.yaml)"
mkdir -p "$(dirname "$active")"; printf 'sessions: []\n' > "$active"
for lane in dispatch-aaaaaaaa dispatch-bbbbbbbb dispatch-dddddddd dispatch-eeeeeeee; do
  mkdir -p "$repo/docs/handoff/$lane"
done
touch "$repo/docs/handoff/dispatch-aaaaaaaa/.close" # dotfile: must NOT count as last artifact
printf 'title: dispatch ledger sweep\n' > "$repo/docs/handoff/dispatch-bbbbbbbb/context.yaml"
printf 'verdict=changes_requested\n' > "$repo/docs/handoff/dispatch-bbbbbbbb/review-gate.md"
printf '# FOUNDER-LANE-VIEW-01 mission\n' > "$repo/docs/handoff/dispatch-eeeeeeee/lane-mission.md"
printf '2026-08-17 phase=deploy lane settled\n' > "$repo/docs/leadv2/tasks/dispatch-eeeeeeee/journal.md"
python3 - "$repo" <<'PY'
import os, sys, time
repo = sys.argv[1]
now = time.time()
# Pin EVERY depth-1 file of each lane dir to the lane's artifact age so the
# "newest artifact" pick is deterministic (context.yaml etc. are fresh from
# the heredocs above and would otherwise win with age 0).
AGE = {"dispatch-bbbbbbbb": 30, "dispatch-dddddddd": 19 * 86400,
       "dispatch-eeeeeeee": 3600}
for lane, age_s in AGE.items():
    hdir = os.path.join(repo, "docs/handoff", lane)
    for name in os.listdir(hdir):
        path = os.path.join(hdir, name)
        if os.path.isfile(path):
            os.utime(path, (now - age_s, now - age_s))
PY

pass=0
check() { # <haystack> <needle> <label>  — needle must be present
  grep -q -- "$2" <<<"$1" && { printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1)); } || \
    { printf '[TEST] FAIL: %s\n-- got --\n%s\n' "$3" "$1" >&2; exit 1; }
}
absent() { # <haystack> <needle> <label>  — needle must NOT be present
  ! grep -q -- "$2" <<<"$1" && { printf '[TEST] PASS: %s\n' "$3"; pass=$((pass+1)); } || \
    { printf '[TEST] FAIL: %s\n-- unexpected --\n%s\n' "$3" "$1" >&2; exit 1; }
}

run_lanes() { # extra args after --repo fixture root
  LEADV2_LANE_VIEW_PS_FILE="$FIXTURE_PS" LEADV2_NO_COLOR=1 \
    bash "$LANES" --repo "$repo" --no-color "$@"
}

out="$(run_lanes)"

# 1. Live process + zero artifacts prints (the dispatch-886a5711 regression).
check "$out" 'dispatch-aaaaaaaa' 'lane with live process and zero artifacts prints'
absent "$out" 'dead:' 'no dead: rows in the live view'
# 2. Old artifact + no process does not print.
absent "$out" 'dispatch-dddddddd' '19-day-old artifact with no process does not print'
# Runner allowlist: a grep that mentions an id invents no lane.
absent "$out" 'dispatch-ffffffff' 'a command that merely mentions an id creates no lane'
# 5. Child prepass id folds into its parent — never its own row.
[[ "$(grep -c 'dispatch-aaaaaaaa' <<<"$out")" -eq 1 ]] && \
  { printf '[TEST] PASS: child id folds into parent (one aaaaaaaa row)\n'; pass=$((pass+1)); } || \
  { printf '[TEST] FAIL: child id folds into parent\n%s\n' "$out" >&2; exit 1; }
# Enrichment columns: title, gate, phase all render.
check "$out" 'dispatch ledger sweep' 'context.yaml title renders'
check "$out" 'gate:changes_requested' 'review-gate verdict renders'
check "$out" 'deploy' 'journal phase= token renders'
# 3. Ordering: newest artifact first; artifactless lane after artifact lanes.
line_b="$(grep -n 'dispatch-bbbbbbbb' <<<"$out" | cut -d: -f1)"
line_e="$(grep -n 'dispatch-eeeeeeee' <<<"$out" | cut -d: -f1)"
line_a="$(grep -n 'dispatch-aaaaaaaa' <<<"$out" | cut -d: -f1)"
[[ "$line_b" -lt "$line_e" && "$line_e" -lt "$line_a" ]] && \
  { printf '[TEST] PASS: rows ordered newest-artifact-first, artifactless last\n'; pass=$((pass+1)); } || \
  { printf '[TEST] FAIL: ordering (b=%s e=%s a=%s)\n%s\n' "$line_b" "$line_e" "$line_a" "$out" >&2; exit 1; }

# JSON shape + pgid closure: the python telemetry child (pid 400002, no lane
# id in argv) and the folded architect child (400003) both join aaaaaaaa.
js="$(run_lanes --json)"
check "$js" '"count_live": 3' 'json count_live counts folded lanes only'
pids="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(str(p) for l in d["lanes"] if l["lane"]=="dispatch-aaaaaaaa" for p in l["pids"]))' <<<"$js")"
check "$pids" '400001 400002 400003' 'pgid closure + fold collect all three aaaaaaaa pids'
check "$js" '"last_artifact": null' 'artifactless lane reports last_artifact null'

# Zero lanes: exit 0, prints the no-live-lanes line.
empty="$tmp/empty-ps.txt"; : > "$empty"
none="$(LEADV2_LANE_VIEW_PS_FILE="$empty" LEADV2_NO_COLOR=1 bash "$LANES" --repo "$repo" --no-color)"
check "$none" 'no live lanes' 'zero live lanes prints no live lanes, exit 0'

# 4. --all delegates verbatim: identical bytes to the liveness script itself.
codex_stub="$tmp/codex-task.sh"
cat > "$codex_stub" <<'SH'
#!/usr/bin/env bash
printf '{"workspaceRoot":"x","running":[],"recent":[]}\n'
SH
chmod +x "$codex_stub"
liveness_root="$tmp/liveness-repo"
mkdir -p "$liveness_root/docs/handoff" "$liveness_root/docs/leadv2"
cp -a "$repo/docs/handoff/." "$liveness_root/docs/handoff/"
all_a="$(LEADV2_PROJECT_ROOT="$liveness_root" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$codex_stub" \
  bash "$LANES" --all --project-root "$liveness_root" 2>&1)"
all_b="$(LEADV2_PROJECT_ROOT="$liveness_root" LEADV2_STATE_ROOT="$state" CODEX_TASK_SH="$codex_stub" \
  bash "$LIVENESS" --all --project-root "$liveness_root" 2>&1)"
if [[ "$all_a" == "$all_b" ]]; then
  printf '[TEST] PASS: --all output identical to leadv2-lane-liveness.sh --all\n'; pass=$((pass+1))
else
  printf '[TEST] FAIL: --all delegation diverged\n-- lanes --\n%s\n-- liveness --\n%s\n' "$all_a" "$all_b" >&2
  exit 1
fi

# Unknown arg: usage to stderr, exit 2 (liveness script convention).
set +e
bad="$(LEADV2_LANE_VIEW_PS_FILE="$FIXTURE_PS" bash "$LANES" --bogus 2>&1)"; rc=$?
set -e
[[ "$rc" -eq 2 ]] && check "$bad" 'Usage:' 'unknown arg exits 2 with usage on stderr' || \
  { printf '[TEST] FAIL: unknown arg rc=%s (want 2)\n' "$rc" >&2; exit 1; }

printf '[TEST] founder lane view: %d checks passed\n' "$pass"
