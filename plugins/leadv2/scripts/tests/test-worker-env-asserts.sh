#!/usr/bin/env bash
# test-worker-env-asserts.sh — V3-ENV-GUARDS-01 item 3
# Extracts _worker_env_asserts (+ its emit/log deps) from leadv2-dispatch-code.sh
# and unit-tests it: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS must always end up
# unset/0 in the process env after the call, CLAUDE_CODE_ENABLE_TODO_TOOLS
# must be set to 1 (unless opted out), and exactly two journal lines land per
# call — the case that matters most is the one where a stray shell profile on
# the founder's machine exported AGENT_TEAMS=1 before the dispatcher ran.

set -euo pipefail

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
DISPATCH="$TEST_DIR/../leadv2-dispatch-code.sh"

pass=0
fail=0
cleanup_items=()
cleanup() {
  for item in "${cleanup_items[@]:-}"; do
    rm -rf "$item" 2>/dev/null || true
  done
}
trap cleanup EXIT

harness="$(mktemp -d)"
cleanup_items+=("$harness")
harness_script="$harness/harness.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'set +e'
  echo 'SCRIPT_NAME=test-worker-env-asserts'
  echo 'log()        { printf "[%s] %s\n" "$SCRIPT_NAME" "$*" >&2; }'
  sed -n '/^emit()/,/^}$/p' "$DISPATCH"
  sed -n '/^_worker_env_asserts()/,/^}$/p' "$DISPATCH"
  echo '"$@"'
} > "$harness_script"
chmod +x "$harness_script"

if ! grep -q '^_worker_env_asserts()' "$harness_script"; then
  echo "[WORKER-ENV-ASSERTS] FAIL: _worker_env_asserts not found in $DISPATCH (extraction broke, or fn renamed)" >&2
  fail=$((fail + 1))
fi

journal_dir="$(mktemp -d)"
cleanup_items+=("$journal_dir")
journal_bin="$journal_dir/journal.sh"
journal_log="$journal_dir/journal.log"
cat >"$journal_bin" <<EOF
#!/usr/bin/env bash
# stub journal: append <task> <type> <text> -> one line to $journal_log
shift  # "append"
printf '%s|%s|%s\n' "\$1" "\$2" "\$3" >> "$journal_log"
EOF
chmod +x "$journal_bin"

# --- case 1: AGENT_TEAMS=1 leaked in from the ambient env -- must be unset --
env_snapshot="$harness/env-after.txt"
rm -f "$journal_log"
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 JOURNAL_BIN="$journal_bin" JOURNAL_TASK=sig8test \
  bash -c "source '$harness_script'; _worker_env_asserts codex sig8test; env | grep -E '^CLAUDE_CODE_' > '$env_snapshot' || true"

echo "[WORKER-ENV-ASSERTS] case 1: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 leaked in -> must be unset for the worker"
if ! grep -q '^CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=' "$env_snapshot"; then
  echo "[WORKER-ENV-ASSERTS]   var absent from the post-assert env ✓"
  pass=$((pass + 1))
else
  echo "[WORKER-ENV-ASSERTS]   FAIL: var still present:" >&2
  cat "$env_snapshot" >&2
  fail=$((fail + 1))
fi

echo "[WORKER-ENV-ASSERTS] case 1b: journal shows action=unset was=1"
if grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=unset was=1' "$journal_log" 2>/dev/null; then
  echo "[WORKER-ENV-ASSERTS]   journal line present ✓"
  pass=$((pass + 1))
else
  echo "[WORKER-ENV-ASSERTS]   FAIL: journal missing the unset line:" >&2
  cat "$journal_log" >&2 2>/dev/null || echo "  (no journal file)" >&2
  fail=$((fail + 1))
fi

echo "[WORKER-ENV-ASSERTS] case 1c: CLAUDE_CODE_ENABLE_TODO_TOOLS set to 1 for the worker"
if grep -q '^CLAUDE_CODE_ENABLE_TODO_TOOLS=1$' "$env_snapshot"; then
  echo "[WORKER-ENV-ASSERTS]   var set to 1 ✓"
  pass=$((pass + 1))
else
  echo "[WORKER-ENV-ASSERTS]   FAIL: var not set to 1:" >&2
  cat "$env_snapshot" >&2
  fail=$((fail + 1))
fi

echo "[WORKER-ENV-ASSERTS] case 1d: exactly two journal lines per call"
line_count="$(wc -l < "$journal_log" | tr -d ' ')"
if [ "$line_count" = "2" ]; then
  echo "[WORKER-ENV-ASSERTS]   exactly 2 lines ✓"
  pass=$((pass + 1))
else
  echo "[WORKER-ENV-ASSERTS]   FAIL: expected 2 journal lines, got $line_count:" >&2
  cat "$journal_log" >&2 2>/dev/null || true
  fail=$((fail + 1))
fi

# --- case 2: AGENT_TEAMS already unset -- action=ok, no-op ------------------
rm -f "$journal_log"
env -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS JOURNAL_BIN="$journal_bin" JOURNAL_TASK=sig8test \
  bash -c "source '$harness_script'; _worker_env_asserts glm sig8test"

echo "[WORKER-ENV-ASSERTS] case 2: AGENT_TEAMS already unset -> action=ok"
if grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok' "$journal_log" 2>/dev/null; then
  echo "[WORKER-ENV-ASSERTS]   ok-line present ✓"
  pass=$((pass + 1))
else
  echo "[WORKER-ENV-ASSERTS]   FAIL: missing action=ok line:" >&2
  cat "$journal_log" >&2 2>/dev/null || true
  fail=$((fail + 1))
fi

# --- case 3: opt-out via LEADV2_WORKER_TODO_TOOLS=0 --------------------------
rm -f "$journal_log"
LEADV2_WORKER_TODO_TOOLS=0 JOURNAL_BIN="$journal_bin" JOURNAL_TASK=sig8test \
  bash -c "source '$harness_script'; _worker_env_asserts sonnet sig8test"

echo "[WORKER-ENV-ASSERTS] case 3: LEADV2_WORKER_TODO_TOOLS=0 -> skip, opt_out"
if grep -q 'CLAUDE_CODE_ENABLE_TODO_TOOLS action=skip reason=opt_out' "$journal_log" 2>/dev/null; then
  echo "[WORKER-ENV-ASSERTS]   skip-line present ✓"
  pass=$((pass + 1))
else
  echo "[WORKER-ENV-ASSERTS]   FAIL: missing action=skip line:" >&2
  cat "$journal_log" >&2 2>/dev/null || true
  fail=$((fail + 1))
fi

echo "[WORKER-ENV-ASSERTS] pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
