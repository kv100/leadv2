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
# run-all-triggers: leadv2-state-path
#
# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger
# marker and matched no name convention, so `run-all.sh --scope changed`
# never selected it — it could only ever run under `--scope all`. The
# triggers are the production files the suite's own body references most,
# with shared helpers excluded so a helper edit does not select everything.


set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_PATH_SH="${SCRIPT_DIR}/../leadv2-state-path.sh"
FAIL=0

bash -n "${STATE_PATH_SH}" || { echo "ERROR: bash -n failed for ${STATE_PATH_SH}"; exit 1; }

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=1; }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

# A mutant copy of leadv2-state-path.sh lands in TMP_ROOT and resolves its
# own SCRIPT_DIR to there, so it must find leadv2-portable-lock.sh as a
# sibling or it dies on `source` before reaching any migration logic --
# which looks identical to "did nothing harmful" and silently defeats any
# falsification whose assertion is "the file survived untouched" (S7).
cp "${SCRIPT_DIR}/../leadv2-portable-lock.sh" "${TMP_ROOT}/leadv2-portable-lock.sh"

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

# ── S7: git-tracked STANDARD name is never migrated/symlinked, even when a
# stale control-plane snapshot + backup already exist and the resolver is
# called for a DIFFERENT, unrelated name — the exact incident shape of
# OPEN-THREADS-TRUNCATED-SIX-TIMES-IN-ONE-NIGHT-01: a session in a real repo
# calling leadv2-state-path.sh for its own journal path silently converted a
# healthy, git-restored docs/leadv2/open-threads.md into a symlink pointing
# at a 9-hour-stale control-plane copy, because the STANDARD migration loop
# runs over EVERY name on EVERY call, not just the one requested. ─────────
WT_GIT="${TMP_ROOT}/wt-git"
STATE_GIT="${TMP_ROOT}/state-git"
mkdir -p "${WT_GIT}/docs/leadv2" "${STATE_GIT}"
git -C "${WT_GIT}" init -q
git -C "${WT_GIT}" config user.email test@example.com
git -C "${WT_GIT}" config user.name test
printf '# healthy, git-restored open threads\nreal content, 3 lines\n' > "${WT_GIT}/docs/leadv2/open-threads.md"
git -C "${WT_GIT}" add docs/leadv2/open-threads.md
git -C "${WT_GIT}" commit -q -m "tracked open-threads.md"
HEALTHY_CONTENT="$(cat "${WT_GIT}/docs/leadv2/open-threads.md")"
# Pre-seed ONLY a STALE control-plane target, no backup yet -- the exact
# collision shape that corrupts the file under the pre-fix code: target
# exists (an earlier migration from elsewhere), backup does not (this local
# copy was never previously the subject of one), so the pre-fix branch does
# `move(local, backup)` then falls through to `symlink(target, local)`. A
# pre-existing backup on top would make even the PRE-fix code a no-op here
# (its `else: continue` on backup-already-exists) -- that is not the
# incident shape, so the test must not seed one.
printf 'STALE 9-hour-old snapshot\n' > "${STATE_GIT}/open-threads.md"
# Call the resolver for an UNRELATED name -- reproducing "action at a
# distance": nobody asked about open-threads.md this call.
LEADV2_STATE_ROOT="${STATE_GIT}" PROJECT_ROOT="${WT_GIT}" bash "${STATE_PATH_SH}" active.yaml >/dev/null 2>&1
if [[ ! -L "${WT_GIT}/docs/leadv2/open-threads.md" ]] \
   && [[ "$(cat "${WT_GIT}/docs/leadv2/open-threads.md" 2>/dev/null)" == "${HEALTHY_CONTENT}" ]] \
   && [[ "$(cat "${STATE_GIT}/open-threads.md" 2>/dev/null)" == "STALE 9-hour-old snapshot" ]]; then
  pass "S7: git-tracked open-threads.md untouched by an unrelated resolver call, stale target left alone"
else
  fail "S7" "is_link=$( [[ -L "${WT_GIT}/docs/leadv2/open-threads.md" ]] && echo yes || echo no ) content=$(cat "${WT_GIT}/docs/leadv2/open-threads.md" 2>/dev/null)"
fi

# ── falsification for S7: prove the git-tracked guard actually matters ─────
# Mutant: production code with the `if is_git_tracked(name): continue` guard
# removed -- i.e. exactly this file's behaviour before the fix. Same
# git-tracked scenario as S7 through the mutant must corrupt the file;
# through the real (patched) resolver it must not.
PATCH_S7_PY="${TMP_ROOT}/patch-s7-mutant.py"
cat > "${PATCH_S7_PY}" <<'PYEOF'
import sys
src_path, dst_path = sys.argv[1], sys.argv[2]
src = open(src_path, encoding="utf-8").read()
anchor = "    if is_git_tracked(name):\n        continue\n\n    if os.path.islink(local):"
replacement = "    if os.path.islink(local):"
if anchor not in src:
    sys.stderr.write("ERROR: S7 falsification anchor not found -- source drifted from patcher\n")
    sys.exit(1)
open(dst_path, "w", encoding="utf-8").write(src.replace(anchor, replacement, 1))
PYEOF
MUTANT_S7_SH="${TMP_ROOT}/leadv2-state-path.s7-mutant.sh"
if ! python3 "${PATCH_S7_PY}" "${STATE_PATH_SH}" "${MUTANT_S7_SH}"; then
  echo "ERROR: S7 falsification mutant patch failed to apply"; exit 1
fi
chmod +x "${MUTANT_S7_SH}"

git_tracked_survives() {  # <state-path-bin> -> 0 if open-threads.md stays a real healthy file
  local bin="$1"
  local wt="${TMP_ROOT}/s7-falsify-wt-$$-${RANDOM}"
  local state="${TMP_ROOT}/s7-falsify-state-$$-${RANDOM}"
  mkdir -p "${wt}/docs/leadv2" "${state}"
  git -C "${wt}" init -q
  git -C "${wt}" config user.email test@example.com
  git -C "${wt}" config user.name test
  printf 'healthy tracked content\n' > "${wt}/docs/leadv2/open-threads.md"
  git -C "${wt}" add docs/leadv2/open-threads.md
  git -C "${wt}" commit -q -m tracked
  printf 'STALE\n' > "${state}/open-threads.md"
  LEADV2_STATE_ROOT="${state}" PROJECT_ROOT="${wt}" bash "${bin}" active.yaml >/dev/null 2>&1
  [[ ! -L "${wt}/docs/leadv2/open-threads.md" ]] && [[ "$(cat "${wt}/docs/leadv2/open-threads.md" 2>/dev/null)" == "healthy tracked content" ]]
}

git_tracked_survives "${MUTANT_S7_SH}"; s7_pre_rc=$?
git_tracked_survives "${STATE_PATH_SH}"; s7_post_rc=$?
if [[ ${s7_pre_rc} -ne 0 && ${s7_post_rc} -eq 0 ]]; then
  pass "falsification: pre-fix mutant corrupts the tracked file, real resolver leaves it alone"
  echo "RED-then-GREEN: state-path-git-tracked (pre_rc=${s7_pre_rc} -> post_rc=${s7_post_rc})"
else
  fail "S7-falsification" "mutant pre_rc=${s7_pre_rc} (want !=0) real post_rc=${s7_post_rc} (want 0)"
fi

# ── falsification: prove S4's line-union assertion can actually FAIL ───────
# Mutant: replace the MERGE(file) collision branch (target already exists)
# with an unconditional shutil.move(local, target) -- a clobber instead of a
# textual line-union. Run the SAME two-worktree merge scenario as S4 through
# the mutant: wt-a's line lands first, wt-b's collision then overwrites the
# target outright, so wt-a's line is lost. A copy of production code,
# mutated one branch, run through the suite's own merge scenario.
PATCH_PY="${TMP_ROOT}/patch-mutant.py"
cat > "${PATCH_PY}" <<'PYEOF'
import sys
src_path, dst_path = sys.argv[1], sys.argv[2]
src = open(src_path, encoding="utf-8").read()
anchor = '''        else:
            try:
                local_size = os.path.getsize(local)
            except OSError:
                local_size = 0
            if local_size > MERGE_SIZE_CAP:
                sys.stderr.write(
                    "[leadv2-state-path] %s exceeds merge size cap (%d bytes) -- "
                    "left un-migrated this invocation\\n" % (local, local_size)
                )
                continue
            try:
                with open(target, "r", encoding="utf-8", errors="replace") as fh:
                    existing_lines = set(line.rstrip("\\n") for line in fh)
            except OSError:
                existing_lines = set()
            try:
                with open(local, "r", encoding="utf-8", errors="replace") as fh:
                    local_lines = [line.rstrip("\\n") for line in fh]
            except OSError:
                local_lines = []
            new_lines = [ln for ln in local_lines if ln and ln not in existing_lines]
            try:
                if new_lines:
                    with open(target, "a", encoding="utf-8") as fh:
                        for ln in new_lines:
                            fh.write(ln + "\\n")
                os.remove(local)
            except OSError:
                continue'''
replacement = '''        else:
            # MUTANT (test-state-path-migration.sh falsification): clobber
            # instead of union.
            try:
                shutil.move(local, target)
            except OSError:
                continue'''
if anchor not in src:
    sys.stderr.write("ERROR: falsification anchor not found -- source drifted from patcher\n")
    sys.exit(1)
open(dst_path, "w", encoding="utf-8").write(src.replace(anchor, replacement, 1))
PYEOF
MUTANT_SH="${TMP_ROOT}/leadv2-state-path.mutant.sh"
if ! python3 "${PATCH_PY}" "${STATE_PATH_SH}" "${MUTANT_SH}"; then
  echo "ERROR: falsification mutant patch failed to apply"; exit 1
fi
chmod +x "${MUTANT_SH}"

merge_union_survives() {  # <state-path-bin> -> 0 if both sig8 lines survive, 1 otherwise
  local bin="$1"
  local state="${TMP_ROOT}/falsify-state-$$-${RANDOM}"
  local a="${TMP_ROOT}/falsify-a-$$-${RANDOM}"
  local b="${TMP_ROOT}/falsify-b-$$-${RANDOM}"
  mkdir -p "${state}" "${a}/docs/leadv2" "${b}/docs/leadv2"
  printf '{"sig8":"aaaaaaaa"}\n' > "${a}/docs/leadv2/glm-deferred.jsonl"
  printf '{"sig8":"bbbbbbbb"}\n' > "${b}/docs/leadv2/glm-deferred.jsonl"
  LEADV2_STATE_ROOT="${state}" PROJECT_ROOT="${a}" bash "${bin}" glm-deferred.jsonl >/dev/null 2>&1
  LEADV2_STATE_ROOT="${state}" PROJECT_ROOT="${b}" bash "${bin}" glm-deferred.jsonl >/dev/null 2>&1
  local merged; merged="$(cat "${state}/glm-deferred.jsonl" 2>/dev/null)"
  grep -qF '"sig8":"aaaaaaaa"' <<<"${merged}" && grep -qF '"sig8":"bbbbbbbb"' <<<"${merged}"
}

merge_union_survives "${MUTANT_SH}"; pre_rc=$?
merge_union_survives "${STATE_PATH_SH}"; post_rc=$?
if [[ ${pre_rc} -ne 0 && ${post_rc} -eq 0 ]]; then
  pass "falsification: clobber mutant loses wt-a's line, real resolver unions both"
  echo "RED-then-GREEN: state-path-migration (pre_rc=${pre_rc} -> post_rc=${post_rc})"
else
  fail "falsification" "mutant pre_rc=${pre_rc} (want !=0) real post_rc=${post_rc} (want 0)"
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
