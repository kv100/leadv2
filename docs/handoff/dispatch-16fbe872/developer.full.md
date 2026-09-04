verdict: NEEDS-INFO
next_action: escalate_to_founder

# dispatch-16fbe872 — CLAUDE-PROFILE-SELECT-FINISH-01 — census falsification

## Summary

The scoped design's premise **P1** ("Task 1 [cherry-pick] is already done. Drop it — both
selector commits are ancestors of `main` at b5ea9f8") is **false for this lane's actual
tree**. No implementation was attempted; implementing C1–C6 against files that do not exist
here would mean silently redoing the exact cherry-pick/merge work the design explicitly
declared a non-goal, on my own authority, which is outside my scope to decide.

## Evidence

Working directory: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/16fbe872`,
branch `worktree-16fbe872`, clean, "up to date with origin/main".

```
$ git log --oneline -1 HEAD
e3ed68c merge(8e705910): LANE-REGISTRY-SELF-DEADLOCK-01 ...

$ git log --oneline -1 origin/main
e3ed68c merge(8e705910): LANE-REGISTRY-SELF-DEADLOCK-01 ...

$ git log --oneline -1 main        # LOCAL main ref only
b5ea9f8 fix(codex-lead): harden tmux statusline paths and uninstall

$ git merge-base --is-ancestor b5ea9f8 HEAD && echo YES || echo NOT
NOT

$ git log --oneline main..HEAD | wc -l
20   # HEAD (origin/main) has 20 commits main doesn't have — separate line of history

$ git log --oneline HEAD..main
b5ea9f8 fix(codex-lead): harden tmux statusline paths and uninstall
dd2fda6 feat(codex-lead): opt-in tmux statusline CODEX-TMUX-STATUSLINE-01
fdfd043 fix(codex-lead): pulse hook production repo root CODEX-PULSE-HOOK-03
99af218 feat(codex-lead): native pulse hook CODEX-PULSE-HOOK-02 R2
747c1ad fix(quota): honor selected keychain service
8d92974 docs: align GLM routing guidance with 5.3 evidence
8d00999 wip(9cefb22b): auto-checkpoint on worker exit (STOP-GATE)
... (13 more, all only reachable from the stale local `main` ref)

$ ls plugins/leadv2/scripts/leadv2-claude-profile-select.sh
ls: No such file or directory
$ ls plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py
ls: No such file or directory
$ ls plugins/leadv2/scripts/tests/test-claude-profile-select.sh
ls: No such file or directory

$ for b in $(git branch -a --format='%(refname:short)'); do
    git cat-file -e "$b:plugins/leadv2/scripts/leadv2-claude-profile-select.sh" 2>/dev/null && echo "HAS FILE: $b"
  done
HAS FILE: main
HAS FILE: worktree-9cefb22b
HAS FILE: worktree-tmux-statusline
```

Interpretation: the design's `git merge-base --is-ancestor 8d00999 main` probe genuinely
returns `YES` — but only because the *local* `main` branch pointer in this repo is stale,
frozen at `b5ea9f8`. The repo's actual current trunk, `origin/main` (== this worktree's
`HEAD`, `e3ed68c`), is on a **different, divergent line** that contains 20 commits not in
`b5ea9f8`'s line (the LANE-REGISTRY / MERGED-BATCH-FIXROUND / handoff-guard work) and does
**not** contain `b5ea9f8`'s line at all — including `8d00999`, `747c1ad`, and the whole
tmux-statusline branch. The task binding says "Worktree: ... @ base b5ea9f8", but the
worktree's live branch has since moved to track `origin/main` at `e3ed68c`, which never
merged that work in.

Net effect: none of the six files this lane is scoped to touch —
`leadv2-claude-profile-select.sh`, `lib/leadv2-claude-profile-pick.py`,
`claude-subsession.sh`'s selector wiring, `tests/test-claude-profile-select.sh` — exist in
this tree. `claude-subsession.sh` and `lib/leadv2-codex-quota-gate.sh` do exist (verified),
but the profile-select machinery they're supposed to already have (C2's edit target
`leadv2_select_claude_profile`, lines 605-619) is simply absent — `claude-subsession.sh`
here predates that feature entirely.

```
$ grep -n "leadv2_select_claude_profile\|CLAUDE_CONFIG_DIR" plugins/leadv2/scripts/claude-subsession.sh
(no match)
```

## Why I stopped instead of implementing around it

The mission's prepass instruction is explicit: a census falsification means STOP and report,
not implement around it. Implementing C1–C6 here would require first performing the exact
cherry-pick/merge of `8d00999` + `747c1ad` (or equivalent) that the design's own non-goals
section forbids ("No cherry-pick, no lane branch off worktree-tmux-statusline, no touching
that branch"). Doing that unilaterally would both violate an explicit non-goal and silently
decide a fork (which base is authoritative) that the design assumed was already resolved.

## What I did NOT do

- No files touched under `plugins/leadv2/scripts/` — tree is unchanged from `origin/main`.
- No cherry-pick, no merge, no new branch cut from `worktree-tmux-statusline`.
- No commit made (nothing to commit — working tree is clean and matches HEAD).

## Options for the lead/founder

1. **Re-cut the lane from `worktree-tmux-statusline` (or `main`'s stale tip `b5ea9f8`)
   instead of `origin/main`**, so the selector code is actually present, then re-dispatch
   this same design (C1–C6 apply as written once the files exist).
2. **Merge `worktree-tmux-statusline` into `origin/main` first** (a separate, larger
   decision — that work has never landed on trunk), then re-dispatch this lane against the
   updated trunk.
3. Confirm the intended base explicitly if there's context I'm missing (e.g. an in-flight
   rebase this worktree hasn't picked up yet) and re-point this branch there.

I did not pick one of these myself — it changes which commits are authoritative on `main`,
which is a call above this lane's scope.

## Self-check (falsification set)

Not applicable — no shell/Python files were changed, so there is nothing to `bash -n` /
`py_compile` / test. Working tree remains byte-identical to `origin/main` (`e3ed68c`);
`git status` is clean.

DELIVERABLE_COMPLETE
