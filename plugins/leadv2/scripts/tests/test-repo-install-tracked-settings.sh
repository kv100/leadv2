#!/usr/bin/env bash
# test-repo-install-tracked-settings.sh — INSTALLER-REFUSAL-URGENT-01
#
# leadv2-repo-install.sh must never write its env block into a git-TRACKED
# .claude/settings.json (it would ship the installing machine's absolute
# paths into whatever repo git tree the founder happens to be standing in —
# a real hazard when the installer runs inside an employer repo). A tracked
# file must route to .claude/settings.local.json instead; an untracked one
# keeps today's behaviour.
#
# Negative control: mutate _lv2_settings_is_tracked's body (inside the
# function, not a top-level insert) so it always reports "untracked". That
# must make a tracked settings.json get overwritten — proving the control
# is load-bearing, not decorative.
NEGATIVE_CONTROL_MUTATION="_lv2_settings_is_tracked always reports untracked"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL="$SCRIPTS_ROOT/leadv2-repo-install.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

bash -n "$INSTALL" 2>/dev/null || { echo "ERROR: install syntax check failed"; exit 1; }

ROOT="$(mktemp -d)"
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT

STATE_BASE="$ROOT/state"
run_install() {
  # $1 = installer script, $2 = repo, remaining = extra args
  local script="$1" repo="$2"; shift 2
  LEADV2_STATE_BASE="$STATE_BASE" "$script" "$@" "$repo"
}
sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

mk_git_repo() {
  local dir="$1"
  mkdir -p "$dir/.claude"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
}

# ---- Scenario A: tracked settings.json must be left byte-identical --------
REPO_A="$ROOT/repo-a"
mk_git_repo "$REPO_A"
cat > "$REPO_A/.claude/settings.json" <<'EOF'
{
  "env": { "EXISTING_KEY": "keep-me" }
}
EOF
git -C "$REPO_A" add .claude/settings.json
git -C "$REPO_A" commit -q -m "tracked settings"

SHA_BEFORE="$(sha "$REPO_A/.claude/settings.json")"
OUT1="$(run_install "$INSTALL" "$REPO_A" 2>&1)"
SHA_AFTER="$(sha "$REPO_A/.claude/settings.json")"

if [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then
  pass "scenario A: tracked settings.json byte-identical (sha ${SHA_BEFORE})"
else
  fail "scenario A: tracked settings.json CHANGED (${SHA_BEFORE} -> ${SHA_AFTER})"
fi

if [ -f "$REPO_A/.claude/settings.local.json" ] && grep -q 'LEADV2_PROJECT_ROOT' "$REPO_A/.claude/settings.local.json"; then
  pass "scenario A: env block landed in settings.local.json"
else
  fail "scenario A: env block missing from settings.local.json"
fi

if printf '%s\n' "$OUT1" | grep -qi 'tracked.*left untouched'; then
  pass "scenario A: stdout announces the tracked-file refusal"
else
  fail "scenario A: stdout missing tracked-file refusal message (got: ${OUT1})"
fi

# --check must target the SAME file write targeted (settings.local.json here) —
# otherwise it reports MISSING forever after a correct write.
run_install "$INSTALL" "$REPO_A" --check >/dev/null 2>&1
CHECK_RC=$?
if [ "$CHECK_RC" -eq 0 ]; then
  pass "scenario A: --check reports ok against settings.local.json (rc=0)"
else
  fail "scenario A: --check rc=${CHECK_RC}, expected 0 (must target settings.local.json like write did)"
fi

# idempotency: second write run must not duplicate/change anything
LOCAL_SHA_1="$(sha "$REPO_A/.claude/settings.local.json")"
run_install "$INSTALL" "$REPO_A" >/dev/null 2>&1
LOCAL_SHA_2="$(sha "$REPO_A/.claude/settings.local.json")"
TRACKED_SHA_2="$(sha "$REPO_A/.claude/settings.json")"
if [ "$LOCAL_SHA_1" = "$LOCAL_SHA_2" ]; then
  pass "scenario A: second run is idempotent (settings.local.json unchanged, no duplicate keys)"
else
  fail "scenario A: second run changed settings.local.json (${LOCAL_SHA_1} -> ${LOCAL_SHA_2})"
fi
if [ "$SHA_BEFORE" = "$TRACKED_SHA_2" ]; then
  pass "scenario A: tracked settings.json still byte-identical after second run"
else
  fail "scenario A: tracked settings.json drifted on second run"
fi

# ---- Scenario B: untrack the file -> env block goes to settings.json ------
git -C "$REPO_A" rm --cached -q .claude/settings.json
run_install "$INSTALL" "$REPO_A" >/dev/null 2>&1
if grep -q 'LEADV2_PROJECT_ROOT' "$REPO_A/.claude/settings.json"; then
  pass "scenario B: now-untracked settings.json receives the env block"
else
  fail "scenario B: now-untracked settings.json missing env block"
fi

SHA_B1="$(sha "$REPO_A/.claude/settings.json")"
run_install "$INSTALL" "$REPO_A" >/dev/null 2>&1
SHA_B2="$(sha "$REPO_A/.claude/settings.json")"
if [ "$SHA_B1" = "$SHA_B2" ]; then
  pass "scenario B: second run is idempotent (no duplicate keys)"
else
  fail "scenario B: second run changed settings.json (${SHA_B1} -> ${SHA_B2})"
fi

# ---- Regression guard: non-repo target unaffected --------------------------
PLAIN="$ROOT/plain"
mkdir -p "$PLAIN/.claude"
run_install "$INSTALL" "$PLAIN" >/dev/null 2>&1
if grep -q 'LEADV2_PROJECT_ROOT' "$PLAIN/.claude/settings.json"; then
  pass "non-repo target: env block written straight to settings.json as before"
else
  fail "non-repo target: env block missing from settings.json"
fi

# ---- Negative control -------------------------------------------------------
MUTATED_INSTALL="$ROOT/leadv2-repo-install-mutated.sh"
cp "$INSTALL" "$MUTATED_INSTALL"
sed -i.bak 's/^  git -C "\$1" ls-files --error-unmatch \.claude\/settings\.json >\/dev\/null 2>&1$/  return 1/' "$MUTATED_INSTALL"

if ! grep -A2 '^_lv2_settings_is_tracked() {' "$MUTATED_INSTALL" | grep -q '^  return 1$'; then
  fail "negative control: failed to apply mutation inside _lv2_settings_is_tracked body"
else
  MREPO="$ROOT/repo-mutated"
  mk_git_repo "$MREPO"
  printf '{"env":{}}\n' > "$MREPO/.claude/settings.json"
  git -C "$MREPO" add .claude/settings.json
  git -C "$MREPO" commit -q -m "tracked"
  MSHA_BEFORE="$(sha "$MREPO/.claude/settings.json")"
  run_install "$MUTATED_INSTALL" "$MREPO" >/dev/null 2>&1
  MSHA_AFTER="$(sha "$MREPO/.claude/settings.json")"
  if [ "$MSHA_BEFORE" != "$MSHA_AFTER" ]; then
    pass "negative control: mutation KILLED — tracked settings.json got overwritten as feared"
  else
    fail "negative control: mutation did not overwrite tracked settings.json (control too weak)"
  fi
fi

echo "----"
echo "PASS=${PASS} FAIL=${FAIL}"
[ "$FAIL" -eq 0 ]
