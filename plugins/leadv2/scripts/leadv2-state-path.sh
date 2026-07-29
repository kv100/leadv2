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
# ALL scripts/hooks that touch active.yaml / bus.jsonl / merge-queue.jsonl /
# .merge.lock / open-threads.md MUST resolve the path through this script —
# no hardcoded `docs/leadv2/...` string for these five files anywhere else.
#
# Usage:
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
    mkdir -p "$STATE_ROOT"
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
  STATE_BASE="${LEADV2_STATE_BASE:-${HOME}/.claude/leadv2-state}"
  STATE_ROOT="${STATE_BASE}/${REPO_SLUG}"
fi

mkdir -p "$STATE_ROOT"

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
if [[ "$NO_LINK" -eq 0 ]]; then
  python3 - "$STATE_ROOT" "$LINK_ROOT" <<'PYEOF' 2>/dev/null || true
import os, shutil, sys

state_root, link_root = sys.argv[1], sys.argv[2]
leadv2_dir = os.path.join(link_root, "docs", "leadv2")
os.makedirs(leadv2_dir, exist_ok=True)

# name -> is_dir
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
}

for name, is_dir in STANDARD.items():
    target = os.path.join(state_root, name)
    local = os.path.join(leadv2_dir, name)

    if os.path.islink(local):
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
PYEOF
fi

if [[ "$NAME" == "root" || -z "$NAME" ]]; then
  printf -- '%s\n' "$STATE_ROOT"
  exit 0
fi

TARGET="${STATE_ROOT}/${NAME}"
mkdir -p "$(dirname "$TARGET")"
printf -- '%s\n' "$TARGET"
