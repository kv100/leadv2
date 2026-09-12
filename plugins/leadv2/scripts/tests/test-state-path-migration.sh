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

# ── S6: DELETED (ONE-STATUS-MECHANISM-01, 2026-09-13): the RENDER class
# lost its only members (the founder-status render set) with the retired
# beat chain; collision semantics are untestable until a new render exists.

# ── S7 (ROOT FIX; OPEN-THREADS-IS-NOT-CONTROL-PLANE-STATE-01, 2026-09-07):
# open-threads.md is not merely git-tracked-and-skipped any more -- it is
# ABSENT from the STANDARD dict entirely, because it is authored content
# with irrecoverable history (the founder's verbatim permissions live only
# in it), not regenerable runtime state. Empirical tie-breaker over the
# is_git_tracked() heuristic alone: git recovered this file's content NINE
# TIMES OUT OF NINE over one incident night; the control-plane copy was a
# stale 15-line snapshot that preserved nothing. This test proves the root
# fix: even with NO stale target and NO backup pre-seeded (there is nothing
# to collide with -- the name is never considered at all), a resolver call
# for a completely unrelated name leaves a healthy, git-tracked
# open-threads.md untouched. ───────────────────────────────────────────────
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
# Call the resolver for an UNRELATED name -- reproducing "action at a
# distance": nobody asked about open-threads.md this call.
LEADV2_STATE_ROOT="${STATE_GIT}" PROJECT_ROOT="${WT_GIT}" bash "${STATE_PATH_SH}" active.yaml >/dev/null 2>&1
if [[ ! -L "${WT_GIT}/docs/leadv2/open-threads.md" ]] \
   && [[ "$(cat "${WT_GIT}/docs/leadv2/open-threads.md" 2>/dev/null)" == "${HEALTHY_CONTENT}" ]] \
   && [[ ! -e "${STATE_GIT}/open-threads.md" ]]; then
  pass "S7: open-threads.md untouched by an unrelated resolver call -- not even considered, no control-plane copy created"
else
  fail "S7" "is_link=$( [[ -L "${WT_GIT}/docs/leadv2/open-threads.md" ]] && echo yes || echo no ) content=$(cat "${WT_GIT}/docs/leadv2/open-threads.md" 2>/dev/null) state_copy_exists=$( [[ -e "${STATE_GIT}/open-threads.md" ]] && echo yes || echo no )"
fi

# ── S7-defense-in-depth: open-threads.md survives even if the is_git_tracked()
# second-layer guard were entirely removed -- proving the ROOT fix (removal
# from STANDARD) is what actually protects it, not merely the guard this
# task landed first. If this test ever needs the guard to pass, the removal
# from STANDARD has regressed. ─────────────────────────────────────────────
PATCH_NOGUARD_PY="${TMP_ROOT}/patch-noguard-mutant.py"
cat > "${PATCH_NOGUARD_PY}" <<'PYEOF'
import re
import sys
src_path, dst_path = sys.argv[1], sys.argv[2]
src = open(src_path, encoding="utf-8").read()
pattern = re.compile(
    r"    if is_git_tracked\(name\):\n(?:.*\n)*?        continue\n"
)
if not pattern.search(src):
    sys.stderr.write("ERROR: defense-in-depth anchor not found -- source drifted from patcher\n")
    sys.exit(1)
mutated = pattern.sub("", src, count=1)
open(dst_path, "w", encoding="utf-8").write(mutated)
PYEOF
MUTANT_NOGUARD_SH="${TMP_ROOT}/leadv2-state-path.noguard-mutant.sh"
if ! python3 "${PATCH_NOGUARD_PY}" "${STATE_PATH_SH}" "${MUTANT_NOGUARD_SH}"; then
  echo "ERROR: defense-in-depth mutant patch failed to apply"; exit 1
fi
chmod +x "${MUTANT_NOGUARD_SH}"

# Positive control on this mutant too (same lesson as below): prove it can
# still do an ordinary migration before trusting its "survives" result.
NOGUARD_POSCTRL_WT="${TMP_ROOT}/s7-noguard-posctrl-wt"
NOGUARD_POSCTRL_STATE="${TMP_ROOT}/s7-noguard-posctrl-state"
mkdir -p "${NOGUARD_POSCTRL_WT}/docs/leadv2" "${NOGUARD_POSCTRL_STATE}"
printf 'ordinary content\n' > "${NOGUARD_POSCTRL_WT}/docs/leadv2/active.yaml"
LEADV2_STATE_ROOT="${NOGUARD_POSCTRL_STATE}" PROJECT_ROOT="${NOGUARD_POSCTRL_WT}" bash "${MUTANT_NOGUARD_SH}" active.yaml >/dev/null 2>&1
if [[ "$(cat "${NOGUARD_POSCTRL_STATE}/active.yaml" 2>/dev/null)" != "ordinary content" ]]; then
  fail "S7-defense-in-depth-positive-control" "no-guard mutant appears dead on arrival"
fi

WT_NOGUARD="${TMP_ROOT}/wt-noguard"
mkdir -p "${WT_NOGUARD}/docs/leadv2"
git -C "${WT_NOGUARD}" init -q
git -C "${WT_NOGUARD}" config user.email test@example.com
git -C "${WT_NOGUARD}" config user.name test
printf 'healthy tracked content\n' > "${WT_NOGUARD}/docs/leadv2/open-threads.md"
git -C "${WT_NOGUARD}" add docs/leadv2/open-threads.md
git -C "${WT_NOGUARD}" commit -q -m tracked
LEADV2_STATE_ROOT="${TMP_ROOT}/state-noguard" PROJECT_ROOT="${WT_NOGUARD}" bash "${MUTANT_NOGUARD_SH}" active.yaml >/dev/null 2>&1
if [[ ! -L "${WT_NOGUARD}/docs/leadv2/open-threads.md" ]] \
   && [[ "$(cat "${WT_NOGUARD}/docs/leadv2/open-threads.md" 2>/dev/null)" == "healthy tracked content" ]]; then
  pass "S7-defense-in-depth: open-threads.md survives even with the is_git_tracked() guard removed -- STANDARD-removal is the real protection"
else
  fail "S7-defense-in-depth" "open-threads.md was touched even without the guard in play -- STANDARD-removal may have regressed"
fi

# ── S8 (the git-tracked-skip guard's remaining job): a STANDARD name that IS
# still in the dict (active.yaml) but tracked BY MISTAKE (this repo's own
# docs/leadv2/active.yaml, found tracked when it should be gitignored) must
# still be protected by is_git_tracked(), loudly. ──────────────────────────
WT_S8="${TMP_ROOT}/wt-s8"
STATE_S8="${TMP_ROOT}/state-s8"
mkdir -p "${WT_S8}/docs/leadv2" "${STATE_S8}"
git -C "${WT_S8}" init -q
git -C "${WT_S8}" config user.email test@example.com
git -C "${WT_S8}" config user.name test
printf 'tracked-by-mistake registry\n' > "${WT_S8}/docs/leadv2/active.yaml"
git -C "${WT_S8}" add docs/leadv2/active.yaml
git -C "${WT_S8}" commit -q -m "active.yaml tracked by mistake"
S8_HEALTHY="$(cat "${WT_S8}/docs/leadv2/active.yaml")"
printf 'stale control-plane snapshot\n' > "${STATE_S8}/active.yaml"
# Call the resolver for a DIFFERENT unrelated name.
LEADV2_STATE_ROOT="${STATE_S8}" PROJECT_ROOT="${WT_S8}" bash "${STATE_PATH_SH}" bus.jsonl >/dev/null 2>&1
if [[ ! -L "${WT_S8}/docs/leadv2/active.yaml" ]] \
   && [[ "$(cat "${WT_S8}/docs/leadv2/active.yaml" 2>/dev/null)" == "${S8_HEALTHY}" ]]; then
  pass "S8: a STANDARD name tracked by mistake (active.yaml) is still protected by is_git_tracked()"
else
  fail "S8" "is_link=$( [[ -L "${WT_S8}/docs/leadv2/active.yaml" ]] && echo yes || echo no ) content=$(cat "${WT_S8}/docs/leadv2/active.yaml" 2>/dev/null)"
fi

SKIP_LOG="${STATE_S8}/.git-tracked-skips.log"
# Match on the tmp dir's basename, not the full path: macOS resolves /tmp
# via a /private/tmp symlink, so git's own absolute-path resolution and this
# script's un-resolved ${WT_S8} can legitimately differ by that prefix --
# not a defect, just two correct spellings of the same directory.
if [[ -f "${SKIP_LOG}" ]] \
   && grep -q "state-path: skipping active.yaml -- tracked in git at .*$(basename "${WT_S8}")\$" "${SKIP_LOG}"; then
  pass "S8b: git-tracked skip is logged, names the skipped name and the repo"
else
  fail "S8b" "log_exists=$( [[ -f "${SKIP_LOG}" ]] && echo yes || echo no ) content=$(cat "${SKIP_LOG}" 2>/dev/null || echo '<missing>')"
fi

# ── falsification for S8: prove the git-tracked guard actually matters for a
# name still IN the STANDARD dict. Mutant: production code with the
# `if is_git_tracked(name): continue` guard removed. ───────────────────────
PATCH_S8_PY="${TMP_ROOT}/patch-s8-mutant.py"
cat > "${PATCH_S8_PY}" <<'PYEOF'
import re
import sys
src_path, dst_path = sys.argv[1], sys.argv[2]
src = open(src_path, encoding="utf-8").read()
# Regex, not a literal block match: the git-tracked guard's body (including
# the loud-skip logging added as a follow-up) is prose that will keep
# changing wording -- pin only its structural start/end, `if is_git_tracked
# (name):` through the FIRST bare `continue` at the same 8-space indent that
# directly follows it, whatever sits between.
pattern = re.compile(
    r"    if is_git_tracked\(name\):\n(?:.*\n)*?        continue\n"
)
if not pattern.search(src):
    sys.stderr.write("ERROR: S8 falsification anchor not found -- source drifted from patcher\n")
    sys.exit(1)
mutated = pattern.sub("", src, count=1)
open(dst_path, "w", encoding="utf-8").write(mutated)
PYEOF
MUTANT_S8_SH="${TMP_ROOT}/leadv2-state-path.s8-mutant.sh"
if ! python3 "${PATCH_S8_PY}" "${STATE_PATH_SH}" "${MUTANT_S8_SH}"; then
  echo "ERROR: S8 falsification mutant patch failed to apply"; exit 1
fi
chmod +x "${MUTANT_S8_SH}"

# ── POSITIVE CONTROL on the mutant itself (the most valuable finding of this
# whole round, per Leadmain: a mutant that dies BEFORE reaching the mutated
# line reads as "nothing bad happened" for the exact same reason every
# defect tonight did -- a verdict from a path that never reached the logic
# it claims to test. This bit us for real: the mutant copy landed in
# TMP_ROOT and its own SCRIPT_DIR-relative `source leadv2-portable-lock.sh`
# failed to find a sibling there, so it crashed on line 1 of real work and
# "survived untouched" looked identical to "the guard held". Fixed by
# copying leadv2-portable-lock.sh into TMP_ROOT (see near the top of this
# file) -- this check proves that fix, and any future one, actually holds:
# the mutant must still be ABLE to do a completely ordinary, unrelated
# migration before its result on the git-tracked scenario below is trusted
# at all. ───────────────────────────────────────────────────────────────
POSCTRL_WT="${TMP_ROOT}/s8-posctrl-wt"
POSCTRL_STATE="${TMP_ROOT}/s8-posctrl-state"
mkdir -p "${POSCTRL_WT}/docs/leadv2" "${POSCTRL_STATE}"
printf 'ordinary content\n' > "${POSCTRL_WT}/docs/leadv2/bus.jsonl"
LEADV2_STATE_ROOT="${POSCTRL_STATE}" PROJECT_ROOT="${POSCTRL_WT}" bash "${MUTANT_S8_SH}" bus.jsonl >/dev/null 2>&1
if [[ "$(cat "${POSCTRL_STATE}/bus.jsonl" 2>/dev/null)" == "ordinary content" ]] \
   && [[ -L "${POSCTRL_WT}/docs/leadv2/bus.jsonl" ]]; then
  pass "S8-positive-control: the mutant still executes ordinary migration logic (it did not merely crash silently)"
else
  fail "S8-positive-control" "mutant appears dead on arrival -- its 'survives' result below cannot be trusted. migrated=$(cat "${POSCTRL_STATE}/bus.jsonl" 2>/dev/null || echo '<missing>') is_link=$( [[ -L "${POSCTRL_WT}/docs/leadv2/bus.jsonl" ]] && echo yes || echo no )"
fi

git_tracked_survives() {  # <state-path-bin> -> 0 if active.yaml stays a real healthy file
  local bin="$1"
  local wt="${TMP_ROOT}/s8-falsify-wt-$$-${RANDOM}"
  local state="${TMP_ROOT}/s8-falsify-state-$$-${RANDOM}"
  mkdir -p "${wt}/docs/leadv2" "${state}"
  git -C "${wt}" init -q
  git -C "${wt}" config user.email test@example.com
  git -C "${wt}" config user.name test
  printf 'healthy tracked content\n' > "${wt}/docs/leadv2/active.yaml"
  git -C "${wt}" add docs/leadv2/active.yaml
  git -C "${wt}" commit -q -m tracked
  printf 'STALE\n' > "${state}/active.yaml"
  LEADV2_STATE_ROOT="${state}" PROJECT_ROOT="${wt}" bash "${bin}" bus.jsonl >/dev/null 2>&1
  [[ ! -L "${wt}/docs/leadv2/active.yaml" ]] && [[ "$(cat "${wt}/docs/leadv2/active.yaml" 2>/dev/null)" == "healthy tracked content" ]]
}

git_tracked_survives "${MUTANT_S8_SH}"; s8_pre_rc=$?
git_tracked_survives "${STATE_PATH_SH}"; s8_post_rc=$?
if [[ ${s8_pre_rc} -ne 0 && ${s8_post_rc} -eq 0 ]]; then
  pass "falsification: pre-fix mutant corrupts a git-tracked-by-mistake active.yaml, real resolver leaves it alone"
  echo "RED-then-GREEN: state-path-git-tracked (pre_rc=${s8_pre_rc} -> post_rc=${s8_post_rc})"
else
  fail "S8-falsification" "mutant pre_rc=${s8_pre_rc} (want !=0) real post_rc=${s8_post_rc} (want 0)"
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
