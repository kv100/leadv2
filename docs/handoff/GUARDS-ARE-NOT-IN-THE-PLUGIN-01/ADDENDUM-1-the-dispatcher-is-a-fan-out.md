# ADDENDUM 1 — `leadv2-bash-hook-dispatcher.sh` is a fan-out, and it fails OPEN

Measured 2026-09-11 after the lane was already dispatched. This corrects the main brief and
is **binding on landing**: do not register the dispatcher in another repo without its
children.

## What the file actually is

`leadv2-bash-hook-dispatcher.sh` is 159 lines and contains **none** of the guard logic. Grep
it for `heredoc`, `worktree remove`, `reset --hard`, `git clean`, `stash`, `foreground`,
`destructive` — every count is zero. It is a fan-out that runs seven child guards with a
per-child timeout:

| child | where it lives | plugin twin | persona-engine refs |
|---|---|---|---|
| `guard-shared-git-destructive.py` | repo file, 547 lines | **none** | 0 |
| `leadv2-supervisor-fanout-guard.sh` | repo file, 288 lines | **none** | 0 |
| `leadv2-close-diff-guard.sh` | repo file, 172 lines | **none** | 0 |
| `open-threads-shrink-guard.sh` | repo file, 77 lines | **none** | 0 |
| `leadv2-reflect-enforcer.sh` | repo file, 142 lines | **none** | 3 |
| `leadv2-phase8-gate.sh` | repo file, 117 lines | **none** | 3 |
| `plugin-scripts-drift-guard.sh` | symlink to plugin | yes | — |
| `check-careful.sh` | `${HOME}/.claude/hooks/` | — | file absent |

So the destructive-git block is **`guard-shared-git-destructive.py`**, a 547-line repo file
with zero persona-engine references and no plugin twin. That is the one the getmany session
needs — not the dispatcher, which is only its launcher.

## Why this is binding, not a detail

The dispatcher **fails open** on a missing child (lines 42-45):

    if [ ! -e "$child" ] || { [ ! -x "$child" ] && [ ! -r "$child" ]; }; then
      echo "[hook-dispatch] child missing or not runnable, skipping (fail-open): $child" >&2
      continue
    fi

One line on stderr that nobody reads, then it continues. Register the dispatcher in a repo
without its children and every guard silently skips while the registration looks like
enforcement. That is worse than today's state in getmany, because today nobody believes the
guard is there.

## Consequence for the work

The portable set is **11 + 4**, not 11. Add to the move, all four with zero persona-engine
references:

    guard-shared-git-destructive.py      (547)
    leadv2-supervisor-fanout-guard.sh    (288)
    leadv2-close-diff-guard.sh           (172)
    open-threads-shrink-guard.sh          (77)

`leadv2-reflect-enforcer.sh` and `leadv2-phase8-gate.sh` carry 3 persona-engine references
each — read them and decide per file; `leadv2-phase8-gate.sh` already exists in
getmany-followup-bot as its own repo file, so it needs no copy there in any case.

**Landing rule, non-negotiable:** the registration of `leadv2-bash-hook-dispatcher.sh` in
`getmany-followup-bot/.claude/settings.json` goes in ONLY in the same change that puts its
children on disk there. If the children are not ready, land the other ten hooks and leave the
dispatcher out. A fan-out with no children is a false green.

## Acceptance addition

The suite must assert that for every child the dispatcher lists, the file exists and is
readable from the repo where the dispatcher is registered. Negative control: remove one child
and the suite must go RED — proving the suite sees what the dispatcher's own fail-open path
would have swallowed.

## Credit where it is due

The getmany-followup-bot session forced this measurement. It reported that the heredoc block
DID fire in its repo, from `${CLAUDE_PLUGIN_ROOT}/hooks/leadv2-bash-pre-dispatch.sh` — plugin
content, portable, already working there — and warned that my file census was inference, not
a test: the right question is "does the guard fire", not "does the file exist". Checking that
is what surfaced the fan-out. Its correction was in the safe direction (one guard was already
present); this one is in the dangerous direction (a guard that would have looked present and
done nothing).
