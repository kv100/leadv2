# Where plan-routing telemetry is written: nowhere persistent

Follow-up to `haiku-opus-zero-rows.md`. Question: does plan-job arm selection get recorded
anywhere, even outside `model-select-telemetry.csv`? Checked structured telemetry, then the shared
journal system, then the actual `emit` implementation plan-run uses. Answer: **no — its `emit()` is
a local stderr-only shim, not a writer into any persistent sink.**

## Step 1 — does plan-run.sh log an arm decision at all

Yes. `leadv2-plan-run.sh:759` (and neighbours 685-762): `emit decision "plan_run task=${TASK}
status=ran arm=${architect_arm} critic=${_critic_arm}"` — a genuine outcome-level line (status=ran,
after success, names the arm that actually ran), not a pre-run candidate. So the CODE intends to
record this.

## Step 2 — does it reach the shared journal system

Searched all 243 real (non-`.ephemeral`) `journal.md` files under `~/.claude/leadv2-state/*/tasks/`
for `plan_run`. **Zero occurrences, of any shape** (checked the exact string first, then loosened to
a bare substring match to avoid missing a reformatted line — still zero). Not a formatting mismatch:
the string never appears.

## Step 3 — why: plan-run.sh's own `emit()` is not the journal writer

`leadv2-dispatch-code.sh:2065`'s `emit()` is the function that appends to the shared per-task
journal (the one `_model_select_telemetry` and every build-path decision use). `leadv2-plan-run.sh`
does **not** call that one. It defines its own, local, and much weaker version at line 129:

```bash
emit() { printf '[leadv2-plan-run] %s %s\n' "${1:-}" "${2:-}" >&2; }
```

Every `emit decision "plan_run ..."` line in that file goes to **stderr only** — no file, no journal,
no CSV. Confirmed there's no wrapper catching it either: grepped the whole repo for callers of
`leadv2-plan-run.sh` from other scripts and found none in production code — only test files and one
doc reference. `plugins/leadv2/docs/phases.md:150-153` shows how it's actually meant to run: as a
direct foreground `bash .../leadv2-plan-run.sh ...` command inside the LEAD's own phase flow, not a
worker spawned and supervised by `dispatch-code.sh`. That fits the earlier finding that opus/plan
decisions "stay lead judgment" — but it also means the arm choice for the single most expensive
class of decision in the system (plan jobs, where opus and fable are live candidates) is printed
once to whichever terminal happened to be running it, and then gone.

## Answer

Not "somewhere else, unmeasured yet" — **nowhere persistent, by construction.** The code names the
right value (`architect_arm`) at the right moment (after success) and then writes it to a
stream nothing keeps. This isn't a missing column in a CSV; it's a local logging shim that was never
wired to the shared journal at all. Recovering this data going forward means pointing
`leadv2-plan-run.sh`'s `emit()` at the same journal-writing function `dispatch-code.sh` uses (or
piping its stderr into that journal from the caller side) — not a row, per your standing
instruction this round; naming the fix, not filing it.
