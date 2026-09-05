DISPATCHER-BRANCH-RESIDUE-01 — ten stranded branches each carry a slice of dispatcher work that
main mostly, but not entirely, already has. Land the residue that is still wanted, drop the rest,
and say which is which — with a reason per branch, not a percentage.

WHY THIS IS ONE TASK AND NOT TEN MERGES. Every one of these branches was killed by a gate defect,
not by a review: the close gate could not tell a pre-existing red from a regression, and its e2e
step could not pass by construction (`tests/run-all.sh:114-118` adds `run-core-offline`
unconditionally outside `--scope`, and that alone exceeds `LEADV2_PHASE8_E2E_TIMEOUT_S:-900`,
`leadv2-dispatch-product-close.sh:2764`). So their content was never judged. It has to be judged
now, once, by someone reading it — not by a merge strategy.

MEASURED 2026-09-04 on main `2b7e3883`, method stated so you can re-run it: for each branch, take
the lines it ADDS to `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (non-blank, non-comment,
whitespace-stripped, deduped) and count how many of those exact lines already appear in main's
copy of that file. Line-presence is a proxy for supersession, NOT proof of it — a line can be
present in a different function and mean something else. Re-derive per branch before trusting it.

  branch                             added   already in main
  83c44855                            155      127  (81%)
  PREPASS-PROVIDER-FALLBACK-01-R5     220      174  (79%)
  PREPASS-PROVIDER-FALLBACK-01-R6     220      174  (79%)   <- R5 and R6 are near-identical; say which supersedes which
  f7f1c2c8                             44       33  (75%)
  d784b987                              8        6  (75%)
  PLUGIN-RELIABILITY-01                11       10  (90%)
  PHASE-BOOTSTRAP-ADMIT-02             24        9  (37%)
  100a892d                             11        3  (27%)
  5e57c5ff                             21        5  (23%)
  049e0e9e                              0        0        <- touches the file not at all; its conflict is elsewhere

Branch names are `worktree-<id>` in `~/Projects/leadv2`. Several also touch
`leadv2-dispatch-product-close.sh`, `leadv2-helpers.sh`, `leadv2-phase-record.sh`,
`leadv2-routing.yaml` and `tests/run-all.sh` — those files are in scope too.

THE WORK.

1. Per branch, one verdict with a reason: SUPERSEDED (main already does this — name where),
   LAND (still wanted — land it), or OBSOLETE (the mechanism it edits no longer exists — name what
   replaced it). A percentage is not a verdict.
2. Land what you judged LAND. Land it as ONE coherent change per behaviour, not as ten merge
   commits — you are carrying intent across, not replaying history.
3. `tests/run-all.sh` conflicts in this set are all the same shape: the branch adds a row to
   `EXTRA_SUITE_MAP`, main migrated to per-suite `# run-all-triggers:` headers. Do NOT restore
   rows to the map. Convert each to a header in the suite it names, and prove the conversion —
   see acceptance 3.
4. Anything you land carries a behavioural test. A dispatcher change with no test is how this
   whole backlog was created.

ACCEPTANCE.

1. The verdict table, ten rows, each with its one-line reason.
2. For every behaviour you land: a suite, plus a NEGATIVE CONTROL applied INSIDE the function body
   that makes that suite go red, both outputs verbatim. A line-number insert that lands at top
   level reddens everything for the wrong reason and reads as a pass — that mistake was made on
   2026-09-04 and invalidated a whole measurement.
3. Prove CI selects each new or changed suite with `LEADV2_RUN_ALL_SELECT_ONLY=1
   tests/run-all.sh --scope changed` — modify the source script in the working tree, show the
   `[SELECT]` line, revert, show it absent. Both directions. Do NOT run a full `tests/run-all.sh`
   in a live checkout: a full run repointed five live control-plane symlinks
   (`active.yaml`, `questions`, `bus.jsonl`, `merge-queue.jsonl`, `.bus-offsets`) into a temp
   fixture directory and deleted their targets with it, measured 2026-09-04.
4. The dispatcher must still dispatch when you are done. Show `bash -n` clean AND one real
   `--no-spawn` invocation that reaches a routing decision, verbatim.

CONSTRAINTS. Shared plugin tree feeding three repositories; the founder authorised work in this
tree this session. Never `git add -A`. Do not push to origin. `tests/known-red-suites.txt` and
`tests/known-failures.txt` may only shrink. Do not touch `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`
— a separate live lane owns that file this session. If the close gate returns `e2e_regression`,
run the named suites on main WITHOUT your commit before believing it — a verdict is not evidence.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-8f5611ba" "<question>" \
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