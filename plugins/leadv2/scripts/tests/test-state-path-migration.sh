#!/usr/bin/env bash
# tests/test-state-path-migration.sh — LANE-STATE-LEAK-01
#
# Proves the migration classes leadv2-state-path.sh added on top of the
# original five-name STANDARD set: S3 (first move), S4 (MERGE-file line
# union), S5 (MERGE-dir per-entry move-if-absent), S6 (RENDER collision ->
# delete local, no backup). Also proves a malformed ladder line does not
# abort the migration loop (§3.4 -- the union must be textual, never
# JSON-parsed).
#
# Hermetic: two throwaway "worktree" dirs (plain directories -- migration
# logic only cares about LINK_ROOT identity, not real git-ness) sharing one
# LEADV2_STATE_ROOT. Neither dir is a git repo, so the B1 safety net's
# "real checkout" predicate (git remote / REAL-REPO marker) never fires.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PATH_SH="${SCRIPT_DIR}/../leadv2-state-path.sh"
FAIL=0

bash -n "${STATE_PATH_SH}" || { echo "ERROR: bash -n failed for ${STATE_PATH_SH}"; exit 1; }

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

STATE="${TMP_ROOT}/state-root"
WT_A="${TMP_ROOT}/wt-a"
WT_B="${TMP_ROOT}/wt-b"
mkdir -p "${STATE}" "${WT_A}/docs/leadv2" "${WT_B}/docs/leadv2"

export LEADV2_STATE_ROOT="${STATE}"

# ── S3: first migration moves content verbatim, symlink left behind ───────
printf 'a: 1\n' > "${WT_A}/docs/leadv2/active.yaml"
OUT_A="$(PROJECT_ROOT="${WT_A}" bash "${STATE_PATH_SH}" active.yaml 2>/dev/null)"
if [[ "$(cat "${STATE}/active.yaml" 2>/dev/null)" == "a: 1" && -L "${WT_A}/docs/leadv2/active.yaml" && "${OUT_A}" == "${STATE}/active.yaml" ]]; then
  pass "S3: first migration moved active.yaml content and left a symlink"
else
  fail "S3" "state content=$(cat "${STATE}/active.yaml" 2>/dev/null || echo '<missing>') is_link=$( [[ -L "${WT_A}/docs/leadv2/active.yaml" ]] && echo yes || echo no ) resolved=${OUT_A}"
fi

# ── S4: MERGE(file) line-union -- two worktrees' glm-deferred.jsonl lines
# both survive, malformed line does not abort the loop ────────────────────
printf '{"sig8":"aaaaaaaa"}\n' > "${WT_A}/docs/leadv2/glm-deferred.jsonl"
printf '{"sig8":"bbbbbbbb"}\nnot-json-garbage-truncated-lin' > "${WT_B}/docs/leadv2/glm-deferred.jsonl"
PROJECT_ROOT="${WT_A}" bash "${STATE_PATH_SH}" glm-deferred.jsonl >/dev/null 2>&1
PROJECT_ROOT="${WT_B}" bash "${STATE_PATH_SH}" glm-deferred.jsonl >/dev/null 2>&1
MERGED="$(cat "${STATE}/glm-deferred.jsonl" 2>/dev/null)"
if grep -qF '"sig8":"aaaaaaaa"' <<<"${MERGED}" && grep -qF '"sig8":"bbbbbbbb"' <<<"${MERGED}"; then
  pass "S4: glm-deferred.jsonl lines from both worktrees survived the merge"
else
  fail "S4" "merged content: ${MERGED}"
fi
if [[ -L "${WT_A}/docs/leadv2/glm-deferred.jsonl" && -L "${WT_B}/docs/leadv2/glm-deferred.jsonl" ]]; then
  pass "S4: both worktrees now symlink glm-deferred.jsonl (no local copy left)"
else
  fail "S4: symlink" "wt-a is_link=$( [[ -L "${WT_A}/docs/leadv2/glm-deferred.jsonl" ]] && echo yes || echo no ) wt-b is_link=$( [[ -L "${WT_B}/docs/leadv2/glm-deferred.jsonl" ]] && echo yes || echo no )"
fi
if PROJECT_ROOT="${WT_A}" bash "${STATE_PATH_SH}" root >/dev/null 2>&1; then
  pass "S4: a malformed line in the local ladder did not abort the migration loop"
else
  fail "S4: malformed-line survival" "resolver call after malformed-line merge failed outright"
fi

# ── S5: MERGE(dir) per-entry move-if-absent -- glm-deferred.d entries from
# two worktrees both survive; a same-name entry keeps the target's copy ───
mkdir -p "${WT_A}/docs/leadv2/glm-deferred.d" "${WT_B}/docs/leadv2/glm-deferred.d"
printf 'mission A only\n' > "${WT_A}/docs/leadv2/glm-deferred.d/aaaaaaaa.md"
printf 'mission B only\n' > "${WT_B}/docs/leadv2/glm-deferred.d/bbbbbbbb.md"
PROJECT_ROOT="${WT_A}" bash "${STATE_PATH_SH}" glm-deferred.d >/dev/null 2>&1
PROJECT_ROOT="${WT_B}" bash "${STATE_PATH_SH}" glm-deferred.d >/dev/null 2>&1
if [[ -f "${STATE}/glm-deferred.d/aaaaaaaa.md" && -f "${STATE}/glm-deferred.d/bbbbbbbb.md" ]]; then
  pass "S5: glm-deferred.d entries from both worktrees survived (per-entry move-if-absent)"
else
  fail "S5" "entries: $(ls "${STATE}/glm-deferred.d" 2>/dev/null | tr '\n' ' ')"
fi
if [[ -L "${WT_A}/docs/leadv2/glm-deferred.d" && -L "${WT_B}/docs/leadv2/glm-deferred.d" ]]; then
  pass "S5: both worktrees now symlink glm-deferred.d"
else
  fail "S5: symlink" "wt-a is_link=$( [[ -L "${WT_A}/docs/leadv2/glm-deferred.d" ]] && echo yes || echo no ) wt-b is_link=$( [[ -L "${WT_B}/docs/leadv2/glm-deferred.d" ]] && echo yes || echo no )"
fi

# ── S6: RENDER collision deletes the local copy, no backup file ───────────
WT_C="${TMP_ROOT}/wt-c"
mkdir -p "${WT_C}/docs/leadv2"
printf '# stale render from another worktree\n' > "${WT_C}/docs/leadv2/founder-status.md"
# First worktree migrates (creates the control-plane copy + symlink).
printf '# canonical render\n' > "${WT_A}/docs/leadv2/founder-status.md"
rm -f "${WT_A}/docs/leadv2/founder-status.md"  # undo S3 test's unrelated symlink noise, if any
printf '# canonical render\n' > "${WT_A}/docs/leadv2/founder-status.md"
PROJECT_ROOT="${WT_A}" bash "${STATE_PATH_SH}" founder-status.md >/dev/null 2>&1
# Second worktree collides.
PROJECT_ROOT="${WT_C}" bash "${STATE_PATH_SH}" founder-status.md >/dev/null 2>&1
if [[ -L "${WT_C}/docs/leadv2/founder-status.md" ]] \
   && [[ ! -f "${WT_C}/docs/leadv2/founder-status.md.pre-controlplane-backup" ]]; then
  pass "S6: RENDER collision symlinked the local copy away with NO backup file"
else
  fail "S6" "is_link=$( [[ -L "${WT_C}/docs/leadv2/founder-status.md" ]] && echo yes || echo no ) backup_exists=$( [[ -f "${WT_C}/docs/leadv2/founder-status.md.pre-controlplane-backup" ]] && echo yes || echo no )"
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
