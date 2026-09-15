# GUARD-READ-ONLY-IS-A-NAME-NOT-A-PROPERTY-01 — two rows, one mechanism

Backlog rows `GUARD-GENERAL-PURPOSE-IS-NOT-READ-ONLY-01` and
`GUARD-READ-ONLY-ROLES-KEEP-MUTATING-BASH-01`. One lane: the second is what makes the first
worth doing, and they touch the same guard family.

All writes in **`~/Projects/leadv2`**. Files:
`plugins/leadv2/hooks/leadv2-routing-guard.sh`, `plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh`,
and a new suite under `plugins/leadv2/scripts/tests/`.

## The measurement (2026-09-15, reported by the getmany-followup-bot session)
That session spent a day routing every piece of work to Claude — Codex and GLM were never called.
The cause: the lead spawned `general-purpose` agents directly.

The guard's own header says why a direct lead spawn is forbidden for write roles: it
*"skips complexity estimation, the balancer, the arbiter and the phase ladder"*.
`_is_write_role()` at `leadv2-routing-guard.sh:79-80` lists
`developer|frontend-developer|postgres-pro|devops-engineer|architect|product-owner`.
It does **not** list `general-purpose` — and `general-purpose` carries `tools: *`: Edit, Write,
Bash, git, ssh.

Through that role the reporting session shipped a production deploy, wrote and committed
TypeScript, and made a `PUT` to a third-party API. Formally clean against the base allowlist
(`general-purpose` + `model=haiku|sonnet`); in substance, a bypass. Read-only is the role's name,
not its property.

Verified independently in this repo before this mission was written: the `_is_write_role` body
does not contain `general-purpose`, and the base allowlist admits it.

## Defect 1 — the classification is wrong
Move `general-purpose` into `_is_write_role`. It then hits the same refusal as any write role,
with the existing pointer to `leadv2-dispatch-code.sh` and the existing journalled escape hatch
`LEADV2_LEAD_WRITE_SPAWN_ALLOW=1`.

`Explore` and `recon` stay read-only. The comment beside them is correct and stays true: *a guard
that refuses everything is an outage, not a fix*. Do not fork the list — both the nested path and
the lead path must keep consulting the one function.

## Defect 2 — a read-only classification is void while the role holds Bash
Defect 1 alone moves the bypass one role sideways: `Explore` also has Bash, so the same deploy,
the same `git commit`, the same `ssh` go through it instead.

Add a sub-hook to `leadv2-bash-pre-dispatch.sh`: when the calling agent type is in the read-only
set, refuse a **mutating** shell command. At minimum `git commit` / `git push`, `sed -i`, `ssh`,
`docker exec`, and `curl -X PUT|POST|DELETE`. The mechanism already exists in that file — this is
a sub-hook beside `leadv2-block-bash-heredoc`, not new infrastructure. Read the existing refusal
path and match its shape, its exit convention and its message format rather than inventing one.

Two properties, both required:
1. The refusal **names its cause** — which role, which command class. A refusal that cannot be
   read back is the defect this repo keeps paying for.
2. A read-only caller running a genuinely read-only command (`git log`, `grep`, `curl` with no
   `-X`, a plain `ssh host true`… decide and state where you drew the line) is **unaffected**.
   State your line and why. Over-refusal here is an outage across four repos.

## Blast radius — read this before you widen anything
This plugin is one inode shared by `persona-engine`, `respiro-ios` and the m3 repo, with live
sessions in them right now. A guard that over-refuses takes all four down at once. Prefer the
narrow, named command set above over a clever general rule.

## Acceptance
- `sed -n '/^_is_write_role()/,/^}/p' plugins/leadv2/hooks/leadv2-routing-guard.sh | grep -q general-purpose` → rc=0.
- A new suite `plugins/leadv2/scripts/tests/test-readonly-caller-cannot-mutate.sh` that drives the
  **real** hook (not a reimplementation of its `case` statement) and asserts:
  (a) a read-only caller running `git commit` is refused, with the cause named in the message;
  (b) the same caller running a read-only command is admitted;
  (c) a write-role caller is already refused at spawn, unchanged.
- Proof the guard fires **live**, not that the file changed: run the hook on its real input path
  and paste the refusal. A report that a gate was deployed has been wrong here before while the
  live hook still allowed everything — verify by reading the behaviour, never by the diff.

## Negative controls — one per independent check, ALL RUN
1. Remove `general-purpose` from `_is_write_role` → the spawn test goes RED.
2. Remove the mutating-command sub-hook → the `git commit` refusal test goes RED.
3. Widen the sub-hook to refuse everything → the read-only-command test goes RED. This one is the
   over-refusal control and it is not optional: without it the suite cannot tell a working guard
   from an outage.

Paste all three red/green pairs. A mutation anchor that does not match must fail loudly — an
unmatched anchor is a test failure, never a silent skip.

## Off limits
- Do not change what happens when there is **no active task**. That is a third row
  (`GUARD-NO-ACTIVE-TASK-IS-PERMISSIVE-01`), it is a policy decision, and it is not yours.
- Do not touch the arbiter, the balancer, complexity estimation, quota, or the phase ladder.
- Do not remove or weaken `LEADV2_LEAD_WRITE_SPAWN_ALLOW=1` — it is the audited escape hatch and
  it stays journalled.
- Do not `git stash`, `git reset --hard` or `git clean`: this checkout is shared with live
  sessions in three other repos.

## Known limit — state it in the report, do not try to fix it
Both defects are gates on agent **spawn**, not on the **action**. A lead can run
`deploy-latest.sh` from its own Bash with no agent at all, and no routing gate sees it. This lane
narrows the hole; it does not close it. Say so plainly in the report so nobody reads this as
"the arbiter can no longer be bypassed".

## Report
`docs/handoff/GUARD-READ-ONLY-IS-A-NAME-NOT-A-PROPERTY-01/report.md`: the diff summary, the live
refusal output, the suite green, all three controls, and the known limit.
End with `DELIVERABLE_COMPLETE`.
