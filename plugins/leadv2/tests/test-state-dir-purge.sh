#!/usr/bin/env bash
# tests/test-state-dir-purge.sh — STATE-DIR-JUNK-01 smoke tests.
#
# Everything here runs against a mktemp -d fixture with LEADV2_STATE_BASE
# pointed at it -- NEVER against the real ~/.claude/leadv2-state.
#
# Covers:
#   (1) leak fix, positive — a scratch `git init` repo with no
#       LEADV2_STATE_ROOT/LEADV2_STATE_BASE set resolves under
#       <base>/.ephemeral/<slug>, carrying a .ephemeral marker.
#   (2) leak fix, negative — same call against a repo with a remote resolves
#       under <base>/<slug>, no .ephemeral marker.
#   (3) renderer unaffected — leadv2-status-projects.sh --slugs against a
#       base containing .ephemeral/ does not list it.
#   (4) classification — one fixture of each class -> counts match.
#   (5) protection — --apply on a base containing persona-engine/leadv2/
#       respiro-ios leaves all three present, with every other flag set.
#   (6) escape — a symlink inside the base is REFUSED, never followed.
#   (7) dry-run is inert — --apply omitted -> file count before == after.
#   (8) age hold — a root touched now is HELD; back-dated 2d is EPHEMERAL.
#
# Usage: bash tests/test-state-dir-purge.sh
# Exit 0 = all pass; non-zero = failure count.
set -uo pipefail

SCRIPTS_DIR="${BASH_SOURCE[0]%/*}/../scripts"
STATE_PATH_SCRIPT="${SCRIPTS_DIR}/leadv2-state-path.sh"
PURGE_SCRIPT="${SCRIPTS_DIR}/leadv2-state-purge.sh"
STATUS_PROJECTS_SCRIPT="${SCRIPTS_DIR}/leadv2-status-projects.sh"

PASS=0
FAIL=0
pass() { printf -- 'PASS: %s\n' "$1"; PASS=$(( PASS + 1 )); }
fail() { printf -- 'FAIL: %s\n' "$1"; FAIL=$(( FAIL + 1 )); }

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

new_scratch_repo() { # -> repo path, git-init'd, no remote
  local d
  d="$(mktemp -d "${TMPDIR_BASE}/scratch.XXXXXX")"
  ( cd "$d" && git init -q -b main && git config user.email t@e.com \
    && git config user.name t && touch seed && git add seed \
    && git commit -qm seed ) >/dev/null 2>&1
  printf '%s' "$d"
}

new_repo_with_remote() { # -> repo path, git-init'd, has a remote
  local d
  d="$(new_scratch_repo)"
  git -C "$d" remote add origin "https://example.invalid/x.git" >/dev/null 2>&1
  printf '%s' "$d"
}

set_mtime_days_ago() { # <path> <days>
  local path="$1" days="$2" ts
  ts="$(date -u -v-"${days}"d +%Y%m%d%H%M.%S 2>/dev/null \
        || date -u -d "-${days} days" +%Y%m%d%H%M.%S 2>/dev/null)"
  [[ -n "$ts" ]] && touch -t "$ts" "$path" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Case 1/2: leak-fix redirect, positive and negative
#
# The redirect only fires when NEITHER LEADV2_STATE_ROOT NOR
# LEADV2_STATE_BASE is set (matching what production actually looks like --
# see the EPHEMERAL-REDIRECT comment in leadv2-state-path.sh). To scope the
# fixture's writes away from the real ~/.claude/leadv2-state without setting
# either of those, override HOME instead -- the script's default base is
# ${HOME}/.claude/leadv2-state, so a fixture HOME gives an isolated,
# `LEADV2_STATE_*`-unset base, i.e. the true "no LEADV2_STATE_* set"
# production-shaped code path this case is testing.
# ---------------------------------------------------------------------------
FAKE_HOME1="${TMPDIR_BASE}/fakehome1"
BASE1="${FAKE_HOME1}/.claude/leadv2-state"
mkdir -p "$BASE1"

SCRATCH1="$(new_scratch_repo)"
SLUG1="$(basename "$SCRATCH1")"
OUT1="$(env -u LEADV2_STATE_ROOT -u LEADV2_STATE_BASE HOME="$FAKE_HOME1" \
        PROJECT_ROOT="$SCRATCH1" bash "$STATE_PATH_SCRIPT" --no-link root 2>/dev/null)"
if [[ "$OUT1" == "${BASE1}/.ephemeral/${SLUG1}" && -f "${OUT1}/.ephemeral" ]]; then
  pass "case1: scratch repo, no LEADV2_STATE_* set -> redirects under .ephemeral/"
else
  fail "case1: expected ${BASE1}/.ephemeral/${SLUG1} with .ephemeral marker, got '${OUT1}'"
fi

REMOTE1="$(new_repo_with_remote)"
SLUGR1="$(basename "$REMOTE1")"
OUTR1="$(env -u LEADV2_STATE_ROOT -u LEADV2_STATE_BASE HOME="$FAKE_HOME1" \
         PROJECT_ROOT="$REMOTE1" bash "$STATE_PATH_SCRIPT" --no-link root 2>/dev/null)"
if [[ "$OUTR1" == "${BASE1}/${SLUGR1}" && ! -f "${BASE1}/.ephemeral/${SLUGR1}/.ephemeral" ]]; then
  pass "case2: repo with a remote, no LEADV2_STATE_* set -> top-level root, no .ephemeral marker"
else
  fail "case2: expected ${BASE1}/${SLUGR1} plain root, got '${OUTR1}'"
fi

# ---------------------------------------------------------------------------
# Case 3: renderer unaffected by .ephemeral/
# ---------------------------------------------------------------------------
BASE3="${TMPDIR_BASE}/base3"
mkdir -p "${BASE3}/.ephemeral/leadv2-lwt.abc123"
touch "${BASE3}/.ephemeral/leadv2-lwt.abc123/active.yaml"
mkdir -p "${BASE3}/persona-engine"
touch "${BASE3}/persona-engine/active.yaml"
echo "${TMPDIR_BASE}/pe-checkout" > "${BASE3}/persona-engine/.repo-root"
mkdir -p "${TMPDIR_BASE}/pe-checkout"

SLUGS3="$(LEADV2_STATE_BASE="$BASE3" bash "$STATUS_PROJECTS_SCRIPT" --slugs 2>/dev/null)"
if ! grep -q 'ephemeral' <<< "$SLUGS3" && ! grep -q 'leadv2-lwt' <<< "$SLUGS3"; then
  pass "case3: leadv2-status-projects.sh --slugs never lists .ephemeral/ contents"
else
  fail "case3: .ephemeral/ leaked into renderer output: ${SLUGS3}"
fi

# ---------------------------------------------------------------------------
# Case 4: classification counts
# ---------------------------------------------------------------------------
BASE4="${TMPDIR_BASE}/base4"
mkdir -p "$BASE4"

# PROTECTED
mkdir -p "${BASE4}/persona-engine"

# LIVE (via .repo-root pointing at a real dir)
mkdir -p "${BASE4}/dota-coach" "${TMPDIR_BASE}/dota-coach-checkout"
echo "${TMPDIR_BASE}/dota-coach-checkout" > "${BASE4}/dota-coach/.repo-root"

# EPHEMERAL by fixture-name pattern, old enough
mkdir -p "${BASE4}/leadv2-lwt.zz9999"
set_mtime_days_ago "${BASE4}/leadv2-lwt.zz9999" 3

# EPHEMERAL by .ephemeral marker
mkdir -p "${BASE4}/.ephemeral/some-scratch-repo"
touch "${BASE4}/.ephemeral/some-scratch-repo/.ephemeral"
set_mtime_days_ago "${BASE4}/.ephemeral/some-scratch-repo" 3

# HELD (fixture-named but fresh)
mkdir -p "${BASE4}/r1"

# UNKNOWN (back-dated past --min-age-days so it clears the HELD gate and
# actually reaches the "no match" branch, per the design's own class
# ordering: HELD is evaluated BEFORE the ephemeral/fixture check)
mkdir -p "${BASE4}/job-search"
set_mtime_days_ago "${BASE4}/job-search" 3

CLASSIFY_OUT="$(bash "$PURGE_SCRIPT" --base "$BASE4" --min-age-days 1 --dry-run 2>&1)"
CLASSIFY_RC=$?
if grep -q 'PROTECTED=1 LIVE=1 HELD=1 EPHEMERAL=2 UNKNOWN=1' <<< "$CLASSIFY_OUT"; then
  pass "case4: classification counts match (PROTECTED=1 LIVE=1 HELD=1 EPHEMERAL=2 UNKNOWN=1)"
else
  fail "case4: counts mismatch. Output:
${CLASSIFY_OUT}"
fi
if [[ "$CLASSIFY_RC" -eq 4 ]]; then
  pass "case4: exit code 4 when an UNKNOWN root is present"
else
  fail "case4: expected exit 4 (UNKNOWN present), got ${CLASSIFY_RC}"
fi

# ---------------------------------------------------------------------------
# Case 5: protection holds under --apply + every other flag
# ---------------------------------------------------------------------------
BASE5="${TMPDIR_BASE}/base5"
mkdir -p "${BASE5}/persona-engine" "${BASE5}/leadv2" "${BASE5}/respiro-ios" \
         "${BASE5}/leadv2-lwt.abc123"
set_mtime_days_ago "${BASE5}/leadv2-lwt.abc123" 10

bash "$PURGE_SCRIPT" --base "$BASE5" --min-age-days 0 --apply >/dev/null 2>&1

if [[ -d "${BASE5}/persona-engine" && -d "${BASE5}/leadv2" && -d "${BASE5}/respiro-ios" ]]; then
  pass "case5: all three protected slugs survive --apply"
else
  fail "case5: a protected slug was removed! remaining: $(ls "$BASE5" 2>/dev/null)"
fi
if [[ ! -d "${BASE5}/leadv2-lwt.abc123" ]]; then
  pass "case5: the non-protected fixture WAS removed by --apply (sanity check apply works at all)"
else
  fail "case5: --apply removed nothing at all -- test fixture invalid"
fi

# ---------------------------------------------------------------------------
# Case 6: symlink escape refused, never followed
# ---------------------------------------------------------------------------
BASE6="${TMPDIR_BASE}/base6"
OUTSIDE6="${TMPDIR_BASE}/outside-target"
mkdir -p "$BASE6" "$OUTSIDE6"
touch "${OUTSIDE6}/canary"
ln -s "$OUTSIDE6" "${BASE6}/escape-link"

OUT6="$(bash "$PURGE_SCRIPT" --base "$BASE6" --min-age-days 0 --dry-run 2>&1)"
if grep -q 'REFUSED' <<< "$OUT6" && [[ -f "${OUTSIDE6}/canary" ]]; then
  pass "case6: symlinked entry classified REFUSED, target untouched"
else
  fail "case6: symlink not refused as expected. Output:
${OUT6}"
fi
bash "$PURGE_SCRIPT" --base "$BASE6" --min-age-days 0 --apply >/dev/null 2>&1 || true
if [[ -f "${OUTSIDE6}/canary" ]]; then
  pass "case6: --apply does not delete through the symlink"
else
  fail "case6: --apply followed the symlink and deleted outside content"
fi

# ---------------------------------------------------------------------------
# Case 7: dry-run is inert
# ---------------------------------------------------------------------------
BASE7="${TMPDIR_BASE}/base7"
mkdir -p "${BASE7}/leadv2-lwt.dryrun1" "${BASE7}/tmp.abcdefgh"
set_mtime_days_ago "${BASE7}/leadv2-lwt.dryrun1" 5
set_mtime_days_ago "${BASE7}/tmp.abcdefgh" 5
BEFORE7="$(find "$BASE7" -mindepth 1 | wc -l | tr -d ' ')"
bash "$PURGE_SCRIPT" --base "$BASE7" --min-age-days 1 --dry-run >/dev/null 2>&1
AFTER7="$(find "$BASE7" -mindepth 1 | wc -l | tr -d ' ')"
if [[ "$BEFORE7" == "$AFTER7" ]]; then
  pass "case7: --dry-run (default) makes zero filesystem changes"
else
  fail "case7: dry-run changed file count: before=${BEFORE7} after=${AFTER7}"
fi

# ---------------------------------------------------------------------------
# Case 8: age hold
# ---------------------------------------------------------------------------
BASE8="${TMPDIR_BASE}/base8"
mkdir -p "${BASE8}/repo" "${BASE8}/repo4"
set_mtime_days_ago "${BASE8}/repo4" 2

OUT8="$(bash "$PURGE_SCRIPT" --base "$BASE8" --min-age-days 1 --dry-run 2>&1)"
if grep -qE '^HELD\trepo\t' <<< "$OUT8" && grep -qE '^EPHEMERAL\trepo4\t' <<< "$OUT8"; then
  pass "case8: fresh root HELD, back-dated root EPHEMERAL under the same --min-age-days"
else
  fail "case8: age-hold mismatch. Output:
${OUT8}"
fi

# ---------------------------------------------------------------------------
printf -- '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
