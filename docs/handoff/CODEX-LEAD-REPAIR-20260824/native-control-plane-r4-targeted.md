# NATIVE-CODEX-CONTROL-PLANE-01-R4-TARGETED

One targeted High fix on worktree `a2d18758` at `0d987c9`.

A fake directory can copy a genuine linked worktree's `.git` pointer. In addition
to realpath and git-dir/common-dir checks, verify that the registered worktree
gitdir's own `gitdir` backlink (or the exact `git worktree list --porcelain`
mapping) resolves back to this real cwd's `.git` entry/toplevel. A copied pointer
whose registry backlink names another lane must deny.

Add a forged-`.git`-pointer fixture beside the real linked-worktree allow case.
Preserve all prior hook/manifest/guard cases. Commit the hook and focused test;
leave clean.

acceptance:
  surface: file_artifact
  observable: A genuine registered linked worktree may patch inside itself, while a directory copying its .git pointer is denied.
  authored_at: 2026-08-24T22:01:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh,plugins/leadv2/codex-lead/tests/test-codex-hooks.sh
