#!/usr/bin/env bash
# tests/test-status-surface-fast-names.sh — SWIFTBAR-FAST-NAMES-01
#
# Covers the two things SWIFTBAR-FAST-NAMES-01 adds:
#   1. resolve_lane_label() — the sig8 → human-label resolver (sourced, unit).
#   2. the async cache render path — cold cache, warm cache (label shown, sig8
#      demoted), stale cache (⚠️ кэш устарел), and rename hygiene (bash= path).
#
# Every input is sandboxed (a temp cache dir, fixture ledger / active.yaml /
# handoff); nothing touches the operator's live leadv2 state. The render path
# is driven in CACHED mode (no LEADV2_STATUS_SYNC) against a stub renderer so
# it never runs the real ~4 s renderer.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
WIDGET="${ROOT}/plugins/leadv2/scripts/leadv2-status-surface.5s.sh"

PASS=0; FAIL=0
ok()  { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }

FIX="$(mktemp -d -t leadv2-fast-names)"
trap 'rm -rf "$FIX"' EXIT
CACHE="$FIX/cache"
LEDGERS="$FIX/ledgers"
HANDOFF="$FIX/handoff"
ACTIVE="$FIX/active.yaml"
mkdir -p "$CACHE" "$LEDGERS" "$HANDOFF"

# A stub renderer: succeeds with empty output by default (so a kick never
# promotes a payload), but can be told to sleep (to hold the refresh lock).
STUB="$FIX/stub-renderer.sh"
printf '#!/usr/bin/env bash\nsleep "${LEADV2_STUB_SLEEP:-0}"; exit 0\n' > "$STUB"
chmod +x "$STUB"

# ════════════════════════════════════════════════════════════════════════════
# T1: resolve_lane_label — ledger / active.yaml / mission / miss / pipe-strip
# ════════════════════════════════════════════════════════════════════════════
echo "== T1: resolve_lane_label fallback chain =="

# ledger row carrying a lane_label
printf '{"task_sig":"aaaa1111ffffffffffffffffffffffffffffffffffffffffffffffff","arm":"glm","state":"confirmed","lane_label":"LEDGER-HIT-TASK"}\n' \
  > "$LEDGERS/leadv2.jsonl"
# active.yaml with a session whose worktree carries a sig8
cat > "$ACTIVE" <<EOF
meta: {}
sessions:
  - { task_id: ACTIVE-YAML-TASK, worktree: worktree-bbbb2222, phase: build }
EOF
# mission heading for a third sig8
mkdir -p "$HANDOFF/dispatch-cccc3333"
printf '# MISSION-HEADING-TASK — implementation design\nbody\n' > "$HANDOFF/dispatch-cccc3333/mission.md"

resolve() {
  # $0 is a dummy name ("resolver") distinct from the sourced widget path, so
  # the widget's main guard (BASH_SOURCE[0] = $0) does NOT fire on source.
  LEADV2_STATUS_LEDGER_DIR="$LEDGERS" \
  LEADV2_STATUS_ACTIVE_YAML="$ACTIVE" \
  LEADV2_STATUS_HANDOFF_DIR="$HANDOFF" \
  bash -c 'set -uo pipefail; source "$1"; resolve_lane_label "$2"' resolver "$WIDGET" "$1"
}

[ "$(resolve aaaa1111)" = "LEDGER-HIT-TASK" ] && ok "ledger lane_label hit" || bad "ledger hit (got '$(resolve aaaa1111)')"
[ "$(resolve bbbb2222)" = "ACTIVE-YAML-TASK" ] && ok "active.yaml worktree fallback" || bad "active.yaml fallback (got '$(resolve bbbb2222)')"
# mission heading: the whole H1 is returned, '#' stripped and clipped to 40
# (per design §1.4) — assert the name token leads it.
case "$(resolve cccc3333)" in
  "MISSION-HEADING-TASK "*) ok "mission heading fallback ($(resolve cccc3333))" ;;
  *) bad "mission fallback (got '$(resolve cccc3333)')" ;;
esac
[ "$(resolve bbbbbbbb)" = "bbbbbbbb" ] && ok "miss -> sig8 unchanged" || bad "miss (got '$(resolve bbbbbbbb)')"

# pipe-strip: a lane_label carrying '|' must come back without it
printf '{"task_sig":"dddd4444ffffffffffffffffffffffffffffffffffffffffffffffff","lane_label":"A|B"}\n' >> "$LEDGERS/leadv2.jsonl"
_r="$(resolve dddd4444)"
case "$_r" in
  *"|"*) bad "pipe not stripped (got '$_r')" ;;
  *) ok "lane_label pipe stripped (got '$_r')" ;;
esac

# ════════════════════════════════════════════════════════════════════════════
# helper: drive the widget in CACHED mode against the sandbox cache
# ════════════════════════════════════════════════════════════════════════════
widget() {
  LEADV2_STATUS_CACHE_DIR="$CACHE" \
  LEADV2_STATUS_RENDERER="$STUB" \
  LEADV2_STATUS_LEDGER_DIR="$LEDGERS" \
  LEADV2_STATUS_HANDOFF_DIR="$HANDOFF" \
  /bin/bash "$WIDGET" 2>&1
}

# A minimal valid --all payload: section 1 (lanes), 2 (questions), 3-5 empty,
# 6 (single-lead with a sig8 worker), 7 empty. $1 (optional) = a question row
# to inject under the questions header (used for the copy-reply bash= test).
make_payload() {
  _qrow="${1:-}"
  printf 'supervisor:OFF\nlanes (0 live · 0 dead · 0 done)\n'
  if [ -n "$_qrow" ]; then printf -- '---\nquestions (1)\n%s\n' "$_qrow"
  else printf -- '---\nquestions (0)\n'; fi
  printf -- '---\n\n---\n\n---\n\n---\n'
  printf 'mode=single-lead active 1 ff3b7059 sonnet 3m\n'
  # Real render_single_lead detail-line shape (single-repo, non-multi):
  # "  <name> · <phase> · <arm> <age>" -- this fixture used to hand-write a
  # legacy space-delimited row ("  ff3b7059 sonnet 3m active"), which never
  # matched what the renderer actually emits (confirmed by reading
  # render_single_lead directly). It only "worked" because the widget's old
  # CACHED-branch parser also (coincidentally, buggily) split on whitespace.
  # Now that the widget parser correctly splits on ' · ' (see leadv2-status-
  # surface.5s.sh's CACHED branch), the fixture must use the real format.
  printf '  ff3b7059 · worker · sonnet 3m\n'
  printf -- '---\n'
}

# ════════════════════════════════════════════════════════════════════════════
# T2: cold cache — no payload -> «нет кэша», <1s, no spinner, lock kicked
# ════════════════════════════════════════════════════════════════════════════
echo "== T2: cold cache =="
rm -f "$CACHE/all.payload" 2>/dev/null; rmdir "$CACHE/refresh.lock" 2>/dev/null
_s="$(date +%s)"
_out="$(LEADV2_STUB_SLEEP=4 widget)"
_e="$(date +%s)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
_rc_pass=1
printf '%s' "$_title" | grep -q 'нет кэша' || _rc_pass=0
printf '%s\n' "$_out" | grep -q 'обновляется' && _rc_pass=0   # no spinner
if [ "$_rc_pass" -eq 1 ]; then ok "cold cache shows «нет кэша», no spinner"
else bad "cold cache (title='$_title')"; fi
if [ $(( _e - _s )) -le 1 ]; then ok "cold render <1s (wall $(( _e - _s ))s)"
else bad "cold render too slow (wall $(( _e - _s ))s)"; fi
# the kick holds the lock while the stub sleeps
if [ -d "$CACHE/refresh.lock" ]; then ok "cold render kicked a refresh (lock held)"
else bad "cold render did not leave a refresh lock"; fi
# let the stub finish so it does not leak into later cases
sleep 5; rmdir "$CACHE/refresh.lock" 2>/dev/null

# ════════════════════════════════════════════════════════════════════════════
# T3: warm cache — label shown in title + row, sig8 demoted to `sig …`
# ════════════════════════════════════════════════════════════════════════════
echo "== T3: warm cache =="
make_payload > "$CACHE/all.payload"
printf 'ff3b7059\tHUMAN-LANE-NAME-01\n' > "$CACHE/labels.map"
_s="$(date +%s)"
_out="$(widget)"
_e="$(date +%s)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
_warm_pass=1
printf '%s' "$_title" | grep -q 'HUMAN-LANE-NAME-01' || _warm_pass=0     # title has the label
printf '%s' "$_title" | grep -q 'ff3b7059' && _warm_pass=0               # title has NO raw sig8
# Real detail-line shape after label substitution: label + the untouched
# ' · '-delimited remainder (phase · arm age). The old assertion expected
# 'label · arm · age' (no phase) -- that shape was never real, only the old
# whitespace-splitting widget bug produced it.
printf '%s\n' "$_out" | grep -q 'HUMAN-LANE-NAME-01 · worker · sonnet 3m' || _warm_pass=0
# D1/tier-2: the `sig <hex>` sub-row is deleted entirely (pure duplication
# once the label is shown inline) -- assert it is GONE, not present.
printf '%s\n' "$_out" | grep -q '  sig ff3b7059' && _warm_pass=0          # no sig8 sub-row
if [ "$_warm_pass" -eq 1 ]; then ok "warm cache: label in title+row, no sig8 sub-row"
else bad "warm cache (title='$_title' out=$(printf '%s' "$_out" | tr '\n' '|'))"; fi
if [ $(( _e - _s )) -le 1 ]; then ok "warm render <1s (wall $(( _e - _s ))s)"
else bad "warm render too slow (wall $(( _e - _s ))s)"; fi

# ════════════════════════════════════════════════════════════════════════════
# T4: stale cache — payload >=600 s old -> «⚠️ кэш устарел»
# ════════════════════════════════════════════════════════════════════════════
echo "== T4: stale cache =="
python3 -c 'import os,sys,time; t=time.time()-900; os.utime(sys.argv[1],(t,t))' "$CACHE/all.payload"
_out="$(widget)"
_title="$(printf '%s\n' "$_out" | sed -n '1p')"
printf '%s' "$_title" | grep -q 'кэш устарел' && ok "stale cache -> «⚠️ кэш устарел»" \
  || bad "stale cache (title='$_title')"

# ════════════════════════════════════════════════════════════════════════════
# T5: rename hygiene — copy-reply bash= path ends .5s.sh and exists
# ════════════════════════════════════════════════════════════════════════════
echo "== T5: rename hygiene (SELF_PATH) =="
# Legacy-mode payload (no section-6 single-lead header) with a pending
# question: the legacy dropdown emits copy-reply rows carrying bash=$SELF_PATH,
# which is what must survive the .10s -> .5s rename (R2).
printf 'supervisor:ON\nlanes (1 live · 0 dead · 0 done)\n---\nquestions (1)\nq9 Continue? [yes|no]\n---\n' > "$CACHE/all.payload"
rm -f "$CACHE/labels.map"
python3 -c 'import os,sys,time; os.utime(sys.argv[1],(time.time(),time.time()))' "$CACHE/all.payload"
_out="$(widget)"
_bashpath="$(printf '%s\n' "$_out" | sed -n 's/.*bash=\([^ ]*\).*/\1/p' | head -1)"
if [ -n "$_bashpath" ] && printf '%s' "$_bashpath" | grep -q '\.5s\.sh$' && [ -f "$_bashpath" ]; then
  ok "copy-reply bash= path is the .5s.sh and exists ($_bashpath)"
else
  bad "rename hygiene (bashpath='$_bashpath' out=$(printf '%s' "$_out" | tr '\n' '|'))"
fi

# ════════════════════════════════════════════════════════════════════════════
printf '\ntest-status-surface-fast-names: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
