# Lead addendum — the writer's real path (verified 2026-09-06)

The brief stands. Two corrections to its file paths only; nothing about the defect,
the acceptance criteria, or the rules changes.

## 1. `plugins/leadv2/scripts/lib/leadv2-events.sh` does not exist

The brief's `LANE_WRITES` names it. `ls` says no such file. Dispatching against that
write-set would refuse the lane for touching an undeclared path.

**The real writer is `plugins/leadv2/scripts/leadv2-event.sh`** — 97 lines, singular
`event`, not under `lib/`. Verified:

```
plugins/leadv2/scripts/leadv2-event.sh:17
  LEADV2_EVENT_LOG_DIR="${LEADV2_EVENT_LOG_DIR:-${HOME}/.claude/cache/leadv2-events}"
plugins/leadv2/scripts/leadv2-event.sh:62
  local logf="${LEADV2_EVENT_LOG_DIR}/${repo}.jsonl"
```

The corrected write-set is passed on the dispatch `--writes` flag; use it rather than
the brief's line 5.

## 2. The override variable already exists — and its default is the bug

`LEADV2_EVENT_LOG_DIR` is already an env override. It **defaults to the live directory**,
which is precisely the fail-open the brief's §1 forbids ("the default must be safe, not
the exception"). So the lane is not inventing a new variable: it is making an existing one
**mandatory** at `leadv2-event.sh:17`, and that single line is the smallest part of the job.

The work is the rest: the behavioural census, the loud non-zero refusal, proving every
suite sets it, and the before/after `sha256` on the live journal.

There is **no test-context guard anywhere in the file** — all 97 lines were read.

## 3. Unchanged

Everything else in `brief.md` binds as written, including §0's warning that the causal
claim about the freepool breaker is **unproven** and must be decided by experiment, not
inherited.
