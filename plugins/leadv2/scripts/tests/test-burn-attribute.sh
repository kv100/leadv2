#!/usr/bin/env bash
# Read-only attribution regression suite.
# run-all-triggers: leadv2-burn-attribute
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../../../.." && pwd)"
BIN="${LEADV2_BURN_ATTRIBUTE_BIN:-${ROOT}/plugins/leadv2/scripts/leadv2-burn-attribute.py}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-burn-attribute.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0 FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -x "$BIN" || -f "$BIN" ]] || { echo "FAIL: attribute script exists at $BIN"; exit 1; }

DB="$TMP/history.db" HANDOFF="$TMP/docs/handoff"
mkdir -p "$HANDOFF/dispatch-work" "$HANDOFF/dispatch-personal" "$HANDOFF/dispatch-no-profile" "$HANDOFF/dispatch-no-session"
printf '[claude-profile] selected=work\n' > "$HANDOFF/dispatch-work/claude-profile.log"
printf 'PID=1 LABEL=x SESSION_ID=s-work\n' > "$HANDOFF/dispatch-work/spawn.log"
printf '[claude-profile] selected=personal\n' > "$HANDOFF/dispatch-personal/claude-profile.log"
printf 'SESSION_ID=s-personal\n' > "$HANDOFF/dispatch-personal/worker.log"
printf 'SESSION_ID=s-no-profile\n' > "$HANDOFF/dispatch-no-profile/spawn.log"
printf '[claude-profile] selected=work\n' > "$HANDOFF/dispatch-no-session/claude-profile.log"

python3 - "$DB" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute('CREATE TABLE sessions (session_id TEXT PRIMARY KEY, project_name TEXT, start_ts TEXT, last_asst_ts TEXT, turns INTEGER, cc_total INTEGER, cr_total INTEGER, last_model TEXT)')
rows = [
 ('s-work', 'alpha', '2026-09-10T01:00:00Z', '2026-09-10T02:00:00Z', 3, 30, 3, 'claude-work'),
 ('s-personal', 'beta', '2026-09-10T01:00:00Z', '2026-09-10T02:00:00Z', 4, 40, 4, 'claude-personal'),
 ('s-no-profile', 'gamma', '2026-09-10T01:00:00Z', '2026-09-10T02:00:00Z', 5, 50, 5, 'claude-unknown'),
 ('s-orphan', 'delta', '2026-09-10T01:00:00Z', '2026-09-10T02:00:00Z', 6, 60, 6, 'claude-orphan'),
]
db.executemany('INSERT INTO sessions VALUES (?,?,?,?,?,?,?,?)', rows)
db.commit()
PY

before="$(stat -f '%m %z' "$DB" 2>/dev/null || stat -c '%Y %s' "$DB")"
chmod 444 "$DB"
out="$TMP/out"
mkdir -p "$TMP/readonly-spy"
cat > "$TMP/readonly-spy/sitecustomize.py" <<'PY'
import sqlite3
_connect = sqlite3.connect
def connect(*args, **kwargs):
    uri = str(args[0]) if args else str(kwargs.get('database', ''))
    if '?mode=ro' not in uri:
        raise sqlite3.OperationalError('READ_ONLY_OPEN_REQUIRED')
    return _connect(*args, **kwargs)
sqlite3.connect = connect
PY
if ! PYTHONPATH="$TMP/readonly-spy${PYTHONPATH:+:$PYTHONPATH}" python3 "$BIN" --db "$DB" --handoff-root "$HANDOFF" --since 2026-09-09T00:00:00Z --until 2026-09-11T00:00:00Z >"$out" 2>"$TMP/err"; then
  cat "$TMP/err"
  bad 'read-only DB opens successfully'
fi
after="$(stat -f '%m %z' "$DB" 2>/dev/null || stat -c '%Y %s' "$DB")"

grep -q '^ACCOUNT work sessions=1 turns=3 cc_total=30 cr_total=3$' "$out" && ok 'selected=work attributes work session' || bad 'selected=work attributes work session'
grep -q '^ACCOUNT personal sessions=1 turns=4 cc_total=40 cr_total=4$' "$out" && ok 'selected=personal attributes personal session' || bad 'selected=personal attributes personal session'
grep -q '^ACCOUNT unknown sessions=2 turns=11 cc_total=110 cr_total=11 reason=unmatched_dispatch_or_no_selected_profile$' "$out" && ok 'missing profile and orphan are unknown' || bad 'missing profile and orphan are unknown'
grep -q '^PROJECT account=work project_name=alpha sessions=1 turns=3 cc_total=30 cr_total=3$' "$out" && ok 'work project breakdown' || bad 'work project breakdown'
grep -q '^MODEL account=personal last_model=claude-personal sessions=1 turns=4 cc_total=40 cr_total=4$' "$out" && ok 'personal model breakdown' || bad 'personal model breakdown'
grep -q '^JOIN dispatch_dirs=4 selected_profiles=3 without_selected_profile=1 profile_without_session=1 session_without_profile=1 conflicting_session_evidence=0$' "$out" && ok 'handoff join defects counted without attribution' || bad 'handoff join defects counted without attribution'
grep -q '^WINDOW_POSITION five_hour=unknown weekly=unknown reason=history_db_has_no_window_reset_or_account_fields$' "$out" && ok 'window position remains explicitly unknown' || bad 'window position remains explicitly unknown'
[[ "$before" == "$after" ]] && ok 'read-only DB mtime and size unchanged' || bad "read-only DB mtime and size unchanged before=$before after=$after"

echo "pass=$PASS fail=$FAIL"
[[ "$FAIL" -eq 0 ]]
