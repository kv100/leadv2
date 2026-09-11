# ADDENDUM 2 — the symlink must never land before its target

Measured 2026-09-11 in `~/Projects/persona-engine`, while lane `1753a23440c1` was still running.
**This corrects the brief, not the lane.** The lane did exactly what step 2 told it to.

## What happened

The lane had already committed the 11 plugin-side files on its own branch:

    6d8f763a feat(guards): move 11 portable guard hooks into the plugin (step 1 of 2)

…in `~/Projects/leadv2/.claude/worktrees/1753a23440c1`. It then carried out the brief's step 2 in
`~/Projects/persona-engine`, replacing each `.claude/hooks/<name>.sh` with a symlink to
`~/Projects/leadv2/plugins/leadv2/hooks/<name>.sh`.

That path resolves against leadv2 **main**, which does not have the files — they are on the lane's
branch. So all 11 symlinks were dangling, and `git status` in persona-engine showed eleven ` T`
typechanges. For as long as that state stood, persona-engine ran with **eleven hooks registered and
none of them executable**, including `leadv2-bash-hook-dispatcher.sh` — the launcher for the
destructive-git block, the heredoc block and the foreground-dispatch block.

Registered hook names resolving to a file went **19 → 8**. Restored from HEAD, it is 19 again.

## Why the brief is at fault

Step 2 says "replace each `.claude/hooks/<name>.sh` with a symlink to the plugin copy" and asserts
the acceptance property "behaviour in persona-engine must not change at all". Those two cannot both
hold while the plugin copy exists only on a branch. The brief created a cross-repo dependency on a
commit that had not landed, and put the dependent side first.

It is the same failure mode as ADDENDUM 1 one level up. There, a fan-out registered without its
children skips them one stderr line at a time. Here, a registration points through a symlink at a
file that is not there yet. Both read as enforcement; neither enforces. ADDENDUM 1 was caught by
reading the launcher; this one was caught by a probe —
`persona-engine/scripts/check-registered-hooks-exist.sh`, written the same hour for a different row,
went red within a minute of the breakage.

## Binding ordering rule

**The plugin commit lands in `~/Projects/leadv2` main BEFORE any repo is pointed at it.** Concretely,
in this order, and never overlapping:

1. Merge the lane's plugin-side commit into leadv2 main. `~/Projects/leadv2/plugins/leadv2/hooks/<name>.sh`
   must exist and be readable from a plain checkout — verify by `test -r`, not by reading the branch.
2. Only then replace persona-engine's 11 real files with symlinks, and immediately run
   `bash scripts/check-registered-hooks-exist.sh` — it must print 23/23 and exit 0.
3. Only then add the getmany-followup-bot registrations.

If step 1 has not landed, step 2 does not start. A lane may prepare the symlink change; it may not
apply it to a shared checkout. The window between the two is a repo with no guards, and nothing in
the system announces it — the hook runner is silent about a hook it cannot find.

## Acceptance addition

The suite named in the brief must assert, as its FIRST check, that every symlink under
`persona-engine/.claude/hooks/` resolves (`test -e`, which follows the link — `test -L` and
`os.path.islink` are both TRUE for a dangling link and will pass a broken tree). Negative control:
point one symlink at a nonexistent path and the suite must go RED.

This is not hypothetical. The only other dangling symlink in that directory,
`leadv2-supervisor-mode-reinject.sh`, was first scored **healthy** by exactly that mistake.
