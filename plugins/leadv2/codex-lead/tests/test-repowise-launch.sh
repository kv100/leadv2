#!/usr/bin/env bash
# tests/test-repowise-launch.sh — MERGED-BATCH-FIXROUND-01 H6: the marketplace
# repowise MCP launcher shipped with `bash -n` as its only coverage. These
# cases exercise the live path hermetically: every case runs under a
# mktemp -d sandbox with a stub repowise-mcp.sh that prints a sentinel, so a
# pass proves the launcher actually exec'd the stub (sentinel on stdout), not
# that it merely parsed. Covers the two silent-absence modes the fix makes
# audible: a dead LEADV2_REPOWISE_MCP override (now announced on stderr) and
# a walk that finds nothing (now names the start directory on stderr).
#
# Run: bash plugins/leadv2/codex-lead/tests/test-repowise-launch.sh
# Exit 0 = all pass; non-zero = failures found.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_LEAD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$CODEX_LEAD_DIR/marketplace/plugins/leadv2/scripts/repowise-launch.sh"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

FIX="$(mktemp -d "${TMPDIR:-/tmp}/rwlaunch-test.XXXXXX")"
# TMPDIR can end in a slash, so mktemp prints a double-slash path that `cd`
# later normalises — canonicalise once so path-glob assertions match $PWD.
FIX="$(cd "$FIX" && pwd)"
trap 'rm -rf "$FIX"' EXIT

# stub_server <path> <sentinel>: a stand-in repowise MCP server.
stub_server() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<STUB
#!/usr/bin/env bash
echo "$2"
STUB
  chmod +x "$1"
}

# --- Case 1: LEADV2_REPOWISE_MCP override is honoured ----------------------
log "Case 1: override set + file exists -> stub runs"
stub_server "$FIX/override-mcp.sh" "SENTINEL-OVERRIDE"
out="$(cd "$FIX" && LEADV2_REPOWISE_MCP="$FIX/override-mcp.sh" bash "$LAUNCHER" 2>/dev/null)"
if [[ "$out" == *"SENTINEL-OVERRIDE"* ]]; then
  pass "Case 1: override exec'd, sentinel on stdout"
else
  fail "Case 1: out=[$out]"
fi

# --- Case 2: dead override falls back to the walk AND announces it --------
log "Case 2: override set but file missing -> walk fallback + stderr announcement"
stub_server "$FIX/walkrepo/.repowise/repowise-mcp.sh" "SENTINEL-WALK"
out="$(cd "$FIX/walkrepo" && LEADV2_REPOWISE_MCP="$FIX/nonexistent-mcp.sh" bash "$LAUNCHER" 2>"$FIX/err2")"
err="$(cat "$FIX/err2")"
if [[ "$out" == *"SENTINEL-WALK"* && "$err" == *"LEADV2_REPOWISE_MCP="*"override ignored"* ]]; then
  pass "Case 2: walk sentinel + ignored-override stderr line"
else
  fail "Case 2: out=[$out] err=[$err]"
fi

# --- Case 3: walk finds the server at the cwd -----------------------------
log "Case 3: .repowise at cwd -> stub runs"
stub_server "$FIX/atcwd/.repowise/repowise-mcp.sh" "SENTINEL-ATCWD"
out="$(cd "$FIX/atcwd" && bash "$LAUNCHER" 2>/dev/null)"
if [[ "$out" == *"SENTINEL-ATCWD"* ]]; then
  pass "Case 3: cwd-level .repowise exec'd"
else
  fail "Case 3: out=[$out]"
fi

# --- Case 4: walk finds the server 3 levels up ----------------------------
log "Case 4: .repowise 3 dirs above cwd -> stub runs"
stub_server "$FIX/deep/.repowise/repowise-mcp.sh" "SENTINEL-UP3"
out="$(cd "$FIX/deep/a/b/c" 2>/dev/null || { mkdir -p "$FIX/deep/a/b/c"; cd "$FIX/deep/a/b/c"; } && bash "$LAUNCHER" 2>/dev/null)"
if [[ "$out" == *"SENTINEL-UP3"* ]]; then
  pass "Case 4: upward walk exec'd the stub 3 levels up"
else
  fail "Case 4: out=[$out]"
fi

# --- Case 5: nothing found -> exit 0, silent stdout, loud stderr ----------
log "Case 5: no .repowise anywhere up -> rc 0, empty stdout, stderr names start dir"
mkdir -p "$FIX/nowhere/x"
rc_out="$(cd "$FIX/nowhere/x" && bash "$LAUNCHER" 2>"$FIX/err5")"
rc=$?
err="$(cat "$FIX/err5")"
if [[ "$rc" == "0" && -z "$rc_out" && "$err" == *"no .repowise/repowise-mcp.sh found walking up from"*"$FIX/nowhere/x"* && "$err" == *"repowise MCP unavailable"* ]]; then
  pass "Case 5: rc 0 + start-dir stderr line (silent absence made observable)"
else
  fail "Case 5: rc=$rc out=[$rc_out] err=[$err]"
fi

# --- Case 6: argv passthrough ----------------------------------------------
log "Case 6: launcher argv reaches the server verbatim"
stub_server "$FIX/argsrepo/.repowise/repowise-mcp.sh" "SENTINEL-ARGS"
cat > "$FIX/argsrepo/.repowise/repowise-mcp.sh" <<'STUB'
#!/usr/bin/env bash
echo "ARGS:$*"
STUB
chmod +x "$FIX/argsrepo/.repowise/repowise-mcp.sh"
out="$(cd "$FIX/argsrepo" && bash "$LAUNCHER" --flag one "two words" 2>/dev/null)"
if [[ "$out" == *"ARGS:--flag one two words"* ]]; then
  pass "Case 6: argv passed through verbatim"
else
  fail "Case 6: out=[$out]"
fi

echo ""
log "=== Results: PASS=$PASS FAIL=$FAIL ==="
if [[ "${#ERRORS[@]}" -gt 0 ]]; then
  log "Failures:"
  for e in "${ERRORS[@]}"; do log "  $e"; done
  exit 1
fi
log "All tests passed."
exit 0
