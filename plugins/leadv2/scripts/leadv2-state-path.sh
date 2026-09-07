#!/usr/bin/env bash
# scripts/leadv2-state-path.sh — LEAD-CONTROL-PLANE-01 canonical path resolver.
#
# THE BUG this fixes: every /leadv2 coordination file (active.yaml, bus.jsonl,
# merge-queue.jsonl, .merge.lock, open-threads.md) used to live at a
# REPO-RELATIVE path (docs/leadv2/...). But every /leadv2 session runs in its
# OWN `git worktree add` checkout — so each of N parallel sessions got its own
# PRIVATE copy of every "shared" coordination file. The merge lock locked
# nothing. The bus connected no one. All N sessions still raced the same
# `main`.
#
# THE FIX: resolve one canonical root OUTSIDE any worktree, via
# `git rev-parse --path-format=absolute --git-common-dir` — this path is
# IDENTICAL from every worktree of the same repo (unlike `--git-dir`, which
# is worktree-private: <repo>/.git for the main tree,
# <repo>/.git/worktrees/<name> for a linked one). Root:
#   ~/.claude/leadv2-state/<repo-slug>/
# where <repo-slug> = basename of the MAIN repo's toplevel dir (derived from
# git-common-dir, never from the calling worktree's own path).
#
# ALL scripts/hooks that touch any of the names below MUST resolve the path
# through this script — no hardcoded `docs/leadv2/...` string for a managed
# name anywhere else. LANE-STATE-LEAK-01 extended the original five to the
# full managed set, grouped by migration class:
#   STANDARD — opaque single-writer state: active.yaml, active.yaml.lock,
#     bus.jsonl, .bus.lock, .bus-offsets/, merge-queue.jsonl, .merge.lock,
#     open-threads.md, questions/, .codex-credits-empty.stamp. On a
#     first-worktree-wins collision the local copy is preserved as
#     <name>.pre-controlplane-backup (S7).
#   RENDER — regenerable, no history worth keeping: founder-status.md,
#     founder-status-full.md, .board-empty-since, .founder-status-epoch. On
#     collision the local copy is DELETED, no backup (S6) — the next beat
#     rewrites it, and a backup file here would just be new untracked noise.
#     The docs/leadv2/<name> symlink is a CONTRACT for this class, not a
#     convenience: leadv2-single-lead-beat.sh and two test suites open these
#     paths directly rather than through this resolver.
#   MERGE (file) — glm-deferred.jsonl: on collision the local file's lines
#     are unioned into the target textually (never JSON-parsed, so one
#     malformed line can't abort migration), deduped by exact line equality,
#     then the local file is removed.
#   MERGE (dir) — glm-deferred.d/: on collision each local entry is moved
#     into the target only if absent there (content-derived sig8 filenames
#     make a same-name collision the same task); the target's own entry
#     always wins.
#   GLOB — .arm-exceptions-<day> and its .lock siblings: move-if-absent into
#     the control plane, no symlink (the caller always re-resolves the exact
#     dated name through this script).
#
# Usage:
#   leadv2-state-path.sh --project-root  # owning worktree root only; no writes
#   leadv2-state-path.sh                  # -> control-plane root, ensures it
#                                            exists + repairs the standard
#                                            docs/leadv2/<name> symlink set
#                                            for the CURRENT worktree
#   leadv2-state-path.sh root             # same as above
#   leadv2-state-path.sh <name>           # -> <root>/<name> (nested names,
#                                            e.g. .bus-offsets/<session>,
#                                            questions/<id>.yaml, are NOT
#                                            symlinked individually — only
#                                            their parent dir is)
#   leadv2-state-path.sh --no-link <name> # resolve only, skip the symlink /
#                                            migration side effect (used by
#                                            the test harness to probe raw
#                                            paths without mutating a worktree)
#
# GIT-TRACKED-NEVER-MIGRATES (OPEN-THREADS-TRUNCATED-SIX-TIMES-IN-ONE-NIGHT-01,
# 2026-09-07): before touching any STANDARD name, the migration below checks
# `git ls-files --error-unmatch docs/leadv2/<name>` in LINK_ROOT and skips the
# name entirely if it is tracked. A path git tracks belongs to the repo, not
# the control plane -- letting it be migrated/symlinked meant a stale
# control-plane snapshot from hours earlier could silently replace a
# freshly git-restored, healthy file the next time ANY of 12+ unrelated
# call sites invoked this resolver for a completely different name. Hard
# authority check (tracked or not), not an mtime/size heuristic.
#
# Migration semantics (idempotent, safe to call from every worktree, every
# invocation): for each name in the standard set, if the control-plane copy
# does not exist yet AND a REAL file/dir (not a symlink) is sitting at
# docs/leadv2/<name> in THIS worktree, its content is MOVED into the control
# plane (never dropped) and replaced with a symlink. If the control-plane
# copy already exists (another worktree migrated first) and this worktree
# also has independent real content, the local copy is preserved as
# `<name>.pre-controlplane-backup` before the symlink is created — nothing is
# ever silently overwritten.
#
# Env overrides (test sandboxing):
#   LEADV2_STATE_ROOT   — full absolute override of the control-plane root
#                         (skips git/slug resolution entirely)
#   LEADV2_STATE_BASE   — override the base dir (default ~/.claude/leadv2-state)
#   PROJECT_ROOT        — repo root override (for the symlink step only;
#                         defaults to `git rev-parse --show-toplevel` of cwd)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=leadv2-portable-lock.sh
source "${SCRIPT_DIR}/leadv2-portable-lock.sh"

NO_LINK=0
if [[ "${1:-}" == "--no-link" ]]; then
  NO_LINK=1
  shift
fi
NAME="${1:-root}"

# LINK_ROOT is the worktree this invocation cares about — an explicit
# PROJECT_ROOT override (test sandboxes, callers that already know their
# root) always wins; otherwise fall back to this invocation's own cwd
# toplevel. git-common-dir MUST be resolved AGAINST LINK_ROOT, never against
# the ambient `git rev-parse` cwd — resolving from cwd silently pointed every
# caller (including test sandboxes with no .git at all) at whichever repo
# happened to be the current shell's cwd, which is wrong for any caller that
# passes an explicit PROJECT_ROOT belonging to a different tree.
LINK_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# SHADOW-CONTROL-PLANE-01: callers such as status-collector pass their cwd
# as PROJECT_ROOT. Resolve that location to its owning worktree before
# migration creates docs/leadv2; git-common-dir alone fixes STATE_ROOT but
# leaves the compatibility links under scripts/. Keep explicit non-git
# sandbox roots intact, and never switch to the plugin's own repository.
LINK_ROOT="$(git -C "$LINK_ROOT" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$LINK_ROOT")"
if [[ "$NAME" == "--project-root" ]]; then
  printf '%s\n' "$LINK_ROOT"
  exit 0
fi

# ── Resolve control-plane root ──────────────────────────────────────────────
if [[ -n "${LEADV2_STATE_ROOT:-}" ]]; then
  STATE_ROOT="$LEADV2_STATE_ROOT"
else
  COMMON_DIR="$(git -C "$LINK_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -z "$COMMON_DIR" ]]; then
    # LINK_ROOT is not inside a git repo at all (e.g. a test sandbox that
    # never ran `git init`) — degrade to the pre-fix repo-relative layout
    # for THIS root only. This never silently borrows the real control
    # plane of an unrelated repo just because it happens to be the caller's
    # ambient cwd.
    STATE_ROOT="${LINK_ROOT}/docs/leadv2"
    # SWIFTBAR-LIVE-01: a caller with no cwd-derived repo (LINK_ROOT resolves to
    # "/" — e.g. SwiftBar launching this script with cwd=/ and no PROJECT_ROOT)
    # used to `mkdir -p //docs/leadv2`, which either crashes under a caller's
    # `set -e` or half-creates a stray root-owned dir. Refuse instead of
    # guessing: no mkdir, one-line stderr diagnostic, exit 3.
    if [[ "$LINK_ROOT" == "/" ]]; then
      printf -- '[leadv2-state-path] ABORT: no git repo resolved and LINK_ROOT is "/" (cwd=/, no PROJECT_ROOT) -- refusing to mkdir "%s". Pass PROJECT_ROOT or run from inside a repo checkout.\n' "$STATE_ROOT" >&2
      exit 3
    fi
    if ! mkdir -p "$STATE_ROOT" 2>/dev/null; then
      printf -- '[leadv2-state-path] ABORT: parent of "%s" is not writable -- refusing to proceed.\n' "$STATE_ROOT" >&2
      exit 3
    fi
    if [[ "$NAME" == "root" || -z "$NAME" ]]; then
      printf -- '%s\n' "$STATE_ROOT"
      exit 0
    fi
    TARGET="${STATE_ROOT}/${NAME}"
    mkdir -p "$(dirname "$TARGET")"
    printf -- '%s\n' "$TARGET"
    exit 0
  fi
  MAIN_REPO_ROOT="$(cd "$(dirname "$COMMON_DIR")" && pwd)"
  REPO_SLUG="$(basename "$MAIN_REPO_ROOT")"

  # ── EPHEMERAL-REDIRECT (STATE-DIR-JUNK-01) ───────────────────────────────
  # Production never sets LEADV2_STATE_ROOT or LEADV2_STATE_BASE (see the B1
  # SAFETY NET below, which relies on the same fact). When NEITHER is set AND
  # MAIN_REPO_ROOT is a scratch repo -- no git remote, no REAL-REPO /
  # .git/leadv2-real-repo-marker (the exact predicate the B1 net already uses
  # to tell a real checkout from a fixture) -- redirect under
  # <base>/.ephemeral/<slug> instead of the top level. This is the unguarded
  # direction the B1 net doesn't cover: no sandbox signal + scratch repo used
  # to mean "write straight into production" -- ~100 `leadv2-lwt.*` dirs from
  # test-lane-writes-scoping.sh alone, one per run, never cleaned up. The
  # renderer (leadv2-status-projects.sh) globs "$BASE"/*/ with no dotglob, so
  # a dot-prefixed subtree is already invisible to it -- no renderer change
  # needed.
  STATE_BASE="${LEADV2_STATE_BASE:-${HOME}/.claude/leadv2-state}"
  if [[ -z "${LEADV2_STATE_ROOT:-}" && -z "${LEADV2_STATE_BASE:-}" ]] \
     && ! { git -C "$MAIN_REPO_ROOT" remote 2>/dev/null | grep -q .; } \
     && [[ ! -f "$MAIN_REPO_ROOT/REAL-REPO" && ! -f "$MAIN_REPO_ROOT/.git/leadv2-real-repo-marker" ]]; then
    STATE_ROOT="${STATE_BASE}/.ephemeral/${REPO_SLUG}"
    mkdir -p "$STATE_ROOT"
    _eph_marker="${STATE_ROOT}/.ephemeral"
    if [[ ! -f "$_eph_marker" ]]; then
      printf -- 'source=%s\ncreated=%s\n' "$MAIN_REPO_ROOT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${_eph_marker}.tmp.$$" 2>/dev/null \
        && mv -f "${_eph_marker}.tmp.$$" "$_eph_marker" 2>/dev/null || rm -f "${_eph_marker}.tmp.$$" 2>/dev/null || true
    fi
    unset _eph_marker
  else
    STATE_ROOT="${STATE_BASE}/${REPO_SLUG}"
  fi
fi

mkdir -p "$STATE_ROOT"

# SWIFTBAR-LIVE-01: a marker recording which real repo checkout this
# control-plane root belongs to, so a cwd-independent reader (leadv2-status-
# projects.sh) can enumerate every project under LEADV2_STATE_BASE without
# ever calling git or depending on the caller's cwd. Additive, atomic,
# write-only-on-change (avoid mtime churn on every invocation). Only written
# when MAIN_REPO_ROOT is known (the git branch above) -- the no-git fallback
# returns early and never reaches here.
if [[ -n "${MAIN_REPO_ROOT:-}" ]]; then
  _repo_root_marker="${STATE_ROOT}/.repo-root"
  _cur_marker=""
  [[ -f "$_repo_root_marker" ]] && _cur_marker="$(cat "$_repo_root_marker" 2>/dev/null || true)"
  if [[ "$_cur_marker" != "$MAIN_REPO_ROOT" ]]; then
    _repo_root_tmp="${_repo_root_marker}.tmp.$$"
    if printf -- '%s' "$MAIN_REPO_ROOT" > "$_repo_root_tmp" 2>/dev/null; then
      mv -f "$_repo_root_tmp" "$_repo_root_marker" 2>/dev/null || rm -f "$_repo_root_tmp"
    fi
  fi
  unset _repo_root_marker _cur_marker _repo_root_tmp
fi

# ── B1 SAFETY NET (SUPERVISOR-AUDIT-01, third recurrence, fix-round-3) ─────
# Twice before, a test that sandboxes the control plane via LEADV2_STATE_ROOT
# still forgot to ALSO thread PROJECT_ROOT/LEADV2_PROJECT_ROOT/CLAUDE_PROJECT_DIR
# for one specific call; that call's LINK_ROOT then fell back to `git
# rev-parse --show-toplevel` of the CALLING PROCESS'S cwd — the real repo the
# test happened to be invoked from — and the symlink-repair block below
# retargeted that real repo's docs/leadv2/* control-plane links at a
# throwaway tmp dir. Root-cause every individual missing-override call site
# is a losing game (this is the third recurrence); this script is the one
# chokepoint EVERY such call passes through, so the safety net belongs here.
#
# LEADV2_STATE_ROOT is a sandbox-only signal: production NEVER sets it (a
# real /leadv2 session always resolves STATE_ROOT via git-common-dir above).
# A real leadv2/persona-engine/m3-market/respiro-ios checkout always carries
# a configured git remote; a scratch `git init` fixture never does (same
# signal leadv2-temp.sh's lv2_assert_scratch_repo already uses test-side).
# If a caller set LEADV2_STATE_ROOT (declaring "sandbox this") but LINK_ROOT
# nonetheless resolves to a real checkout, that is exactly the contradiction
# that produced the retarget: hard-abort instead of silently mutating it.
if [[ "$NO_LINK" -eq 0 && -n "${LEADV2_STATE_ROOT:-}" ]]; then
  if git -C "$LINK_ROOT" remote 2>/dev/null | grep -q . \
     || [[ -f "$LINK_ROOT/REAL-REPO" || -f "$LINK_ROOT/.git/leadv2-real-repo-marker" ]]; then
    printf -- '[leadv2-state-path] ABORT: LEADV2_STATE_ROOT is set (a sandbox-only signal — production never sets this) but the resolved LINK_ROOT (%s) is a real repo checkout (has a git remote or a REAL-REPO marker). This means PROJECT_ROOT/LEADV2_PROJECT_ROOT/CLAUDE_PROJECT_DIR was not threaded to THIS specific call, so LINK_ROOT fell back to cwd. Refusing to touch its docs/leadv2/* control-plane symlinks — fix the caller to pass PROJECT_ROOT explicitly; never mutate a real checkout from a sandboxed test.\n' "$LINK_ROOT" >&2
    exit 1
  fi
fi

# ── Orphan-root reconciliation (QUESTION-CHANNEL-DEAD-01) ──────────────────
# A prior control-plane root has been observed at "${COMMON_DIR}/leadv2-state"
# (i.e. INSIDE .git, not under ~/.claude/leadv2-state/<slug>) holding real
# question files (e.g. active.yaml, questions/*.yaml) that this resolver's
# canonical STATE_ROOT never reads -- a silent, undelivered-forever question
# looks identical to "nobody asked". The exact caller that produced that root
# was never pinned down (no code path in this script or its known callers
# computes it), so treat it as a standing hazard rather than a one-off: on
# every resolution, if that path exists and differs from STATE_ROOT, absorb
# any file not already present in STATE_ROOT (never clobber existing
# content) and warn loudly so a future orphan is visible instead of silent.
if [[ -n "${COMMON_DIR:-}" ]]; then
  ORPHAN_ROOT="${COMMON_DIR}/leadv2-state"
  if [[ -d "$ORPHAN_ROOT" && "$ORPHAN_ROOT" != "$STATE_ROOT" ]]; then
    python3 - "$ORPHAN_ROOT" "$STATE_ROOT" <<'PYEOF' || true
import os, shutil, sys

orphan_root, state_root = sys.argv[1], sys.argv[2]
for dirpath, dirnames, filenames in os.walk(orphan_root):
    rel = os.path.relpath(dirpath, orphan_root)
    dst_dir = state_root if rel == "." else os.path.join(state_root, rel)
    os.makedirs(dst_dir, exist_ok=True)
    for fn in filenames:
        if fn.startswith(".") and fn.endswith(".lock"):
            continue
        src = os.path.join(dirpath, fn)
        dst = os.path.join(dst_dir, fn)
        if os.path.exists(dst):
            continue
        try:
            shutil.move(src, dst)
            sys.stderr.write(
                "[leadv2-state-path] absorbed orphaned control-plane file: "
                "%s -> %s\n" % (src, dst)
            )
        except OSError:
            continue
PYEOF
  fi
fi

# ── Migration + symlink repair (idempotent, best-effort, never fatal) ──────
# LANE-STATE-LEAK-01 §2.3: the MERGE classes below are read-modify-write across
# processes -- two worktrees migrating concurrently could both read the target,
# both append, and one loses its lines. Guard the whole block with a
# non-blocking, short-timeout advisory lock. fd 7 is used deliberately:
# dispatch-code.sh already reserves fd 9 (dispatch lock, closed before a
# detached spawn) and fd 8 (GLM-ladder sidecar lock) in the process tree this
# resolver is called from (`grep -n '7[<>]' plugins/leadv2/scripts/*.sh` is
# empty). On lock timeout: skip migration for this invocation and still print
# the resolved path -- this resolver must never become a place a dispatch can
# hang.
if [[ "$NO_LINK" -eq 0 ]]; then
  MIGRATE_LOCK="${STATE_ROOT}/.state-path-migrate.lock"
  _migrate_locked=0
  if command -v flock >/dev/null 2>&1; then
    if exec 7>"${MIGRATE_LOCK}" 2>/dev/null && flock -w 5 -x 7 2>/dev/null; then
      _migrate_locked=1
    fi
  else
    _mdir="${MIGRATE_LOCK}.d"
    _mstart="$(date +%s 2>/dev/null || printf 0)"
    _mdeadline=$(( _mstart + 5 ))
    while true; do
      if mkdir "${_mdir}" 2>/dev/null; then
        printf '%s' "$$" > "${_mdir}/pid" 2>/dev/null || true
        _migrate_locked=1
        break
      fi
      _mnow="$(date +%s 2>/dev/null || printf 0)"
      [[ ${_mnow} -ge ${_mdeadline} ]] && break
      sleep 0.2 2>/dev/null || sleep 1
    done
  fi

  if [[ "${_migrate_locked}" -eq 1 ]]; then
    python3 - "$STATE_ROOT" "$LINK_ROOT" <<'PYEOF' 2>/dev/null || true
import os, re, shutil, subprocess, sys

state_root, link_root = sys.argv[1], sys.argv[2]
leadv2_dir = os.path.join(link_root, "docs", "leadv2")
os.makedirs(leadv2_dir, exist_ok=True)


def is_git_tracked(name):
    # OPEN-THREADS-TRUNCATED-SIX-TIMES-IN-ONE-NIGHT-01: a path git tracks
    # belongs to the repo, never to the control plane. This is a hard
    # authority check (git tracks it or it doesn't), not an mtime/size
    # heuristic -- a heuristic still has to pick a winner when both sides
    # look plausible, and picking wrong is exactly how a git-restored,
    # healthy `docs/leadv2/open-threads.md` got silently backed up and
    # replaced by a symlink to a 9-hour-stale control-plane snapshot: the
    # STANDARD migration below ran on every unrelated resolver call (12+
    # call sites), found the old snapshot already present, and treated that
    # as "another worktree already migrated" instead of "this file is under
    # version control and isn't the control plane's to move." Skipping
    # migration/symlinking outright for anything git tracks removes the
    # question instead of answering it.
    rel = os.path.join("docs", "leadv2", name)
    try:
        r = subprocess.run(
            ["git", "-C", link_root, "ls-files", "--error-unmatch", rel],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return r.returncode == 0
    except OSError:
        return False

MERGE_SIZE_CAP = 8 * 1024 * 1024  # §3.4: never load an unbounded ladder into memory

# name -> is_dir. Opaque single-writer state: first-worktree-wins, collision
# preserved as <name>.pre-controlplane-backup.
STANDARD = {
    "active.yaml": False,
    "active.yaml.lock": False,
    "bus.jsonl": False,
    ".bus.lock": False,
    ".bus-offsets": True,
    "merge-queue.jsonl": False,
    ".merge.lock": False,
    "open-threads.md": False,
    "questions": True,
    ".codex-credits-empty.stamp": False,
}

# Regenerable renders: on collision the local copy is deleted outright (no
# backup) -- a stale 30-minute-old render is not worth a permanently-untracked
# .pre-controlplane-backup file, and the next beat rewrites it anyway.
RENDER = {
    "founder-status.md": False,
    "founder-status-full.md": False,
    ".board-empty-since": False,
    ".founder-status-epoch": False,
}

# Text-line-union merge on collision (never JSON-parsed -- one malformed line
# must not abort the whole migration loop).
MERGE_FILE = {"glm-deferred.jsonl"}

# Per-entry move-if-absent merge on collision (sig8 filenames are
# content-derived, so a same-name collision is the same task; target wins).
MERGE_DIR = {"glm-deferred.d"}


def relink_if_needed(local, target):
    try:
        cur = os.readlink(local)
    except OSError:
        cur = None
    if cur != target:
        try:
            os.unlink(local)
            os.symlink(target, local)
        except OSError:
            pass


for name, is_dir in STANDARD.items():
    target = os.path.join(state_root, name)
    local = os.path.join(leadv2_dir, name)

    if is_git_tracked(name):
        continue

    if os.path.islink(local):
        relink_if_needed(local, target)
        continue

    if os.path.exists(local):
        # Real (non-symlink) content sitting at the old repo-relative path.
        if not os.path.exists(target):
            # First migration: move content into the control plane verbatim.
            try:
                shutil.move(local, target)
            except OSError:
                continue
        else:
            # Control plane already has content (another worktree migrated
            # first) — never clobber; preserve this worktree's local copy.
            backup = local + ".pre-controlplane-backup"
            if not os.path.exists(backup):
                try:
                    shutil.move(local, backup)
                except OSError:
                    continue
            else:
                continue

    if not os.path.exists(local):
        if is_dir:
            os.makedirs(target, exist_ok=True)
        try:
            os.symlink(target, local)
        except FileExistsError:
            pass
        except OSError:
            pass

for name in RENDER:
    target = os.path.join(state_root, name)
    local = os.path.join(leadv2_dir, name)

    if os.path.islink(local):
        relink_if_needed(local, target)
        continue

    if os.path.exists(local):
        if not os.path.exists(target):
            try:
                shutil.move(local, target)
            except OSError:
                continue
        else:
            # S6: regenerable -- delete local outright, no backup.
            try:
                if os.path.isdir(local):
                    shutil.rmtree(local, ignore_errors=True)
                else:
                    os.remove(local)
            except OSError:
                continue

    if not os.path.exists(local):
        try:
            os.symlink(target, local)
        except FileExistsError:
            pass
        except OSError:
            pass

for name in MERGE_FILE:
    target = os.path.join(state_root, name)
    local = os.path.join(leadv2_dir, name)

    if os.path.islink(local):
        relink_if_needed(local, target)
        continue

    if os.path.exists(local):
        if not os.path.exists(target):
            try:
                shutil.move(local, target)
            except OSError:
                continue
        else:
            try:
                local_size = os.path.getsize(local)
            except OSError:
                local_size = 0
            if local_size > MERGE_SIZE_CAP:
                sys.stderr.write(
                    "[leadv2-state-path] %s exceeds merge size cap (%d bytes) -- "
                    "left un-migrated this invocation\n" % (local, local_size)
                )
                continue
            try:
                with open(target, "r", encoding="utf-8", errors="replace") as fh:
                    existing_lines = set(line.rstrip("\n") for line in fh)
            except OSError:
                existing_lines = set()
            try:
                with open(local, "r", encoding="utf-8", errors="replace") as fh:
                    local_lines = [line.rstrip("\n") for line in fh]
            except OSError:
                local_lines = []
            new_lines = [ln for ln in local_lines if ln and ln not in existing_lines]
            try:
                if new_lines:
                    with open(target, "a", encoding="utf-8") as fh:
                        for ln in new_lines:
                            fh.write(ln + "\n")
                os.remove(local)
            except OSError:
                continue

    if not os.path.exists(local):
        try:
            os.symlink(target, local)
        except FileExistsError:
            pass
        except OSError:
            pass

for name in MERGE_DIR:
    target = os.path.join(state_root, name)
    local = os.path.join(leadv2_dir, name)

    if os.path.islink(local):
        relink_if_needed(local, target)
        continue

    if os.path.isdir(local):
        os.makedirs(target, exist_ok=True)
        for entry in os.listdir(local):
            src = os.path.join(local, entry)
            dst = os.path.join(target, entry)
            if os.path.exists(dst):
                # Content-derived name already present in the target -- same
                # task, target wins; drop the local duplicate.
                try:
                    if os.path.isdir(src) and not os.path.islink(src):
                        shutil.rmtree(src, ignore_errors=True)
                    else:
                        os.remove(src)
                except OSError:
                    pass
                continue
            try:
                shutil.move(src, dst)
            except OSError:
                continue
        try:
            if not os.listdir(local):
                os.rmdir(local)
        except OSError:
            pass

    if not os.path.exists(local):
        if not os.path.exists(target):
            os.makedirs(target, exist_ok=True)
        try:
            os.symlink(target, local)
        except FileExistsError:
            pass
        except OSError:
            pass

# GLOB class: .arm-exceptions-<day> and its .lock siblings. No symlink -- the
# caller always re-resolves the exact dated name through this script, so
# nothing needs to point at a stable local path. Collision (target already
# exists) is left alone: these files are gitignored regardless, so an
# un-migrated leftover is not visible worktree noise (S9).
glob_re = re.compile(r"^\.arm-exceptions-\d{8}(\.lock)?$")
try:
    entries = os.listdir(leadv2_dir)
except OSError:
    entries = []
for entry in entries:
    if not glob_re.match(entry):
        continue
    local = os.path.join(leadv2_dir, entry)
    if os.path.islink(local):
        continue
    target = os.path.join(state_root, entry)
    if os.path.exists(target):
        continue
    try:
        shutil.move(local, target)
    except OSError:
        continue
PYEOF
    if command -v flock >/dev/null 2>&1; then
      exec 7>&- 2>/dev/null || true
    else
      rm -rf "${_mdir}" 2>/dev/null || true
    fi
  else
    printf -- '[leadv2-state-path] WARN: migration lock busy after 5s -- skipping migration this invocation (path still resolved).\n' >&2
  fi
  unset _migrate_locked _mdir _mstart _mdeadline _mnow
fi

if [[ "$NAME" == "root" || -z "$NAME" ]]; then
  printf -- '%s\n' "$STATE_ROOT"
  exit 0
fi

TARGET="${STATE_ROOT}/${NAME}"
mkdir -p "$(dirname "$TARGET")"
printf -- '%s\n' "$TARGET"
