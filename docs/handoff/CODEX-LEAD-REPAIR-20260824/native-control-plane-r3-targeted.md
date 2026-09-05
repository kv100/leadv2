# NATIVE-CODEX-CONTROL-PLANE-01-R3-TARGETED

One targeted High fix on worktree `a2d18758` at `1721008`.

The isolated apply_patch allow path must not trust a lexical
`.claude/worktrees/<id>` substring or `abspath`. Resolve `cwd` and targets through
realpath, require the cwd to be a genuine linked Git worktree (git-dir distinct
from common-dir and under the common repo's worktrees registry), require its real
toplevel to equal the allowed lane root, and require every existing or future
patch target to resolve inside that real toplevel. Main worktree, ordinary fake
directories, symlinked fake worktrees, absolute escapes and `..` escapes deny.

Add executable fixtures for a real temporary linked worktree and the symlink
bypass. Preserve all 18 focused and 43 manifest/72 guard cases. Commit only the
hook and focused test, leave clean.

acceptance:
  surface: file_artifact
  observable: apply_patch is allowed in a genuine isolated linked worktree and denied for main, fake, symlinked or escaping paths.
  authored_at: 2026-08-24T21:51:00Z

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh,plugins/leadv2/codex-lead/tests/test-codex-hooks.sh
