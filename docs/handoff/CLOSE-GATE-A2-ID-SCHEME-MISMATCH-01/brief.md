# CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01 — A2 compares a human milestone name against a fingerprint id

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase8-assert.sh,plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh,tests/run-all.sh,docs/handoff/CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01/

Main is `de44cc7` in `~/Projects/leadv2`. Branch from it.

Reported by the session running V5 in persona-engine; **I verified every claim in the source
and against the live file before writing this** — do not re-derive it, fix it.

## The defect

`leadv2-phase8-assert.sh:240-243`:

```python
for it in items:
    if isinstance(it, dict) and str(it.get("id","")) == task_id:
```

`task_id` is the human milestone name (`V5-M0-SKELETON-01`). persona-engine's backlog is keyed
by fingerprints — the row's `id` is `ca2177b9451b`, and the human name lives inside `intent`:

```
$ grep -c 'V5-M0-SKELETON-01' docs/tasks.yaml
1
$ grep -n 'V5-M0-SKELETON-01' docs/tasks.yaml
23:  intent: 'V5-M0-SKELETON-01: веха M0 плана v5 …'
```

One occurrence, and it is in `intent`, never in `id`. **The comparison can never match**, so A2
always exits 2 and the close gate blocks forever.

Two aggravating facts, both confirmed:

1. **The remedy the failure prints does not work.** `leadv2_tasks_release V5-M0-SKELETON-01
   --outcome success` answers `[tasks-lib] V5-M0-SKELETON-01 not found` — same id-scheme
   mismatch, one layer down. A refusal that prints an impossible remedy is the second time
   today we have shipped that shape.
2. **The promised fallback does not exist.** The line after the loop reads
   `# Not found in tasks.yaml — check lane yamls as fallback` and is immediately followed by
   `sys.exit(2)`; the `rc -eq 2` branch at `:283-285` just records a failure. The comment
   asserts a behaviour that no code performs — the exact class of defect this session has spent
   the day removing.

Consequence right now: `V5-M0-SKELETON-01` is merged (`cdd907e76`), 8 of 9 HARD checks are
green, A2 is the only blocker, and `phase8-passed.flag` was not written. The V5 lead refused to
forge it, correctly. M1 through M12 will all hit this — every milestone is named by hand while
every backlog row is fingerprinted.

## [Critical] resolve the human id to the row before comparing

Match a row when **either** its `id` equals `task_id`, **or** its `intent` names `task_id` as
the prefix before the first colon. Resolve, then compare — do not widen the comparison into a
substring grep: `V5-M1` must not match `V5-M10`. Anchor on the full segment before `:`.

Apply the same resolution wherever else this scheme mismatch bites — at minimum
`leadv2_tasks_release`, so the printed remedy becomes executable. Say in `report.md` how many
call sites you found.

## [Critical] the fallback must exist or the comment must go

Either implement the lane-yaml fallback the comment promises, or delete the comment and make
the rc=2 message say plainly that only `tasks.yaml` was consulted. A comment describing
behaviour that does not exist is worse than no comment: it is what made this look like a data
problem rather than a code one.

## Acceptance

Build `test-phase8-a2-id-resolution.sh` against fixture `tasks.yaml` files — never the real
backlog — covering:

1. **a fingerprint-keyed row whose `intent` starts with the milestone name ⇒ A2 PASSES.** This
   is the case that exists in the real repo, and the negative control must fire on **this**
   fixture, not only on a row whose `id` already equals the name;
2. a row whose `id` equals the task id ⇒ still passes (regression guard);
3. `V5-M1` must not match a row whose intent begins `V5-M10:` — assert both directions;
4. a genuinely absent task ⇒ still fails, with a message naming what was searched;
5. the printed remedy, executed against the fixture, clears the failure.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. **The mutation must be reverted on the fingerprint fixture** — a control
  that only goes red on an id-equals-name fixture proves nothing about this repo, and that trap
  (a self-test ratifying the bug) is exactly what the V5 lead found in its own runner today.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

`leadv2-phase8-assert.sh` prints `A2 … PASS` for a fingerprint-keyed row named in `intent`,
`V5-M1` does not match `V5-M10`, the printed remedy is executable, and a mutation restoring the
id-only comparison turns the suite red with the exit code following.
