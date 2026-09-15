# REDSUITE-D-REVIEW-RUN-TRAP-AND-FOCUS-FLATTENING-01

Row `689648a9641b`. Two red suites, one shared subject file: `leadv2-review-run.sh`.

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.** It carries the
rules that decide whether this lane's work is accepted; they are not repeated here.

## What was measured, by the lead, on main, before this lane existed
macOS Darwin 25.6.0, each suite run alone at a 400s ceiling, 2026-09-15:

```
test-review-round-exhaustive.sh   rc=1  wall=18s
test-leadv2-trace.sh              rc=1  wall=28s
```

### Suite 1 — `test-review-round-exhaustive.sh`: one case, T6
The only failing line is `FAIL: T6 codex focus flattening`. Everything else passes, **including all
eight `T7 red-first` cases against baseline `85ae886`** — so the suite's own instrument is sound and
you are looking at a real defect, not a broken fixture. Start by reading what T6 asserts about
"focus flattening" and what the codex path actually produces.

### Suite 2 — `test-leadv2-trace.sh`: one case, 5b
The only failing line is `5b no host installs its own EXIT trap after lv2_trace_arm_exit`. The
suite prints its own evidence:

```
5b leadv2-review-run.sh: trap ... EXIT installed after arm_exit
  line 126: 220:# nor any `trap ... EXIT` existed anywhere in plugins/leadv2.
  245:trap '_REVIEW_GATE_ST=$?; _review_gate_terminal_fallback "${_REVIEW_GATE_ST}"; exit "${_REVIEW_GATE_ST}"' EXIT
```

So: `leadv2-review-run.sh` arms the trace exit hook at line 126, and then installs its own
`trap … EXIT` at line 245. In bash a later `trap … EXIT` **replaces** the earlier one — it does not
chain — so the trace's exit hook never runs and the span is never flushed. The suite's own header
comment records that when 5b was written, no `trap … EXIT` existed anywhere in `plugins/leadv2`;
one has since been added. The review gate's terminal fallback is clearly load-bearing and must keep
working, so **do not simply delete it**: the two hooks have to coexist.

Note that 5a passes: a script that armed the trace and then lost its clock returns to the prompt
instead of hanging. Do not regress that while fixing 5b.

## The question you must answer before choosing a fix for 5b
Is the right owner the **host** (`leadv2-review-run.sh` chains the prior trap) or the **library**
(`lv2_trace_arm_exit` installs a chaining trap that composes with whatever comes later)? A library
fix protects every future host; a host fix protects one. Say which you chose and why, and if you
chose the host, say what stops the next host from repeating this. If you find other hosts with the
same shape, name them — do not fix them here, your write set does not cover them.

## Deliverables
- Fixes for both suites, each with its own negative control.
- `docs/handoff/REDSUITE-D-REVIEW-RUN-TRAP-AND-FOCUS-FLATTENING-01/report.md` in the shape
  `lane-rules.md` specifies.

## Acceptance
```
cd ~/Projects/leadv2 \
  && bash plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh >/dev/null 2>&1 \
  && bash plugins/leadv2/scripts/tests/test-leadv2-trace.sh >/dev/null 2>&1
```
Red today (rc=1). Green is not enough on its own — the report and its two controls are part of the
deliverable.
