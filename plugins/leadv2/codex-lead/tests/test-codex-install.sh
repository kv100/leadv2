#!/usr/bin/env bash
# tests/test-codex-install.sh — CODEX-LEAD-FULL-01. HOME redirected to a
# fixture; install.sh run TWICE. Asserts: prompt count unchanged and
# byte-identical, exactly one repowise sentinel block, no second .bak from
# the second run, and the ACTION REQUIRED line when the fixture repo's
# AGENTS.md lacks the @import line.
#
# Run: bash plugins/leadv2/codex-lead/tests/test-codex-install.sh
# Exit 0 = all pass; non-zero = failures found.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_LEAD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$CODEX_LEAD_DIR/install.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

FIX_HOME="$FIX/home"
FIX_REPO="$FIX_HOME/Projects/persona-engine"
mkdir -p "$FIX_HOME" "$FIX_REPO"
printf '# fixture AGENTS.md\n\n@import ref/01-orchestrator.md\n' > "$FIX_REPO/AGENTS.md"

N_PROMPTS="$(ls -1 "$CODEX_LEAD_DIR/prompts"/*.md 2>/dev/null | wc -l | tr -d ' ')"

# --- run 1 --------------------------------------------------------------
OUT1="$(HOME="$FIX_HOME" bash "$INSTALL_SH" "$FIX_REPO" 2>&1)"; RC1=$?
[[ $RC1 -eq 0 ]] && pass "run 1: exit 0" || fail "run 1: exit 0 (rc=$RC1, out=$OUT1)"

GOT_PROMPTS="$(ls -1 "$FIX_HOME/.codex/prompts"/*.md 2>/dev/null | wc -l | tr -d ' ')"
[[ "$GOT_PROMPTS" == "$N_PROMPTS" ]] && pass "run 1: all $N_PROMPTS prompts installed" || fail "run 1: prompt count ($GOT_PROMPTS != $N_PROMPTS)"

[[ -f "$FIX_REPO/.claude/ref/90-codex-lead-pilot.md" ]] && pass "run 1: AGENTS-pilot ref file copied" || fail "run 1: AGENTS-pilot ref file missing"

SENTINEL_COUNT_1="$(grep -c 'BEGIN leadv2-codex-lead repowise' "$FIX_HOME/.codex/config.toml" 2>/dev/null || echo 0)"
[[ "$SENTINEL_COUNT_1" == "1" ]] && pass "run 1: exactly one repowise sentinel block" || fail "run 1: sentinel count = $SENTINEL_COUNT_1"

printf '%s' "$OUT1" | grep -q "ACTION REQUIRED" && pass "run 1: ACTION REQUIRED for missing @import line" || fail "run 1: expected ACTION REQUIRED (out=$OUT1)"

BAK_COUNT_1="$(find "$FIX_HOME/.codex" -name '*.bak' 2>/dev/null | wc -l | tr -d ' ')"

# --- run 2 (idempotency) --------------------------------------------------
OUT2="$(HOME="$FIX_HOME" bash "$INSTALL_SH" "$FIX_REPO" 2>&1)"; RC2=$?
[[ $RC2 -eq 0 ]] && pass "run 2: exit 0" || fail "run 2: exit 0 (rc=$RC2, out=$OUT2)"

GOT_PROMPTS_2="$(ls -1 "$FIX_HOME/.codex/prompts"/*.md 2>/dev/null | wc -l | tr -d ' ')"
[[ "$GOT_PROMPTS_2" == "$N_PROMPTS" ]] && pass "run 2: prompt count unchanged (no dupes)" || fail "run 2: prompt count ($GOT_PROMPTS_2 != $N_PROMPTS)"

UNCHANGED_COUNT="$(printf '%s' "$OUT2" | grep -c '^unchanged ')"
[[ "$UNCHANGED_COUNT" -ge "$N_PROMPTS" ]] && pass "run 2: every prompt reported unchanged" || fail "run 2: only $UNCHANGED_COUNT/$N_PROMPTS reported unchanged (out=$OUT2)"

printf '%s' "$OUT2" | grep -q 'AGENTS-pilot' 2>/dev/null; # no-op, ref copy message varies by name
printf '%s' "$OUT2" | grep -qE '^unchanged .*90-codex-lead-pilot\.md$' && pass "run 2: AGENTS-pilot ref reported unchanged" || fail "run 2: AGENTS-pilot ref not reported unchanged (out=$OUT2)"

SENTINEL_COUNT_2="$(grep -c 'BEGIN leadv2-codex-lead repowise' "$FIX_HOME/.codex/config.toml" 2>/dev/null || echo 0)"
[[ "$SENTINEL_COUNT_2" == "1" ]] && pass "run 2: still exactly one repowise sentinel block" || fail "run 2: sentinel count = $SENTINEL_COUNT_2"

printf '%s' "$OUT2" | grep -q "config.toml: repowise block unchanged" && pass "run 2: config.toml reported unchanged" || fail "run 2: config.toml change reported on re-run (out=$OUT2)"

BAK_COUNT_2="$(find "$FIX_HOME/.codex" -name '*.bak' 2>/dev/null | wc -l | tr -d ' ')"
[[ "$BAK_COUNT_2" == "$BAK_COUNT_1" ]] && pass "run 2: no new .bak files from an idempotent re-run" || fail "run 2: .bak count grew ($BAK_COUNT_1 -> $BAK_COUNT_2)"

# --- hand-written repowise block outside sentinels is never touched -------
FIX2="$(mktemp -d)"
FIX2_HOME="$FIX2/home"
FIX2_REPO="$FIX2_HOME/Projects/persona-engine"
mkdir -p "$FIX2_HOME/.codex" "$FIX2_REPO"
printf '@import .claude/ref/90-codex-lead-pilot.md\n' > "$FIX2_REPO/AGENTS.md"
cat > "$FIX2_HOME/.codex/config.toml" <<'EOF'
[mcp_servers.repowise]
command = "/hand/written/path.sh"
args = []
EOF
OUT3="$(HOME="$FIX2_HOME" bash "$INSTALL_SH" "$FIX2_REPO" 2>&1)"; RC3=$?
[[ $RC3 -eq 0 ]] && pass "hand-written block: exit 0" || fail "hand-written block: exit 0 (rc=$RC3)"
grep -q '/hand/written/path.sh' "$FIX2_HOME/.codex/config.toml" && pass "hand-written block: left untouched" || fail "hand-written block: was modified"
printf '%s' "$OUT3" | grep -q "already configured by hand" && pass "hand-written block: reported left-untouched message" || fail "hand-written block: missing left-untouched message (out=$OUT3)"
printf '%s' "$OUT3" | grep -q "@import line present" && pass "hand-written block: @import already present, no ACTION REQUIRED" || fail "hand-written block: unexpected @import handling (out=$OUT3)"
rm -rf "$FIX2"

# --- target repo missing -> rc 3 ------------------------------------------
FIX3_HOME="$(mktemp -d)"
OUT4="$(HOME="$FIX3_HOME" bash "$INSTALL_SH" "$FIX3_HOME/no-such-repo" 2>&1)"; RC4=$?
[[ $RC4 -eq 3 ]] && pass "missing target repo -> rc 3" || fail "missing target repo -> rc 3 (got rc=$RC4, out=$OUT4)"
rm -rf "$FIX3_HOME"

# --- bash -n --------------------------------------------------------------
bash -n "$INSTALL_SH" && pass "bash -n install.sh" || fail "bash -n install.sh"

echo
echo "==================================================="
echo "PASS: $PASS  FAIL: $FAIL"
echo "==================================================="
if [[ $FAIL -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
