#!/usr/bin/env bash
# tests/test-broad-status-foreign-lanes.sh — LANE-OBSERVABILITY-02 change 3.
#
# Live defect (2026-08-25): the BROAD_STATUS beat rendered only the
# dispatcher repo's lanes — two live lanes ran in ~/Projects/leadv2 unseen
# while the founder read a board about persona-engine. This suite locks the
# foreign-repo extension at BOTH layers:
#
#   SNAPSHOT (real leadv2-lanes-snapshot.sh, hermetic state base):
#     S1  a live lane in a foreign repo (+ none in own repo) appears in the
#         --json table carrying repo=<slug> + age_s.
#     S2  single-repo TSV: --all-repos output is BYTE-IDENTICAL to
#         --no-all-repos (the single-repo consumer contract).
#     S3  a foreign read failure yields ONE {"repo":..,"error":
#         "repo_read_error"} row and does NOT zero the table.
#     S4  the own repo is never double-counted (own slug row skipped even
#         when its active.yaml holds a lane).
#
#   RENDERER (real leadv2-broad-status.sh, stubbed collector):
#     R1  a foreign lane row renders with the "<slug>/" prefix and its
#         stream age — never "ДОСКА ПУСТА".
#     R2  a repo_read_error row renders as a named degraded "не вижу линии"
#         line while the remaining table still renders.
#     R3  an own-repo row (no repo field) renders with NO prefix — the
#         single-repo founder-status.md shape is unchanged.
#
# Hermetic: throwaway repos + state base, stubbed collector/claude, no
# network, no real dispatch. Run: bash scripts/tests/test-broad-status-foreign-lanes.sh

set -uo pipefail

export LEADV2_BURN_GOVERNOR=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

LANES_SNAPSHOT_SH="$SCRIPT_DIR/leadv2-lanes-snapshot.sh"
BROAD_STATUS_SH="$SCRIPT_DIR/leadv2-broad-status.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(lv2_mktemp_dir broad-status-foreign-lanes)"
REPO="$TMP/ownrepo"
FOREIGN="$TMP/foreignrepo"
STATE="$TMP/state-base"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$FOREIGN" "$STATE" "$STUBS"
git -C "$REPO" init -q
git -C "$FOREIGN" init -q
lv2_assert_scratch_repo "$REPO"

export LEADV2_STATE_BASE="$STATE"

# control-plane rows for leadv2-status-projects.sh: slug dir + .repo-root.
mk_slug() {  # <slug> <repo_root>
  mkdir -p "$STATE/$1"
  printf '%s\n' "$2" > "$STATE/$1/.repo-root"
}
mk_slug ownrepo "$REPO"
mk_slug foreignrepo "$FOREIGN"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── S1: foreign live lane appears in the snapshot table ─────────────────────
printf 'sessions: []\n' > "$STATE/ownrepo/active.yaml"
FH="$FOREIGN/docs/handoff/dispatch-fee00001"
mkdir -p "$FH"
printf '{"type":"assistant","text":"writing"}\n' > "$FH/developer.stream.jsonl"
cat > "$STATE/foreignrepo/active.yaml" <<EOF
sessions:
  - task_id: dispatch-fee00001
    pid: null
    phase: build
    log_path: docs/handoff/dispatch-fee00001/developer.stream.jsonl
    started_at: 2026-08-25T10:00:00Z
    last_pulse_at: 2026-08-25T10:01:00Z
EOF

# Liveness stub: valid JSON, verdict dead (liveness is another script's
# contract — an EMPTY stdout (e.g. /bin/true) makes the main snapshot's
# json.loads raise and exit 1 silently, which is not the shape under test).
cat > "$STUBS/liveness.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"lanes":[],"jobs":[],"availability":"unavailable"}\n'
exit 0
EOF
chmod +x "$STUBS/liveness.sh"

snap() {  # [extra args...]
  # LEADV2_LANES_ALL_REPOS=1 pins the script's documented default explicitly:
  # ~/.claude/settings.json ships LEADV2_LANES_ALL_REPOS=0 globally on this
  # machine (verified 2026-08-30, see root-cause-evidence.log), so relying on
  # the script's own "${LEADV2_LANES_ALL_REPOS:-1}" default here would let
  # this suite silently test the ambient override instead of the documented
  # behaviour. An explicit "$@" flag (e.g. --no-all-repos in S2) still wins,
  # since CLI parsing runs after this env default inside the script.
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_BASE="$STATE" \
    LEADV2_LANE_LIVENESS_BIN="$STUBS/liveness.sh" \
    LEADV2_LANES_ALL_REPOS=1 \
    bash "$LANES_SNAPSHOT_SH" --json "$@" 2>/dev/null
}

S1_JSON="$(snap)"
S1_ROW="$(printf '%s' "$S1_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in d.get("table") or []:
    if r.get("task_id") == "dispatch-fee00001":
        print(json.dumps(r)); break
' 2>/dev/null || true)"
if [[ -n "$S1_ROW" ]] && printf '%s' "$S1_ROW" | grep -q '"repo": *"foreignrepo"'; then
  ok "S1: foreign live lane in the table with repo=foreignrepo"
else
  bad "S1: foreign row missing: table=$(printf '%s' "$S1_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("table"))')"
fi

# S4: the OWN repo is never re-read as foreign. A second TSV slug whose
# .repo-root resolves to the SAME physical tree as PROJECT_ROOT (a lane
# worktree/mirror spelling of the own repo) must be skipped by the -ef
# filter — its lanes are the main snapshot's job, never the foreign gather's.
# (Driving a real own lane through the MAIN snapshot is not this change's
# scope: a minimal fixture row trips a PRE-EXISTSING state_write_error in
# the main snapshot's own-read path — identical on HEAD, verified
# 2026-08-25 — so the own table is exercised as `sessions: []` here.)
mk_slug ownrepo-mirror "$REPO"
mkdir -p "$REPO/docs/handoff/dispatch-own00001"
printf '{"type":"assistant","text":"own work"}\n' > "$REPO/docs/handoff/dispatch-own00001/developer.stream.jsonl"
cat > "$STATE/ownrepo-mirror/active.yaml" <<EOF
sessions:
  - task_id: dispatch-own00001
    pid: null
    phase: build
    log_path: docs/handoff/dispatch-own00001/developer.stream.jsonl
    started_at: 2026-08-25T10:00:00Z
EOF
S4_JSON="$(snap)"
S4_VERDICT="$(printf '%s' "$S4_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
t = d.get("table") or []
mirror = [r for r in t if r.get("repo") == "ownrepo-mirror"]
foreign = [r for r in t if r.get("repo") == "foreignrepo"]
print("ok" if not mirror and foreign else "bad mirror=%d foreign=%d" % (len(mirror), len(foreign)))
' 2>/dev/null || true)"
if [[ "$S4_VERDICT" == "ok" ]]; then
  ok "S4: own-repo mirror slug skipped by the -ef filter, foreign repo still read"
else
  bad "S4: $S4_VERDICT"
fi
rm -rf "$STATE/ownrepo-mirror"

# ── S2: single-repo TSV -> byte-identical to --no-all-repos ─────────────────
# (normalize the per-invocation reconcile_cycle counter + rendered_at before
# the diff — they tick on every run and are not the contract under test)
cp "$STATE/foreignrepo/active.yaml" "$TMP/foreignrepo.yaml.bak"
rm -rf "$STATE/foreignrepo"
norm() { sed -e 's/"rendered_at":.*/"rendered_at": "X"/' -e 's/"reconcile_cycle": [0-9]*/"reconcile_cycle": N/'; }
A="$(snap --no-all-repos | norm)"
B="$(snap | norm)"  # flag default ON, but no foreign repo in the TSV anymore
if [[ "$A" == "$B" ]]; then
  ok "S2: single-repo output byte-identical with --all-repos on (consumer safety)"
else
  bad "S2: single-repo output diverged: $(diff <(printf '%s' "$A") <(printf '%s' "$B") | head -5)"
fi

# ── S3: one foreign repo fails -> one error row, the OTHER repo's lanes stay ─
# repoB's registry carries a pid too large for pid_t: the per-session read
# raises inside the foreign scan and the WHOLE repoB read degrades to one
# repo_read_error row — while healthy repoA keeps its lane row (a sub-read
# failure is loud, never a zeroed table).
FOREIGN_B="$TMP/foreignrepo-b"
mkdir -p "$FOREIGN_B"; git -C "$FOREIGN_B" init -q
# recreate the healthy foreign repo (S2 removed it for its single-repo diff)
mk_slug foreignrepo "$FOREIGN"
cp "$TMP/foreignrepo.yaml.bak" "$STATE/foreignrepo/active.yaml" 2>/dev/null || true
mk_slug foreignrepo-b "$FOREIGN_B"
cat > "$STATE/foreignrepo-b/active.yaml" <<EOF
sessions:
  - task_id: dispatch-bad00002
    pid: 99999999999999999999999
    phase: build
    started_at: 2026-08-25T10:00:00Z
EOF
S3_JSON="$(snap)"
S3_VERDICT="$(printf '%s' "$S3_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
t = d.get("table") or []
err = [r for r in t if r.get("error") == "repo_read_error" and r.get("repo") == "foreignrepo-b"]
ok_lanes = [r for r in t if r.get("task_id") == "dispatch-fee00001" and r.get("repo") == "foreignrepo"]
print("ok" if err and ok_lanes else "bad err=%d healthy=%d" % (len(err), len(ok_lanes)))
' 2>/dev/null || true)"
if [[ "$S3_VERDICT" == "ok" ]]; then
  ok "S3: failed foreign repo -> one repo_read_error row, healthy repo's lane still in table"
else
  bad "S3: $S3_VERDICT"
fi

# ── Renderer (stubbed collector feeding the real broad-status.sh) ───────────
FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"
# PULSE-REPO-SCOPED-03: the renderer shows a foreign-repo lane only when THIS
# repo dispatched it (dispatch record <root>/docs/leadv2/tasks/<tid>/). R1's
# foreign lane is exactly that case (it is the row that must keep rendering
# with its slug prefix), so seed the record — the suite's snapshot-layer
# cases (S1-S4) are untouched: leadv2-lanes-snapshot.sh has no such filter.
mkdir -p "$REPO/docs/leadv2/tasks/dispatch-fee00001"

collector_out() {  # <snapshot-json-string>
  # broad-status invokes: collector.sh --project-root <root> --out <path>
  cat > "$STUBS/collector.sh" <<EOF
#!/usr/bin/env bash
out=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --out) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "\$out" ]] || exit 1
printf '%s\n' '$1' > "\$out"
exit 0
EOF
  chmod +x "$STUBS/collector.sh"
}
cat > "$STUBS/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"result":"нет данных за сегодня\nвопросов нет"}'
EOF
chmod +x "$STUBS/claude.sh"

mk_snapshot() {  # <lanes-table-json-array>
  python3 - "$1" <<'PY'
import json, sys
table = json.loads(sys.argv[1])
snap = {"sections": {
  "lanes": {"ok": True, "data": {"table": table, "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"ok": True, "lanes": {}}}}}
print(json.dumps(snap))
PY
}

run_beat() {
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$TMP/state" \
    LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-25T11:00:00Z" \
    LEADV2_BROAD_STATUS_DISPATCHED="1" \
    bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
}

# R1: foreign lane row -> prefixed row, board not empty
collector_out "$(mk_snapshot '[
  {"task_id": "dispatch-fee00001", "phase": "build", "minutes_in_phase": 5,
   "status": "live", "status_reason": "writing", "waiting": false,
   "where": "terminal", "protocol_version": 2, "repo": "foreignrepo", "age_s": 45}]')"
run_beat
if grep -q '^| foreignrepo/' "$FOUNDER_STATUS" && ! grep -q 'ДОСКА ПУСТА' "$FOUNDER_STATUS"; then
  ok "R1: foreign lane rendered with slug prefix, no false empty board"
else
  bad "R1: founder-status.md wrong: $(grep '^|' "$FOUNDER_STATUS" | head -3)"
fi
if grep -q '^| foreignrepo/.*тихо' "$FOUNDER_STATUS"; then
  ok "R1b: foreign row carries its stream age"
else
  bad "R1b: no stream age on foreign row: $(grep 'foreignrepo' "$FOUNDER_STATUS")"
fi

# R2: repo_read_error row -> named degraded line, table survives
collector_out "$(mk_snapshot '[
  {"task_id": "dispatch-own00001", "phase": "build", "minutes_in_phase": 5,
   "status": "live", "status_reason": "writing", "waiting": false,
   "where": "terminal", "protocol_version": 2},
  {"repo": "foreignrepo", "error": "repo_read_error", "data": "PermissionError"}]')"
run_beat
if grep -q 'НЕ ВИЖУ ЛИНИИ — репозиторий foreignrepo не прочитан' "$FOUNDER_STATUS" \
   && grep -q '^| dispatch-own00001' "$FOUNDER_STATUS"; then
  ok "R2: foreign read failure -> named degraded line, table not zeroed"
else
  bad "R2: founder-status.md wrong: $(head -12 "$FOUNDER_STATUS")"
fi

# R3: own-repo row (no repo field) renders with NO prefix
collector_out "$(mk_snapshot '[
  {"task_id": "dispatch-own00002", "phase": "build", "minutes_in_phase": 5,
   "status": "live", "status_reason": "writing", "waiting": false,
   "where": "terminal", "protocol_version": 2}]')"
run_beat
if grep -q '^| dispatch-own00002' "$FOUNDER_STATUS" \
   && ! grep -qE '^\| [a-z0-9-]+/dispatch' "$FOUNDER_STATUS"; then
  ok "R3: own-repo row unprefixed (single-repo founder-status shape unchanged)"
else
  bad "R3: unexpected prefix: $(grep '^|' "$FOUNDER_STATUS" | head -3)"
fi

printf '\n[broad-status-foreign-lanes] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "${FAIL}" -eq 0 ]]
