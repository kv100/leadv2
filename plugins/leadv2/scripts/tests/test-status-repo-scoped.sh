#!/usr/bin/env bash
# tests/test-status-repo-scoped.sh — PULSE-REPO-SCOPED-03 (dispatch-82bb6960).
#
# Founder report (2026-08-31): opening a session in ~/Projects/platform, the
# beat there showed another repo's data — "посты н/д · комменты н/д ·
# реплаи н/д" (persona-engine's product counters, hardcoded repo-blind) and
# "persona-engine/dispatch-… — foreign repo persona-engine; pid=alive" (the
# collector's global LEADV2_LANES_ALL_REPOS=1 pin force-showing every other
# repo's lanes on every board). The beat itself is WANTED — the founder
# works in that repo too; only the foreign data is not.
#
# This suite locks the repo-scoped render contract at the ONE layer the fix
# lives in (the renderer, leadv2-broad-status.sh — the collector's pin is
# deliberately untouched: it is what keeps a dispatching session able to see
# a lane whose registry row lives in another repo):
#
#   C1  a repo whose repo_facts declares NO product metric renders NO
#       product line at all — no "посты"/"комменты"/"реплаи" substring
#       anywhere, while the board itself still renders (own row present);
#   C2  a repo that declares them renders the line exactly as before
#       (real numbers where given, "н/д" where a declared repo omits one —
#       never 0);
#   C3  a foreign-repo lane this repo did NOT dispatch is absent;
#   C4  a foreign-repo lane this repo DID dispatch (dispatch record
#       <root>/docs/leadv2/tasks/<task_id>/ exists) still renders — the
#       regression guard for the incident the collector pin was added for;
#   C5  an own-repo lane renders (unchanged).
#
# Hermetic: throwaway repo + state root, stubbed collector/claude, no
# network, no real dispatch, no real repo or state root touched on the
# failure path either (every write lands under $TMP). Run:
#   bash plugins/leadv2/scripts/tests/test-status-repo-scoped.sh

set -uo pipefail

export LEADV2_BURN_GOVERNOR=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

BROAD_STATUS_SH="$SCRIPT_DIR/leadv2-broad-status.sh"

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(lv2_mktemp_dir status-repo-scoped)"
REPO="$TMP/ownrepo"
STUBS="$TMP/stubs"
mkdir -p "$REPO" "$STUBS"
git -C "$REPO" init -q
lv2_assert_scratch_repo "$REPO"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

FOUNDER_STATUS="$REPO/docs/leadv2/founder-status.md"

# broad-status invokes: collector.sh --project-root <root> --out <path>
collector_out() {  # <snapshot-json-string>
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
cat > "\$out" <<'JSONEOF'
$1
JSONEOF
exit 0
EOF
  chmod +x "$STUBS/collector.sh"
}
cat > "$STUBS/claude.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"result":"нет данных за сегодня\nвопросов нет"}'
EOF
chmod +x "$STUBS/claude.sh"

mk_snapshot() {  # <lanes-table-json-array> [repo_facts-json-object]
  local table="$1" facts="${2:-}"
  if [[ -n "$facts" ]]; then
    python3 - "$table" "$facts" <<'PY'
import json, sys
table = json.loads(sys.argv[1])
facts = json.loads(sys.argv[2])
snap = {"sections": {
  "lanes": {"ok": True, "data": {"table": table, "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"ok": True, "lanes": {}}},
  "repo_facts": {"ok": True, "data": facts}}}
print(json.dumps(snap))
PY
  else
    python3 - "$table" <<'PY'
import json, sys
table = json.loads(sys.argv[1])
snap = {"sections": {
  "lanes": {"ok": True, "data": {"table": table, "questions": [], "degraded": []}},
  "lane_detail": {"ok": True, "data": {"ok": True, "lanes": {}}}}}
print(json.dumps(snap))
PY
  fi
}

run_beat() {
  env LEADV2_PROJECT_ROOT="$REPO" LEADV2_STATE_ROOT="$TMP/state" \
    LEADV2_STATUS_COLLECTOR_BIN="$STUBS/collector.sh" \
    LEADV2_BROAD_STATUS_CLAUDE_BIN="$STUBS/claude.sh" \
    LEADV2_BROAD_STATUS_BEAT_AT="2026-08-31T09:00:00Z" \
    LEADV2_BROAD_STATUS_DISPATCHED="1" \
    bash "$BROAD_STATUS_SH" >/dev/null 2>&1 || true
}

seed_dispatch_record() {  # <task_id> — the mark of "this repo dispatched it"
  mkdir -p "$REPO/docs/leadv2/tasks/$1"
}

# Every beat's table carries an own-repo row so a FAILING render (which
# would also lack product words) can never satisfy C1's absence assertions
# by accident — the own row is the positive control that the beat rendered.
OWN_ROW='{"task_id": "dispatch-own00001", "phase": "build", "minutes_in_phase": 5, "status": "live", "status_reason": "writing", "waiting": false, "where": "terminal", "protocol_version": 2}'

# ── C1: no declared product metrics ⇒ NO product line, board still renders ──
collector_out "$(mk_snapshot "[$OWN_ROW]")"
rm -f "$FOUNDER_STATUS"
run_beat
if [[ -f "$FOUNDER_STATUS" ]] && grep -q '^| dispatch-own00001' "$FOUNDER_STATUS"; then
  ok "C1-control: board rendered with the own-repo row (beat did not fail)"
else
  bad "C1-control: beat did not render an own row: $(sed -n '1,12p' "$FOUNDER_STATUS" 2>/dev/null)"
fi
PRODUCT_HITS="$(grep -cE 'посты|комменты|реплаи' "$FOUNDER_STATUS" 2>/dev/null || true)"
if [[ "$PRODUCT_HITS" == "0" ]]; then
  ok "C1: repo declaring no product metrics renders no product line (0 посты/комменты/реплаи substrings)"
else
  bad "C1: product words leaked into a repo that declares none ($PRODUCT_HITS lines): $(grep -E 'посты|комменты|реплаи' "$FOUNDER_STATUS")"
fi

# ── C2: declared metrics ⇒ the line renders exactly as today ────────────────
collector_out "$(mk_snapshot "[$OWN_ROW]" \
  '{"posts_today": 3, "posts_floor": 5, "comments_today": 14, "comments_floor": 60, "replies_today": 2, "replies_floor": 10, "working_window": "09:00-17:00"}')"
run_beat
if grep -q '· посты 3/5 · комменты 14/60 · реплаи 2/10 · окно 09:00-17:00' "$FOUNDER_STATUS"; then
  ok "C2: declared metrics render the product line exactly as before"
else
  bad "C2: product line wrong: $(grep -E 'посты|комменты' "$FOUNDER_STATUS" || echo ABSENT)"
fi

# C2b: a declaring repo that omits one metric keeps the line with "н/д" —
# the rule-1 contract (never 0) is scoped, not removed, by this fix.
collector_out "$(mk_snapshot "[$OWN_ROW]" \
  '{"comments_today": 14, "comments_floor": 60}')"
run_beat
if grep -q 'посты н/д' "$FOUNDER_STATUS" && grep -q 'комменты 14/60' "$FOUNDER_STATUS"; then
  ok "C2b: a declaring repo missing one metric still gets н/д (never 0), line kept"
else
  bad "C2b: partial declaration broke the н/д contract: $(grep -E 'посты|комменты' "$FOUNDER_STATUS" || echo ABSENT)"
fi

# ── C3/C5: foreign lane NOT dispatched by this repo ⇒ absent; own ⇒ present ──
FOREIGN_ROW='{"task_id": "dispatch-beef0001", "phase": "build", "minutes_in_phase": 5, "status": "live", "status_reason": "foreign repo otherrepo; pid=alive", "waiting": false, "where": "terminal", "protocol_version": 2, "repo": "otherrepo", "age_s": 45}'
collector_out "$(mk_snapshot "[$OWN_ROW, $FOREIGN_ROW]")"
run_beat
if grep -q 'otherrepo/' "$FOUNDER_STATUS"; then
  bad "C3: a foreign lane this repo never dispatched leaked onto the board: $(grep 'otherrepo/' "$FOUNDER_STATUS")"
else
  ok "C3: foreign lane without a dispatch record in this repo is absent"
fi
if grep -q '^| dispatch-own00001' "$FOUNDER_STATUS"; then
  ok "C5: own-repo lane renders (unchanged)"
else
  bad "C5: own-repo row missing: $(sed -n '1,12p' "$FOUNDER_STATUS")"
fi

# ── C4: foreign lane this repo DID dispatch ⇒ still renders ─────────────────
# (the incident the collector's ALL_REPOS pin was added for: a lane whose
# registry row lives in another repo must stay visible to the board of the
# repo that dispatched it — the dispatch journal dir is the ownership mark)
seed_dispatch_record "dispatch-beef0001"
run_beat
if grep -q '^| otherrepo/' "$FOUNDER_STATUS"; then
  ok "C4: foreign lane WITH a dispatch record in this repo still renders (pin rescue kept)"
else
  bad "C4: dispatched foreign lane went missing — the pin rescue regressed: $(sed -n '1,12p' "$FOUNDER_STATUS")"
fi

printf '\n[status-repo-scoped] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "${FAIL}" -eq 0 ]]
