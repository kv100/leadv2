# BROAD-STATUS-ROWS-01 — the status pulse duplicates one lane and drops another (Light)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-01`
All edits go there. Never `cd` to `/Users/kostiantyn.vlasenko/Projects/leadv2` and never edit
files under it. Never touch `/Users/kostiantyn.vlasenko/Projects/persona-engine`.

Write set: `plugins/leadv2/scripts/leadv2-broad-status.sh` (990 lines) and, if the snapshot is
the real source of the drop, `plugins/leadv2/scripts/leadv2-lanes-snapshot.sh`. Tests under
`plugins/leadv2/scripts/tests/`.

## The observation (measured, 2026-08-30T01:03:00Z)

Two lanes were live:
- `DISPATCH-PIN-CLUSTER-01` — codex, handle `task-mtf3rk5g-8xivc8`, worktree in **`~/Projects/leadv2`**
- `ANTI-SILENCE-DELIVERY-01` — sonnet, PID 28671, worktree in **`~/Projects/persona-engine`**

The emitted `docs/leadv2/founder-status.md` rendered:

```
| Линия | Что делает | Состояние |
| make the beat reach | make the beat reach the founder without the lead (Heavy) | пишет сейчас (451379 байт в потоке) |
| make the beat reach | make the beat reach the founder without the lead (Heavy) | пишет сейчас (451379 байт в потоке) |
```

Lane 2 twice — with the *same* byte count, so these are not two distinct streams — and lane 1
absent entirely.

## Two separate defects; fix both, do not conflate them

**A. The row identity is a mission-title fragment, not the lane.**
`leadv2-broad-status.sh:404` — `linia_name = prev_row_name or human_name(mission_title)` — and
`:407` `chto = product_sentence(mission_title)`. So the "Линия" column is derived from the
mission TITLE. That is why the column reads `make the beat reach` (a truncated sentence) and why
two rows are indistinguishable. The column must carry the lane identity — `task_id`, with the
sig8 when a task_id is absent — and the human title belongs in "Что делает", not in both.
Then dedupe rows by that identity, so one lane can never occupy two rows.

**B. A cross-repo lane is missing from the table.**
`table_rows = lanes_data.get("table")` (`:197`) comes from the snapshot's `sections.lanes.data`.
Find out whether lane 1 was absent from the snapshot, or present and dropped during rendering —
those are different bugs with different fixes. Read the snapshot the beat actually consumed; do
not infer. If the snapshot only walks one repo, say so plainly in your report: enumerating lanes
across repos may be a larger change than this task, and an honest "the snapshot is single-repo,
here is the evidence" is a better outcome than a guess that silently half-fixes it.

Note `:203-213` already carries a hard-won lesson about an empty `table_rows` being
indistinguishable from a real empty board. Do not regress that: "no lanes" and "could not read
the lanes" must stay distinguishable, and a lane that cannot be read must render as a named
degraded row, never vanish.

## Why this matters

This file is the founder's only status surface that does not depend on the lead relaying
anything. A pulse that undercounts work in flight cannot be used to tell whether a lane died —
which is the one question it exists to answer.

## Tests — negative controls, and you RUN them

`plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh` already exists; read it first and
extend rather than duplicate.

| Fix | Mutation (inside the function body) | Suite |
|---|---|---|
| A identity | make the row key fall back to the mission title again | new/extended: a fixture with two lanes whose mission titles share a prefix must render TWO rows with distinct `Линия` values, and one lane must never render twice |
| B presence | drop the cross-repo branch from the row collection | same suite: a fixture with lanes in two different repo roots must render both |
| regression | force `table_rows = []` on a read error | existing blind-suite assertion must still distinguish "empty board" from "could not read" |

Name each mutation in the suite header, apply it INSIDE the function body in a scratch worktree,
show the suite RED, revert, show GREEN. Paste the runs. A grep-for-a-string assertion does not
count as a control — it must execute the renderer.

Add the `EXTRA_SUITE_MAP` row for `leadv2-broad-status.sh` and prove selection with `--scope changed`.

## Done means

`git -C <lane root> status --porcelain` shows only control-plane residue (`docs/leadv2/*.lock`,
`bus.jsonl`, journals, `active.yaml`, `phases.d/*`) — every source and test change committed.
Report the commit shas, the three red/green mutation runs, and a rendered before/after of the
table for the two-lane fixture.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e9d256b4" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.