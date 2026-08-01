#!/usr/bin/env bash
# tests/test-status-surface-bash32.sh — regression test for SWIFTBAR-BASH32-01.
#
# SwiftBar launches leadv2-status-surface.10s.sh with a minimal PATH under
# macOS's built-in /bin/bash (3.2.57), NOT the Homebrew bash 5.x every
# terminal happens to use. bash 3.2's command-substitution parser scans `$( )`
# with a naive paren counter that does not skip heredoc bodies — a heredoc
# nested inside `$( … python3 <<'PYEOF' … PYEOF )` corrupts the parse of
# everything after it. bash 4+ rewrote that parser to be heredoc-aware, so
# every hand-run under a terminal's bash 5 looked healthy while the founder's
# actual menu bar rendered a silent, confident "0 / 0".
#
# This test hardcodes /bin/bash (not `bash` resolved via PATH) for exactly
# that reason: under CI or any Homebrew-shell dev machine, `bash` on PATH is
# 5.x, and the bug would be invisible to a test that used it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
RENDERER="${ROOT}/plugins/leadv2/scripts/leadv2-status-surface.sh"
WRAPPER="${ROOT}/plugins/leadv2/scripts/leadv2-status-surface.10s.sh"

PASS=0
FAIL=0
SKIP=0
ok()   { printf '  ok   - %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL - %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  SKIP - %s\n' "$1"; SKIP=$((SKIP + 1)); }

# Only meaningful on Darwin with a real bash 3.2 at /bin/bash — that is the
# exact binary SwiftBar resolves via `#!/usr/bin/env bash` + its minimal PATH.
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "test-status-surface-bash32: SKIP — not Darwin, no /bin/bash 3.2 to test against"
  exit 0
fi
if [[ ! -x /bin/bash ]]; then
  echo "test-status-surface-bash32: SKIP — /bin/bash not present"
  exit 0
fi
BASH32_VERSION="$(/bin/bash --version 2>/dev/null | head -1)"
case "$BASH32_VERSION" in
  *"version 3."*) ;;
  *)
    echo "test-status-surface-bash32: SKIP — /bin/bash is not 3.x (${BASH32_VERSION})"
    exit 0
    ;;
esac

echo "== T1: /bin/bash -n on the renderer =="
if _out="$(/bin/bash -n "$RENDERER" 2>&1)" && [[ -z "$_out" ]]; then
  ok "renderer parses clean under bash 3.2"
else
  bad "renderer syntax error under bash 3.2: ${_out}"
fi

echo "== T2: /bin/bash -n on the wrapper =="
if _out="$(/bin/bash -n "$WRAPPER" 2>&1)" && [[ -z "$_out" ]]; then
  ok "wrapper parses clean under bash 3.2"
else
  bad "wrapper syntax error under bash 3.2: ${_out}"
fi

echo "== T3: env -i minimal PATH (the actual SwiftBar launch shape) renders lanes =="
# This is environment-dependent: it needs live lanes to prove a real row
# renders, not just the renderer's own "0 lanes" empty state. If the renderer
# reports zero lane rows under bash 5 too, there is nothing live to observe —
# SKIP rather than FAIL, so a quiet machine doesn't red a passing fix.
_t3_out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash "$WRAPPER" 2>&1)"
_t3_rc=$?
_t3_bash5_out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin bash "$WRAPPER" 2>&1 || true)"
_t3_bash5_rows="$(printf '%s\n' "$_t3_bash5_out" | awk 'BEGIN{c=0} $0=="---"{c++; next} c==1 && $0!="" {print}' | wc -l | tr -d ' ')"
if [[ "$_t3_rc" -ne 0 ]]; then
  bad "wrapper exited ${_t3_rc} under minimal PATH (should always exit 0): ${_t3_out}"
elif printf '%s' "$_t3_out" | grep -q '^⚠️ renderer failed'; then
  bad "wrapper reported renderer failure under minimal PATH: ${_t3_out}"
else
  _rows="$(printf '%s\n' "$_t3_out" | awk 'BEGIN{c=0} $0=="---"{c++; next} c==1 && $0!="" {print}' | wc -l | tr -d ' ')"
  if [[ "$_rows" -ge 1 ]]; then
    ok "wrapper renders ${_rows} lane row(s) under minimal PATH + bash 3.2"
  elif [[ "$_t3_bash5_rows" -eq 0 ]]; then
    skip "no live lanes right now (0 rows under bash 5 too) — nothing to observe"
  else
    bad "0 lane rows under bash 3.2 but ${_t3_bash5_rows} under bash 5 — parser regression"
  fi
fi

echo "== T4: a dead renderer produces the failure title, never a confident 0/0 =="
STUB="$(mktemp -t leadv2-ss-stub)"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
echo "simulated renderer crash for test-status-surface-bash32" >&2
exit 3
STUBEOF
chmod +x "$STUB"
_t4_out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin LEADV2_STATUS_RENDERER="$STUB" /bin/bash "$WRAPPER" 2>&1)"
rm -f "$STUB"
if printf '%s' "$_t4_out" | grep -q 'renderer failed'; then
  if printf '%s' "$_t4_out" | grep -qE '🟢 0 / 🔴 0'; then
    bad "wrapper printed BOTH the failure title and a confident 0/0 count"
  else
    ok "wrapper reports renderer failure, not a confident 0/0"
  fi
else
  bad "wrapper did not report renderer failure for a dead renderer: ${_t4_out}"
fi

echo "== T5: STATUS-SURFACE-R5-01 — name resolution, unnamed, age-out, limits =="
# Fixture-driven cases against the RENDERER (not the wrapper) under /bin/bash 3.2.
# Every path the renderer reads is env-injected into a sandbox; nothing touches
# live state.
FIX="$(mktemp -d -t leadv2-ss-r5)"
cleanup_fix() { rm -rf "$FIX"; }
trap cleanup_fix EXIT
F_STATE="$FIX/state"; F_LED="$FIX/ledger"; F_RUNS="$FIX/cache"; F_HAND="$FIX/handoff"
mkdir -p "$F_STATE" "$F_LED" "$F_RUNS" "$F_HAND"
F_NOW=1780000000
REPO_FIX="r5repo"
F_LEDGER="${F_LED}/${REPO_FIX}.jsonl"; : > "$F_LEDGER"
# _fl <sig8> <arm> <handle> <state> <created_epoch>  — append a ledger row
_fl() { printf '{"task_sig":"%sffffffffffffffffffffffffffffffffffffffffffffff","arm":"%s","state":"%s","handle":"%s","created_epoch":%s}\n' \
        "$1" "$2" "$4" "$3" "$5" >> "$F_LEDGER"; }
# _fr <handle> <arm> <status> <exit_code> <journal_off_secs>  — write a run dir
_fr() { local d="${F_RUNS}/${2}-runs/${1}"; mkdir -p "$d"
        printf 'status: %s\nexit_code: %s\nmodel: glm-5.2\npid: 0\n' "$3" "$4" > "${d}/meta.yaml"
        : > "${d}/journal.jsonl"
        NOW="$F_NOW" python3 - "${d}/journal.jsonl" "$5" <<'PY'
import os, sys
p, off = sys.argv[1], int(sys.argv[2])
t = max(0, int(os.environ.get("NOW","0")) - off)
os.utime(p, (t, t))
PY
        }
render_fix() { LEADV2_STATUS_STATE_DIR="$F_STATE" LEADV2_STATUS_LEDGER_DIR="$F_LED" \
               LEADV2_STATUS_RUNS_ROOT="$F_RUNS" LEADV2_STATUS_REPO="$REPO_FIX" \
               LEADV2_STATUS_NOW="$F_NOW" LEADV2_STATUS_TASKS_YAML="$FIX/nope.yaml" \
               LEADV2_STATUS_HANDOFF_DIR="$F_HAND" /bin/bash "$RENDERER" "$@"; }

# --- R5-C1: name resolution from handoff architect-prepass.md + SIG column ---
mkdir -p "$F_HAND/dispatch-deadbeef"
printf '# FOO-BAR-01 — implementation design (architect prepass)\nbody\n' > "$F_HAND/dispatch-deadbeef/architect-prepass.md"
printf 'meta: {}\nsessions: []\n' > "$F_STATE/active.yaml"
_fl deadbeef glm h1 confirmed $((F_NOW-60))
_fr h1 glm complete 0 60
_o1="$(render_fix)"
if printf '%s\n' "$_o1" | grep -Eq 'FOO-BAR-01' && printf '%s\n' "$_o1" | grep -Eq 'deadbeef'; then
  ok "R5-C1: handoff architect-prepass.md title resolved into NAME, sig in SIG column"
else
  bad "R5-C1: name/sig (got: $(printf '%s' "$_o1" | tr '\n' '|'))"
fi

# --- R5-C2: a sig with no handoff dir and no tasks.yaml entry -> 'unnamed' ---
_fl 12345678 glm h2 confirmed $((F_NOW-60))
_fr h2 glm complete 0 60
_o2="$(render_fix)"
if printf '%s\n' "$_o2" | grep -Eq 'unnamed' \
   && ! printf '%s\n' "$_o2" | grep -Eq 'dispatch-12345678' \
   && ! printf '%s\n' "$_o2" | grep -Eq 'dispatch-deadbeef'; then
  ok "R5-C2: no-name lane renders exactly 'unnamed' (no dispatch-<sig8> in NAME)"
else
  bad "R5-C2: unnamed fallback (got: $(printf '%s' "$_o2" | tr '\n' '|'))"
fi

# --- R5-C3: age-out boundary at DONE_TTL=900 (899 present / 901 absent), live survives ---
: > "$F_LEDGER"; rm -rf "$F_HAND"/*; printf 'meta: {}\nsessions:\n  - { task_id: aaaaaaaa, phase: build, pid: '"$$"', log_path: "" }\n' > "$F_STATE/active.yaml"
_fl aaaaaaaa glm hl pending $((F_NOW-100000))   # live (alive pid $$ via session); pending=non-terminal
_fr hl glm running 0 100000
_fl bbbbbbbb glm h899 confirmed $((F_NOW-899))     # done, just inside TTL
_fr h899 glm complete 0 899
_fl cccccccc glm h901 confirmed $((F_NOW-901))     # done, just outside TTL
_fr h901 glm complete 0 901
_o3="$(LEADV2_STATUS_DONE_TTL_S=900 render_fix)"
_rc3=0
printf '%s\n' "$_o3" | grep -q 'aaaaaaaa' || _rc3=1     # live survives any age
printf '%s\n' "$_o3" | grep -q 'bbbbbbbb' || _rc3=1     # 899s done present
printf '%s\n' "$_o3" | grep -q 'cccccccc' && _rc3=1     # 901s done absent
printf '%s\n' "$_o3" | grep -Eq 'скрыто по возрасту' || _rc3=1   # header reports drop
if [ "$_rc3" -eq 0 ]; then
  ok "R5-C3: age-out boundary — live@100000 + done@899 present, done@901 absent, header counts drop"
else
  bad "R5-C3: boundary (got: $(printf '%s' "$_o3" | tr '\n' '|'))"
fi

# --- R5-C4: no fabricated claude % while the heuristic cap is in use ----------
FSNAP="$FIX/snap.txt"
printf '# stamped %s\nQuota: 5h 0%% (14508 / 8000000 in, claude%% only, cap est.) | weekly(claude,heuristic) 0%%\n  anthropic 5h: in 14.5K  cc 17.0M  cr 642.0M  out 2.8M  (3369 turns)\n  rate_limit:  not captured (heuristic cap in use)\n' "$F_NOW" > "$FSNAP"
_o4="$(LEADV2_STATUS_LIMITS_SNAPSHOT="$FSNAP" LEADV2_STATUS_NOW="$F_NOW" LEADV2_STATUS_BURN_DB="$FIX/nodb.db" /bin/bash "$RENDERER" --limits)"
if printf '%s\n' "$_o4" | grep -q 'не измеряется' \
   && ! printf '%s\n' "$_o4" | grep -Eq 'claude: 5h [0-9]+%'; then
  ok "R5-C4: heuristic cap -> 'не измеряется', no fabricated 'claude: N%'"
else
  bad "R5-C4: limits honesty (got: $(printf '%s' "$_o4" | tr '\n' '|'))"
fi

echo
echo "== T6: STATUS-SURFACE-R5-01 round 2 — minimal-env parity (PyYAML-optional reader) =="
# The bug class: works in a terminal (PyYAML present), dead in the menu bar
# (Xcode python3, no PyYAML). The reader now falls back to a pure-python
# mini-parser, so the minimal-PATH render must (a) contain none of the broken
# substrings and (b) match the full-env render's lane row-count AND urgent count.
_t6_min="$(env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash "$WRAPPER" 2>&1 || true)"
_t6_full="$(bash "$WRAPPER" 2>&1 || true)"
_t6_rc=0
# (a) no broken substring under the SwiftBar launch shape
for _bad in "module missing" "not parsed" "unreadable"; do
  if printf '%s' "$_t6_min" | grep -q "$_bad"; then
    bad "_t6: minimal-env render contains '$_bad'"; _t6_rc=1
  fi
done
# (b) lane row-count parity (section 1, lines after the header up to '---')
_lcount() { printf '%s\n' "$1" | awk 'BEGIN{c=0} $0=="---"{c++; next} c==1 && $0!="" {print}' | grep -c . || true; }
_min_rows="$(_lcount "$_t6_min")"
_full_rows="$(_lcount "$_t6_full")"
# urgent value (section 5, 'urgent: N (4h)')
_ucount() { printf '%s\n' "$1" | awk 'BEGIN{c=0} $0=="---"{c++; next} c==5 {print; exit}' | sed -n 's/^urgent: \([0-9]*\).*/\1/p'; }
_min_u="$(_ucount "$_t6_min")";  [ -z "$_min_u" ] && _min_u=-1
_full_u="$(_ucount "$_t6_full")"; [ -z "$_full_u" ] && _full_u=-1
if [ "$_t6_rc" -eq 0 ]; then
  ok "_t6a: minimal-env render has no broken substring"
else
  : # already bad()'d above
fi
if [ "$_min_rows" = "$_full_rows" ]; then
  ok "_t6b: lane row-count parity (min=$_min_rows full=$_full_rows)"
else
  bad "_t6b: lane row-count drift (min=$_min_rows full=$_full_rows)"; _t6_rc=1
fi
if [ "$_min_u" = "$_full_u" ]; then
  ok "_t6c: urgent parity (min=$_min_u full=$_full_u)"
else
  # Per the round-2 design: urgent divergence is NOT a PyYAML victim and is
  # deliberately left to this parity test to SURFACE. A mismatch here is a
  # follow-up task, recorded -- not a silent lie. FAIL loud so it gets filed.
  bad "_t6c: urgent divergence (min=$_min_u full=$_full_u) — file as follow-up"; _t6_rc=1
fi

echo
printf 'test-status-surface-bash32: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
