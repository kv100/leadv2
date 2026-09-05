#!/usr/bin/env bash
# tests/test-installer-settings-guard.sh — INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01.
#
# leadv2-repo-install.sh used to append the 17-key LEADV2_* env block straight
# into .claude/settings.json with no tracked-ness check. In a repo where that
# file is a committed, shared file (measured: ~/MythicalGames/m3) that leaked
# one developer's absolute paths and plugin routing knobs to the whole team.
#
# Fix: the write destination moves to .claude/settings.local.json (git-ignored
# by convention), with a hard leadv2_path_is_tracked() guard immediately
# before the write as defense-in-depth, and the install-log row names whichever
# file actually received the keys.
#
# Negative control: leadv2_path_is_tracked()'s body — replace the
# `git ls-files --error-unmatch` line with `return 1` ("always untracked") —
# must flip acceptance case (a)'s exit code 0 -> 1. RED with the mutation,
# GREEN after revert; both exit codes are printed verbatim below.
# run-all-triggers: leadv2-repo-install leadv2-settings-guard
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.

NEGATIVE_CONTROL_MUTATION="leadv2_path_is_tracked() body: git ls-files --error-unmatch replaced with 'return 1'"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GUARD_LIB="${ROOT}/plugins/leadv2/scripts/lib/leadv2-settings-guard.sh"
INSTALLER="${ROOT}/plugins/leadv2/scripts/leadv2-repo-install.sh"

for f in "$GUARD_LIB" "$INSTALLER"; do
  if [ ! -f "$f" ]; then
    printf 'FAIL: production script missing: %s\n' "$f" >&2
    exit 1
  fi
done

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/installer-settings-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Fixtures only — never the real ~/.claude: canonical scripts/agents point at
# empty dirs, the state base at $TMP, and a scoped GIT_CONFIG_GLOBAL +
# XDG_CONFIG_HOME keep the host's global excludes out of the fixtures. Both
# are required: this machine's core.excludesFile is unset, so git falls back
# to $XDG_CONFIG_HOME/git/ignore (measured: ~/.config/git/ignore already has
# `**/.claude/settings.local.json` — the exact founder-set global rule the
# INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01 brief documents), which
# GIT_CONFIG_GLOBAL alone does NOT override. Without both, the 5b ignore-heal
# path and the (f) tracked-local-json defense-in-depth path never fire in this
# suite: `git add` silently no-ops on an already-ignored path.
: > "$TMP/gitconfig"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
export XDG_CONFIG_HOME="$TMP/xdg-config"
mkdir -p "$XDG_CONFIG_HOME"
export LEADV2_CANONICAL_SCRIPTS="$TMP/canon-scripts"
export LEADV2_SHARED_AGENTS="$TMP/canon-agents"
export LEADV2_STATE_BASE="$TMP/state"
mkdir -p "$LEADV2_CANONICAL_SCRIPTS/lib" "$LEADV2_SHARED_AGENTS" "$LEADV2_STATE_BASE"
cp "$GUARD_LIB" "$LEADV2_CANONICAL_SCRIPTS/lib/leadv2-settings-guard.sh"

bash -n "$GUARD_LIB" 2>&1 && pass "bash -n leadv2-settings-guard.sh" || fail "bash -n leadv2-settings-guard.sh"
bash -n "$INSTALLER" 2>&1 && pass "bash -n leadv2-repo-install.sh" || fail "bash -n leadv2-repo-install.sh"

mkfixture() { # <dir>
  mkdir -p "$1/.claude"
  git -C "$1" init -q -b main >/dev/null
  git -C "$1" config user.email t@t
  git -C "$1" config user.name t
}

envkeys() { # <settings.local.json path>
  python3 -c "import json;print(len(json.load(open('$1')).get('env',{})))" 2>/dev/null || echo -1
}

# ── (a) guard predicate vs a TRACKED settings.json fixture ──────────────────
TRACKED_REPO="${TMP}/tracked"
mkfixture "$TRACKED_REPO"
echo '{"env":{}}' > "${TRACKED_REPO}/.claude/settings.json"
git -C "$TRACKED_REPO" add .claude/settings.json
git -C "$TRACKED_REPO" commit -qm fixture >/dev/null
SHA_BEFORE="$(shasum -a 256 "${TRACKED_REPO}/.claude/settings.json" | awk '{print $1}')"
( . "$GUARD_LIB" && leadv2_path_is_tracked "$TRACKED_REPO" .claude/settings.json )
rc_tracked=$?
SHA_AFTER="$(shasum -a 256 "${TRACKED_REPO}/.claude/settings.json" | awk '{print $1}')"
printf 'INFO: (a) guard vs tracked fixture exit=%s\n' "$rc_tracked"
[ "$rc_tracked" -eq 0 ] && pass "guard: tracked fixture -> exit 0" || fail "guard: tracked fixture -> exit ${rc_tracked} (want 0)"
[ "$SHA_BEFORE" = "$SHA_AFTER" ] && pass "guard: byte-identical (predicate never writes)" || fail "guard: file mutated by predicate"

( . "$GUARD_LIB" && leadv2_path_is_tracked "$TRACKED_REPO" .claude/nope.json )
rc_untracked=$?
[ "$rc_untracked" -eq 1 ] && pass "guard: untracked path -> exit 1" || fail "guard: untracked path -> exit ${rc_untracked} (want 1)"

# ── negative control: mutate the predicate body, prove RED, then GREEN ──────
MUT_LIB="${TMP}/leadv2-settings-guard.mutated.sh"
sed 's/git -C "\$repo" ls-files --error-unmatch -- "\$relpath" >\/dev\/null 2>&1/return 1/' "$GUARD_LIB" > "$MUT_LIB"
if grep -q 'git -C "\$repo" ls-files' "$MUT_LIB"; then
  fail "negative control: mutation did not apply (sed pattern stale vs GUARD_LIB body)"
else
  ( . "$MUT_LIB" && leadv2_path_is_tracked "$TRACKED_REPO" .claude/settings.json )
  rc_mutated=$?
  printf 'INFO: negative control unmutated_exit=%s mutated_exit=%s\n' "$rc_tracked" "$rc_mutated"
  if [ "$rc_tracked" -eq 0 ] && [ "$rc_mutated" -eq 1 ]; then
    pass "negative control: RED with mutation (0 -> 1), GREEN on revert"
  else
    fail "negative control: mutation did not flip the exit code (unmutated=${rc_tracked} mutated=${rc_mutated})"
  fi
fi

# ── (b) full installer, untracked repo — env lands in settings.local.json ───
UNTRACKED_REPO="${TMP}/untracked"
mkfixture "$UNTRACKED_REPO"
bash "$INSTALLER" --quiet "$UNTRACKED_REPO" >/dev/null 2>&1
rc_install_b=$?
[ "$rc_install_b" -eq 0 ] && pass "installer: exit 0 on untracked repo" || fail "installer: exit ${rc_install_b} on untracked repo"
if git -C "$UNTRACKED_REPO" ls-files --error-unmatch .claude/settings.local.json >/dev/null 2>&1; then
  fail "installer: settings.local.json got tracked"
else
  pass "installer: settings.local.json stays untracked"
fi
if [ -f "${UNTRACKED_REPO}/.claude/settings.json" ]; then
  fail "installer: settings.json was created (should stay absent)"
else
  pass "installer: settings.json untouched (absent)"
fi
K1="$(envkeys "${UNTRACKED_REPO}/.claude/settings.local.json")"
[ "${K1:-0}" -gt 0 ] 2>/dev/null && pass "installer: env keys landed in settings.local.json (${K1})" || fail "installer: settings.local.json has no env keys (${K1})"

# ── (c) idempotency — second run, no duplicate keys ──────────────────────────
bash "$INSTALLER" --quiet "$UNTRACKED_REPO" >/dev/null 2>&1
K2="$(envkeys "${UNTRACKED_REPO}/.claude/settings.local.json")"
[ "$K1" = "$K2" ] && pass "installer: idempotent (${K1} == ${K2})" || fail "installer: key count changed on second run (${K1} != ${K2})"

# ── (d) tracked settings.json case — env still lands in local, tracked byte-identical ──
DAMAGED_REPO="${TMP}/damaged"
mkfixture "$DAMAGED_REPO"
echo '{"env":{}}' > "${DAMAGED_REPO}/.claude/settings.json"
git -C "$DAMAGED_REPO" add .claude/settings.json
git -C "$DAMAGED_REPO" commit -qm fixture >/dev/null
SHA_D_BEFORE="$(shasum -a 256 "${DAMAGED_REPO}/.claude/settings.json" | awk '{print $1}')"
bash "$INSTALLER" --quiet "$DAMAGED_REPO" >/dev/null 2>&1
SHA_D_AFTER="$(shasum -a 256 "${DAMAGED_REPO}/.claude/settings.json" | awk '{print $1}')"
[ "$SHA_D_BEFORE" = "$SHA_D_AFTER" ] && pass "installer: tracked settings.json left byte-identical" || fail "installer: tracked settings.json was modified"
if [ -f "${DAMAGED_REPO}/.claude/settings.local.json" ]; then
  KD="$(envkeys "${DAMAGED_REPO}/.claude/settings.local.json")"
  [ "${KD:-0}" -gt 0 ] 2>/dev/null && pass "installer: tracked-repo case lands env in settings.local.json (${KD})" || fail "installer: tracked-repo case wrote no env keys (${KD})"
else
  fail "installer: tracked-repo case produced no settings.local.json"
fi
if git -C "$DAMAGED_REPO" ls-files --error-unmatch .claude/settings.local.json >/dev/null 2>&1; then
  fail "installer: settings.local.json got tracked in the damaged-repo case"
else
  pass "installer: settings.local.json stays untracked in the damaged-repo case"
fi

# ── (e) already-damaged repo (env already in the tracked file) is not re-nagged ──
NAGGED_REPO="${TMP}/nagged"
mkfixture "$NAGGED_REPO"
python3 -c "
import json
want={'ENABLE_TOOL_SEARCH':'x'}
json.dump({'env': {'ENABLE_TOOL_SEARCH':'auto:50','LEADV2_PULSE_MODE':'1','LEADV2_MAIN_MODEL':'opus','LEADV2_THINK_MODEL':'fable','LEADV2_FORCE_OPUS_LEAD':'0','LEADV2_WORKFLOW_ENABLED':'1','LEADV2_WIKI_INJECT':'0','LEADV2_LOOP_DETECT':'1','LEADV2_CORRECTION_DETECT':'1','LEADV2_LOOP_WARN_AT':'3','LEADV2_LOOP_HARD_AT':'5','LEADV2_SCORECARD_ON_CLOSE':'1','LEADV2_PARALLEL_DISPATCH':'1','LEADV2_DISPATCH_ARCHITECT_GATE':'1','MAX_MCP_OUTPUT_TOKENS':'15000','CLAUDE_PLUGIN_ROOT':'/x','LEADV2_PROJECT_ROOT':'/y'}}, open('${NAGGED_REPO}/.claude/settings.json','w'))
"
git -C "$NAGGED_REPO" add .claude/settings.json
git -C "$NAGGED_REPO" commit -qm "already damaged (17 keys already present)" >/dev/null
out_nagged="$(bash "$INSTALLER" --check "$NAGGED_REPO" 2>&1)"
if printf '%s' "$out_nagged" | grep -q 'settings.local.json env.*ok'; then
  pass "installer: already-damaged repo (17 keys already in tracked file) is not re-nagged"
else
  fail "installer: already-damaged repo still reports missing keys: $(printf '%s' "$out_nagged" | grep 'settings')"
fi

# ── (f) defense-in-depth — refuses whole install if settings.local.json is ever tracked ──
GUARDED_REPO="${TMP}/guarded"
mkfixture "$GUARDED_REPO"
echo '{}' > "${GUARDED_REPO}/.claude/settings.local.json"
git -C "$GUARDED_REPO" add -f .claude/settings.local.json
git -C "$GUARDED_REPO" commit -qm "tracked local (should never happen; simulated)" >/dev/null
out_guarded="$(bash "$INSTALLER" --quiet "$GUARDED_REPO" 2>&1)"
rc_guarded=$?
printf 'INFO: (f) guarded-repo install exit=%s\n' "$rc_guarded"
if [ "$rc_guarded" -ne 0 ] && printf '%s' "$out_guarded" | grep -q 'TRACKED by git'; then
  pass "installer: refuses the whole install when settings.local.json is tracked (exit ${rc_guarded})"
else
  fail "installer: did not refuse a tracked settings.local.json (exit ${rc_guarded}, output: ${out_guarded})"
fi

# ── (g) settings.local.json ignore-state heal — .git/info/exclude, never .gitignore ──
IGNORE_REPO="${TMP}/ignore"
mkfixture "$IGNORE_REPO"
if git -C "$IGNORE_REPO" check-ignore -q .claude/settings.local.json 2>/dev/null; then
  fail "ignore-heal fixture: settings.local.json already ignored before the installer ran (fixture isolation broken)"
else
  bash "$INSTALLER" --quiet "$IGNORE_REPO" >/dev/null 2>&1
  if git -C "$IGNORE_REPO" check-ignore -q .claude/settings.local.json 2>/dev/null; then
    pass "installer: settings.local.json becomes git-ignored after install"
  else
    fail "installer: settings.local.json still not git-ignored after install"
  fi
  if [ -f "${IGNORE_REPO}/.gitignore" ]; then
    fail "installer: wrote a tracked .gitignore instead of .git/info/exclude"
  else
    pass "installer: healed via .git/info/exclude only, no tracked .gitignore created"
  fi
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
