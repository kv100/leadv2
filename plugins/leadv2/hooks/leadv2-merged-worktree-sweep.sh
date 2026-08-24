#!/usr/bin/env bash
# SessionStart hook: remove lane worktrees whose work has already landed.
#
# WHY THIS EXISTS (founder, 2026-08-21): "это проеб плагина, вечно приходится
# то же самое просить тебя делать". Worktrees were created by every dispatch and
# removed by nothing, so they accumulated until the founder noticed his editor
# listing 52 repositories and 2000+ pending changes across them. He then had to ask
# for the same manual cleanup, repeatedly.
#
# The capability already existed and was never wired: leadv2-worktree-cleanup.sh has
# a --sweep-merged mode, and NOTHING called it. The only live caller passes --name at
# phase 8, which reaps a lane that "left nothing behind" — so any lane that produced
# commits (i.e. every lane that did work) survived forever, even after its branch
# merged. Dead code guarding against a problem it was written to solve.
#
# SAFETY (SWEEPER-LANE-SAFETY-01) — a worktree is UNTOUCHABLE while ANY of
#   * registered: its lane id appears in the active session registry
#     (docs/leadv2/active.yaml via the control-plane resolver), any state;
#   * arm-open: docs/handoff/dispatch-<id>/arm-registered exists with no TRUE
#     terminal (landed|dead) row in the dispatch ledger;
#   * live: a registered pid for the lane is alive;
#   * young: the worktree dir is younger than LEADV2_SWEEP_MIN_AGE_H (48h);
# holds — enforced by scripts/lib/leadv2-worktree-protected.sh BEFORE any
# other criterion, fail-closed on any read error (nothing is swept when the
# control plane cannot be read). "Merged and clean" is not sufficient: a lane
# legitimately sits at base before its first commit and between fix rounds —
# incidents b413968c (lane gutted to a lone docs/ dir by the discard that ran
# before the removal decision) and 43ae4318 (lane deleted entirely by
# --sweep-dead before its worker committed).
#
# Only when NONE of the four holds is the tree a sweep candidate, and then
# additionally:
#   * its branch is fully merged into the default branch, so the commits live on.
#   * it is a lane worktree under .claude/worktrees/, never a hand-made checkout.
#   * its only dirt is the plugin's own regenerated bookkeeping (see the
#     orchestration-dirt exclusion below) — genuine uncommitted work always wins.
# The branch itself is NOT deleted: `worktree remove` drops the checkout only, so
# even a misjudgement costs a `git worktree add`, never a commit.
#
# Advisory by default about what it could NOT remove — a lane holding unmerged work
# is reported, never touched, because that is exactly where a founder deliverable
# hides. Today's sweep found a 150-line sample-generation script in one such tree.
#
# Kill switch: LEADV2_MERGED_WORKTREE_SWEEP=0.

set -uo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

[[ "${LEADV2_MERGED_WORKTREE_SWEEP:-1}" == "0" ]] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "${ROOT}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Default branch: main if it exists, else whatever HEAD points at.
BASE="main"
git rev-parse --verify --quiet "${BASE}" >/dev/null 2>&1 || \
  BASE="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

REMOVED=0
KEPT_DIRTY=0
KEPT_AHEAD=0
KEPT_YOUNG=0
declare -a KEPT_NAMES=()

# SWEEPER-LANE-SAFETY-01: the shared lane-protection gate (one inode, both
# unattended sweepers). Missing lib => stub returns rc 5 for every worktree:
# an install that lost the lib sweeps NOTHING rather than sweeping blind.
# "Standalone at SessionStart" means no dependency on REPO state, not on
# plugin files — the lib lives in this plugin tree, next to the hook.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../scripts/lib/leadv2-worktree-protected.sh" ]]; then
  # shellcheck source=leadv2-worktree-protected.sh
  source "${SCRIPT_DIR}/../scripts/lib/leadv2-worktree-protected.sh"
else
  lv2_wt_protect_prime() { :; }
  lv2_worktree_protected() { LV2_WT_PROTECT_REASON="lib-missing"; return 5; }
fi
JOURNAL_BIN="${SCRIPT_DIR}/../scripts/leadv2-journal.sh"
# The durable task journals live in the MAIN checkout — a SessionStart can
# fire inside a lane worktree, and a journal written there dies with the tree.
COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || printf '%s' "${ROOT}/.git")"
JOURNAL_ROOT="$(dirname "${COMMON_DIR}")"
_PROTECT_ERR_SHOWN=0

lv2_wt_protect_prime "${ROOT}"

# Only lane worktrees, and only ones that still exist on disk.
while IFS= read -r wt; do
  [[ -n "${wt}" ]] || continue
  case "${wt}" in
    */.claude/worktrees/*) ;;
    *) continue ;;
  esac
  [[ -d "${wt}" ]] || continue

  # SWEEPER-LANE-SAFETY-01: protection BEFORE any other criterion. rc 1-4
  # (registered / arm-open / live pid / young) skip SILENTLY apart from one
  # /tmp/leadv2-sweep.log line — a protected lane is the steady state, not a
  # per-turn event. rc 5 is fail-closed: one stderr line per pass, and this
  # worktree survives to be re-probed next session.
  if lv2_worktree_protected "${ROOT}" "${wt}"; then
    :
  else
    prc=$?
    printf '%s|merged-worktree-sweep|protected id=%s rc=%d reason=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(basename "${wt}")" "${prc}" \
      "${LV2_WT_PROTECT_REASON:-?}" >> /tmp/leadv2-sweep.log 2>/dev/null || true
    if [[ "${prc}" == "5" && "${_PROTECT_ERR_SHOWN}" == "0" ]]; then
      printf '[leadv2-merged-worktree-sweep] protected(read-error) %s — sweeping nothing this pass (%s)\n' \
        "$(basename "${wt}")" "${LV2_WT_PROTECT_REASON:-unreadable}" >&2
      _PROTECT_ERR_SHOWN=1
    fi
    continue
  fi

  # Unmerged work stays, and is named so a human can decide.
  ahead="$(git -C "${wt}" rev-list --count "${BASE}..HEAD" 2>/dev/null || echo 0)"
  if [[ "${ahead}" != "0" ]]; then
    KEPT_AHEAD=$((KEPT_AHEAD + 1)); KEPT_NAMES+=("$(basename "${wt}") (+${ahead})")
    continue
  fi

  # NEWBORN GUARD (2026-08-24): a worktree `git worktree add` just created is
  # ALSO ahead=0 -- leadv2-dispatch-code.sh creates the lane worktree, then
  # spawns the child session, whose own SessionStart hooks (this one
  # included) run before the child has written a single byte. `ahead=0`
  # cannot tell "already merged, safe to reap" apart from "about to be
  # used" -- the two are byte-for-byte identical git state. Reproduced 2/2
  # on 2026-08-24 (tasks e5be9e72, 77ea471a): the hook deleted the directory
  # the child was about to work in, ~7s after creation.
  #
  # Age is derived from `<common-git-dir>/worktrees/<name>/gitdir`, a file
  # `git worktree add` writes exactly ONCE at creation and never rewrites
  # afterward -- unlike HEAD/index/logs living in that same per-worktree
  # metadata dir, which change on every commit or even a `git status` run
  # inside the worktree. Verified empirically: running `status` then
  # `commit` inside a fresh worktree left `gitdir`'s mtime untouched, so it
  # is creation-stamped, not access-stamped -- exactly what an age guard
  # needs. `git rev-parse --git-dir` run FROM the worktree resolves straight
  # to that metadata dir for a linked worktree (not the common .git).
  min_age="${LEADV2_SWEEP_MIN_AGE_S:-1800}"
  meta_dir="$(git -C "${wt}" rev-parse --git-dir 2>/dev/null)"
  gitdir_file="${meta_dir:-}/gitdir"
  if [[ -n "${meta_dir}" && -f "${gitdir_file}" ]]; then
    created_epoch="$(stat -f '%m' "${gitdir_file}" 2>/dev/null || stat -c '%Y' "${gitdir_file}" 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    if [[ "${created_epoch}" =~ ^[0-9]+$ ]] && (( created_epoch > 0 )); then
      age=$(( now_epoch - created_epoch ))
      if (( age < min_age )); then
        KEPT_YOUNG=$((KEPT_YOUNG + 1)); KEPT_NAMES+=("$(basename "${wt}") (young ${age}s)")
        continue
      fi
    fi
  fi

  # ORCHESTRATION DIRT (2026-08-22): every merged lane carries edits to the
  # orchestration files the plugin itself writes -- docs/leadv2/, docs/handoff/,
  # LEAD_V2_STATE.md, __pycache__ -- so "any dirt keeps the lane" meant NO lane was
  # ever swept. Found live: 641321b5 was merged (ahead=0) with a single modified
  # file, docs/leadv2/open-threads.md, and would have sat there forever. The same
  # exclusion set already exists in leadv2-dispatch-product-close.sh; it is repeated
  # here rather than sourced because this hook must run standalone at SessionStart,
  # and the twin is asserted by test-merged-sweep-orchestration-dirt.sh so the two
  # cannot drift apart silently the way the scope gate's two copies did.
  _MW_ORCH_RE='^.. "?docs/leadv2/|^.. "?docs/handoff/|^.. "?docs/LEAD_V2_STATE\.md|^.. "?.*__pycache__/|^.. "?.*\.pyc$'
  # `|| true`: grep exits 1 when NOTHING survives the exclusion — i.e. exactly the
  # clean case we want to sweep — and under `set -o pipefail` with an ERR trap that
  # non-zero killed the whole hook at this line. The failure mode was invisible: the
  # hook exited 0 (the trap says so) having swept nothing.
  real_dirt="$(git -C "${wt}" status --porcelain 2>/dev/null | grep -vE "${_MW_ORCH_RE}" | head -1 || true)"

  if [[ -n "${real_dirt}" ]]; then
    # Genuine uncommitted work always wins. Never --force from here.
    KEPT_DIRTY=$((KEPT_DIRTY + 1)); KEPT_NAMES+=("$(basename "${wt}") (dirty)")
    continue
  fi

  # Merged, protected-none, and nothing dirty but the plugin's own regenerated
  # bookkeeping. `worktree remove --force` discards exactly that bookkeeping
  # and removes the tree in ONE atomic git operation. The old two-step
  # (checkout --/rm -f the orchestration paths, THEN attempt removal) mutated
  # the tree BEFORE the removal decision was made, and any removal refusal
  # left a gutted husk behind — incident b413968c, a lane reduced to a single
  # docs/ dir. A refused removal now leaves the tree byte-identical. --force
  # here is safe for the same reason the explicit discard was: every gate
  # above (protection, ahead, real-dirt) has already said "removable", so the
  # only thing being forced past is the regenerated bookkeeping itself.
  if git worktree remove --force "${wt}" >/dev/null 2>&1; then
    REMOVED=$((REMOVED + 1))
    # Every actual sweep journals why (design deliverable 2: both prior
    # incidents had to be diagnosed forensically). Journal failure never
    # aborts the sweep, and never undoes a removal git already performed.
    _id="$(basename "${wt}")"
    if [[ -f "${JOURNAL_BIN}" ]]; then
      CLAUDE_PROJECT_ROOT="${JOURNAL_ROOT}" bash "${JOURNAL_BIN}" append "${_id}" note \
        "worktree_swept id=${_id} reason=merged-clean" >/dev/null 2>&1 || true
    fi
  else
    KEPT_DIRTY=$((KEPT_DIRTY + 1)); KEPT_NAMES+=("$(basename "${wt}") (dirty)")
  fi
done < <(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')

git worktree prune >/dev/null 2>&1 || true

if (( REMOVED > 0 || KEPT_AHEAD > 0 || KEPT_DIRTY > 0 || KEPT_YOUNG > 0 )); then
  printf '[leadv2-merged-worktree-sweep] removed %d merged lane worktree(s)' "${REMOVED}" >&2
  if (( KEPT_AHEAD > 0 || KEPT_DIRTY > 0 || KEPT_YOUNG > 0 )); then
    printf '; kept %d with unmerged commits, %d dirty, %d too young (<%ss): %s' \
      "${KEPT_AHEAD}" "${KEPT_DIRTY}" "${KEPT_YOUNG}" "${min_age:-1800}" "${KEPT_NAMES[*]}" >&2
  fi
  printf '\n' >&2
fi

exit 0
