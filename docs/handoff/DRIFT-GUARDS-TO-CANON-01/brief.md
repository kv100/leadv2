# DRIFT-GUARDS-TO-CANON-01 — lift the two drift guards into the plugin canon

**Class:** Standard. **Repo:** leadv2 plugin (canonical tree). **Filed:** 2026-09-02 on founder order,
from a cross-repo request by the getmany-followup-bot lead.

## READ THIS FIRST — the rules that killed six rounds today
- **Pulse mode does NOT apply to you.** You have exactly one turn-chain; no notification will ever reach
  you. Never end a turn waiting for anything.
- **Never background a command whose result you need.** No Monitor, no `run_in_background`. Long commands
  run in the FOREGROUND with `timeout 900`.
- Nested agents are allowed and encouraged for bulk reads — but **synchronously only**, never with
  `isolation:"worktree"`, and you commit the child's output yourself.
- **Commit after every step.**

## Why
`plugin-scripts-drift-guard.sh` and `plugin-scripts-drift-session-warn.sh` exist ONLY in
`~/Projects/persona-engine/.claude/hooks/`. They are the only mechanism in any of the four repos that
catches a **real file sitting where a symlink to canonical belongs** — the failure that cost the
getmany-followup-bot lead two days (a 4-May real copy of `claude-subsession.sh`, 990 lines behind
canonical, silently killing the opus review arm) and that leaves 202 real copies inside the plugin's own
repo. That lead refused to copy the hooks into their repo, correctly: a second uncanonical copy is the
disease itself.

`leadv2-link-tree-heal.sh` runs in both repos and does NOT see this: it only ADDS missing symlinks and
never recognises a regular file occupying a symlink's place. That is why it stayed silent.

Verified before filing: the guard is repo-agnostic already — canonical root comes from
`LEADV2_CANONICAL_ROOT` (default `$HOME/Projects/leadv2`), no repo-specific path anywhere in its 84
lines, and it fires only on a **staged** file, so it cannot block ordinary work in a repo that merely
contains drifted copies.

## Deliver
1. Move both hooks into `plugins/leadv2/hooks/` as canonical, and wire them the way the other plugin
   hooks are wired — **both wiring places**: the plugin hook manifest AND the name+predicate table
   inside `hooks/leadv2-bash-pre-dispatch.sh`. A hook wired in only one of the two is a hook that
   silently does not run; that exact mistake produced a false "25 orphan hooks" census today.
   The persona-engine copies become symlinks to canonical — never left as a second real copy.
2. `leadv2-repo-install.sh --check` must FAIL (non-zero) on a drifted copy and name each file with its
   line delta, using THIS code rather than a second implementation. Today it reports
   `.claude/scripts linked 20` and `ok` while five stale copies sit beside it — and it is itself one of
   the drifted copies, 110 lines behind canonical.
3. `leadv2-link-tree-heal.sh` must at minimum REPORT a real file where a symlink belongs (healing it is
   out of scope — a drifted copy may hold unmerged work that has to go UP into canonical first).

## Done when — the acceptance that matters
The done-condition is **not** "the file is in `plugins/leadv2/hooks/`". Plugin hooks load from the plugin
CACHE, which is a separate copy, and `claude plugin update` no-ops when content changed but the version
did not. So a hook that sits in canon and never loads is exactly the lying-green disease this task
exists to kill.

Prove all of these, pasting the output:
- in a scratch repo that is NOT persona-engine, plant a real copy of a canonical script under
  `.claude/scripts/`, `git add` it, and show the guard REFUSES the commit, naming the file and its
  canonical twin;
- negative control: revert the wiring row in a mktemp FULL copy of the plugin tree (including `lib/`)
  whose baseline is green → the case must go red. Paste both runs;
- `leadv2-repo-install.sh --check` against that same planted copy exits non-zero and names it;
- state plainly in the report what a session must do for the hook to actually load (cache copy +
  restart), because the next reader will otherwise assume canon is enough.

## Explicitly out of scope
- `guard-shared-git-destructive.py` and `leadv2-close-diff-guard.sh` — not lifted. Neither is confirmed
  by any real failure, and a hook adopted because a neighbour has it is future drift plus a false sense
  of protection.
- Converting the plugin repo's own 202 copies to symlinks (that is SD-SYMLINK-FARM-CONVERT-01, gated on
  no live lanes).

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Fixtures and mutants in mktemp only. Tree clean, `main` merged.
