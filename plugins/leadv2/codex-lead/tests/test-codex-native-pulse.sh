#!/bin/bash
# tests/test-codex-native-pulse.sh — CODEX-PULSE-HOOK-02.
# Hermetic pulse-hook suite: no codex binary, no network. All producers are
# fixtures under mktemp dirs (LEADV2_CODEX_PULSE_STATE, registry, repo root
# with a recording status-surface stub). Design §5 step 2 case list.
#
# Run: bash plugins/leadv2/codex-lead/tests/test-codex-native-pulse.sh
# Exit 0 = all pass; non-zero = failures found.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/marketplace/plugins/leadv2/hooks/leadv2-native-pulse.sh"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$1"; }

STATE="$FIX/pulse-state"; REG="$FIX/registry"; REPO="$FIX/repo"
mkdir -p "$STATE" "$REG" "$REPO/plugins/leadv2/scripts" "$REPO/docs/leadv2"

# Recording status-surface stub: appends one line per invocation to
# $FIX/surface-calls and prints the canned oneline from $FIX/surface-out.
cat > "$REPO/plugins/leadv2/scripts/leadv2-status-surface.sh" <<'EOF'
#!/bin/bash
printf 'call\n' >> "${SURFACE_CALLS:?}"
cat "${SURFACE_OUT:?}"
exit 0
EOF
chmod +x "$REPO/plugins/leadv2/scripts/leadv2-status-surface.sh"
export SURFACE_CALLS="$FIX/surface-calls"; : > "$SURFACE_CALLS"
export SURFACE_OUT="$FIX/surface-out"
printf 'sup:OFF(retired) | lanes 1: leadv2/FIXTASK worker confirmed 0s live(fresh)' > "$SURFACE_OUT"
printf 'sessions: []\n' > "$REPO/docs/leadv2/active.yaml"
printf '{"agent_id":"a-1","started_at":"2026-08-25T00:00:00Z"}' > "$REG/a1.json"

pulse(){ LEADV2_CODEX_PULSE_STATE="$STATE" LEADV2_NATIVE_AGENT_REGISTRY="$REG" \
  LEADV2_CODEX_PULSE_REPO_ROOT="$REPO" LEADV2_CODEX_PULSE_MIN_SECONDS="${MIN:-60}" \
  LEADV2_CODEX_PULSE_INJECT="${INJ:-1}" bash "$HOOK" ${1:-}; }
loglines(){ wc -l < "$STATE/pulse.log" 2>/dev/null | tr -d ' '; }
lastjson(){ cat "$STATE/last.json" 2>/dev/null; }

# 1. fresh state: missing last.json -> emits, self-heals
OUT="$(pulse)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *'pulse agents=1 lanes=1 task=leadv2/FIXTASK reason=changed'* ]] \
  && pass 'missing last.json emits reason=changed' || fail "fresh emit rc=$RC out=$OUT"
lastjson | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
  && pass 'last.json self-heals to valid JSON' || fail 'last.json not valid JSON after fresh emit'

# 2. unchanged digest inside window -> no emit, stdout empty, NO lane scan
: > "$SURFACE_CALLS"; BEFORE="$(loglines)"
OUT="$(pulse)"; RC=$?
[[ $RC -eq 0 && -z "$OUT" ]] && [[ "$(loglines)" == "$BEFORE" ]] \
  && pass 'unchanged digest inside window: silent, no log line' || fail "no-emit run wrote output=$OUT"
[[ ! -s "$SURFACE_CALLS" ]] && pass 'no-emit run does no lane scan (R3)' || fail 'no-emit run still scanned lanes'

# 3. registry change (cheap input) -> re-arms scan, digest changed -> emit
printf '{"agent_id":"a-2","started_at":"2026-08-25T00:01:00Z"}' > "$REG/a2.json"
OUT="$(pulse)"
[[ "$OUT" == *'agents=2 '* && "$OUT" == *'reason=changed'* ]] \
  && pass 'registry change emits reason=changed agents=2' || fail "registry change out=$OUT"

# 4. surface change alone, registry+active.yaml untouched -> inside window,
# the R3 short-circuit holds (no scan); documented boundary, not a defect
: > "$SURFACE_CALLS"
printf 'sup:OFF(retired) | lanes 2: leadv2/FIXTASK worker confirmed 0s live(fresh) | leadv2/OTHER worker confirmed 1s live(fresh)' > "$SURFACE_OUT"
sleep 1.1 # ensure active.yaml mtime would differ if touched; it is not
OUT="$(pulse)"
if [[ -z "$OUT" && ! -s "$SURFACE_CALLS" ]]; then
  pass 'surface-only drift inside window: short-circuit holds (R3 boundary)'
else
  fail "surface-only drift inside window scanned/emitted unexpectedly out=$OUT"
fi

# 5. active.yaml touched (cheap input) -> re-arms scan -> surface change emits
touch "$REPO/docs/leadv2/active.yaml"
OUT="$(pulse)"
[[ "$OUT" == *'lanes=2 '* && "$OUT" == *'reason=changed'* ]] \
  && pass 'active.yaml change re-arms scan, emits lanes=2' || fail "active re-arm out=$OUT"

# 6. back-dated emitted_at, digest unchanged -> reason=cadence
python3 - "$STATE/last.json" <<'PY'
import json, sys, time
p = sys.argv[1]
d = json.load(open(p))
d['emitted_epoch'] = time.time() - 120
d['emitted_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(d['emitted_epoch']))
json.dump(d, open(p, 'w'), sort_keys=True, separators=(',', ':'))
PY
OUT="$(pulse)"
[[ "$OUT" == *'reason=cadence'* ]] && pass 'back-dated emitted_at emits reason=cadence' || fail "cadence out=$OUT"

# 7. --force inside window with unchanged digest -> reason=lifecycle
OUT="$(pulse --force)"
[[ "$OUT" == *'reason=lifecycle'* ]] && pass '--force emits reason=lifecycle' || fail "force out=$OUT"

# 8. corrupt last.json -> emits, self-heals
printf 'not json at all{' > "$STATE/last.json"
OUT="$(pulse)"
[[ "$OUT" == *'reason=changed'* ]] && lastjson | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
  && pass 'corrupt last.json emits and self-heals' || fail 'corrupt last.json path broken'

# 9. unreadable producer -> renders ?, exit 0 (repo root without the script).
# INJECT=1 explicitly: the shipped default is 0 (11b), so stdout observation
# requires opting in — the hook itself still logs the pulse unconditionally.
OUT="$(LEADV2_CODEX_PULSE_STATE="$STATE" LEADV2_NATIVE_AGENT_REGISTRY="$REG" \
  LEADV2_CODEX_PULSE_REPO_ROOT="$FIX/no-such-repo" MIN=0 \
  LEADV2_CODEX_PULSE_INJECT=1 bash "$HOOK")"; RC=$?
[[ $RC -eq 0 && "$OUT" == *'lanes=? task=- '* ]] \
  && pass 'unreadable producer renders ? and exits 0' || fail "unreadable producer rc=$RC out=$OUT"

# 10. INJECT=0 -> empty stdout, log still appended
BEFORE="$(loglines)"
OUT="$(MIN=0 INJ=0 pulse)"; RC=$?
AFTER="$(loglines)"
[[ $RC -eq 0 && -z "$OUT" && "$AFTER" -gt "$BEFORE" ]] \
  && pass 'INJECT=0: empty stdout, log appended' || fail "INJECT=0 out=$OUT rc=$RC"

# 11. MIN_SECONDS=0 -> emit on every call
BEFORE="$(loglines)"
OUT="$(MIN=0 pulse)"; OUT2="$(MIN=0 pulse)"
[[ "$(loglines)" -eq $((BEFORE + 2)) ]] \
  && pass 'MIN_SECONDS=0 emits on every call' || fail "MIN=0 emitted $(($(loglines) - BEFORE)) of 2"

# 11b. shipped default INJECT=0 (probe could not confirm rendering): no env
# set at all -> empty stdout, log still appended
BEFORE="$(loglines)"
OUT="$(LEADV2_CODEX_PULSE_STATE="$STATE" LEADV2_NATIVE_AGENT_REGISTRY="$REG" \
  LEADV2_CODEX_PULSE_REPO_ROOT="$REPO" LEADV2_CODEX_PULSE_MIN_SECONDS=0 \
  bash "$HOOK" --force)"; RC=$?
AFTER="$(loglines)"
[[ $RC -eq 0 && -z "$OUT" && "$AFTER" -eq $((BEFORE + 1)) ]] \
  && pass 'shipped default INJECT=0: empty stdout, log appended' || fail "default INJECT out=$OUT rc=$RC"

# 12. pulse never emits a permissionDecision (any payload incl. malformed)
for p in '{"tool_name":"shell","tool_input":{"command":"ls"}}' '{broken'; do
  OUT="$(printf '%s' "$p" | pulse --force)"; RC=$?
  [[ $RC -eq 0 && "$OUT" != *permissionDecision* ]] \
    && pass "no permissionDecision in stdout ($p)" || fail "decision leaked rc=$RC out=$OUT"
done

# 13. 32 concurrent --force invocations -> last.json valid JSON, log intact
: > "$STATE/pulse.log"
for i in $(seq 1 32); do pulse --force >/dev/null & done; wait
python3 - "$STATE" <<'PY' && pass '32 concurrent: last.json JSON + every log line well-formed' || fail '32 concurrent tore state'
import json, re, sys
d = json.load(open(sys.argv[1] + '/last.json'))
assert d['version'] == 1 and 'digest' in d and 'emitted_epoch' in d
pat = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z pulse agents=\d+ lanes=(\d+|\?) task=(\S+|-) reason=(changed|cadence|lifecycle)$')
lines = open(sys.argv[1] + '/pulse.log').read().splitlines()
assert lines and all(len(l) < 4096 and pat.match(l) for l in lines), lines[:3]
PY

# 14. CODEX-PULSE-HOOK-03 default-path integration: NO REPO_ROOT override,
# CLAUDE_PLUGIN_ROOT pinned inside the marketplace tree (the production
# layout: the old ../../ walk from it never reached the project and the
# surface always rendered ?). The hook must resolve the project root from
# the payload cwd — even a deep subdir, proving the walk-up — and call the
# REAL plugins/leadv2/scripts/leadv2-status-surface.sh of this checkout.
# lanes=<digit> (not ?) is only reachable from the real producer succeeding.
PROJECT_ROOT="$(cd "$ROOT/../../.." && pwd)"
ISTATE="$FIX/pulse-integ"; mkdir -p "$ISTATE"
OUT="$( cd "$FIX" && printf '{"cwd":"%s/tests","tool_name":"shell"}' "$PROJECT_ROOT/plugins/leadv2/codex-lead" \
  | LEADV2_CODEX_PULSE_STATE="$ISTATE" LEADV2_CODEX_PULSE_MIN_SECONDS=0 \
    LEADV2_CODEX_PULSE_INJECT=1 CLAUDE_PLUGIN_ROOT="$ROOT/marketplace/plugins/leadv2" \
    bash "$HOOK" --force )"; RC=$?
LINE="$(tail -n 1 "$ISTATE/pulse.log" 2>/dev/null)"
if [[ $RC -eq 0 && "$OUT" == *'pulse agents='* && "$LINE" == *'pulse agents='* ]] \
  && [[ "$LINE" =~ lanes=[0-9] ]] && [[ "$LINE" != *'lanes=?'* ]]; then
  pass 'default path: payload-cwd subdir resolves project, real surface answers'
else
  fail "default-path integration rc=$RC out=$OUT line=$LINE"
fi
# negative control, same default path: payload cwd outside any project ->
# walk-up finds no surface -> renders ?, exit 0 (no hallucinated root)
OUT="$( cd "$FIX" && printf '{"cwd":"%s","tool_name":"shell"}' "$FIX" \
  | LEADV2_CODEX_PULSE_STATE="$ISTATE" LEADV2_CODEX_PULSE_MIN_SECONDS=0 \
    LEADV2_CODEX_PULSE_INJECT=1 CLAUDE_PLUGIN_ROOT="$ROOT/marketplace/plugins/leadv2" \
    bash "$HOOK" --force )"; RC=$?
[[ $RC -eq 0 && "$OUT" == *'lanes=? task=- '* ]] \
  && pass 'default path: non-project cwd renders ? and exits 0' || fail "non-project cwd rc=$RC out=$OUT"

printf '[SUMMARY] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
