# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 — round 3 (review said fail; the gate would break every lane)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01`

LANE_WRITES: plugins/leadv2/config/freepool-arm.yaml,plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh,plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh,plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh,plugins/leadv2/scripts/tests/test-worker-output-gate.sh,plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh,tests/run-all.sh,docs/handoff/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/

Full report: `docs/handoff/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/review-r2.md`. HEAD is `8c5db82`.

**Won and mutation-proven on production files — keep both:** the content-based liveness probe (a
mutation at `leadv2-freepool-model-select.sh:238` drives the suite RED), and the arbiter honouring
the router's exclusion set. Those were the two founding defects and they are closed.

## [Critical] C-1 — the output gate crashes on bash 3.2 and falsely rejects every good worker

`lib/leadv2-worker-output-gate.sh:75` dies with `files[@]: unbound variable` on bash 3.2 whenever
the git diff is empty, and `freepool-coder.sh:1539` turns that crash into `reason=parse_error`.

So a worker that does its job and **commits** — leaving an empty working diff — is rejected as if it
produced broken code. The gate built to make a weak free model survivable would instead reject every
arm's good work, paid ones included. This is the exact bash-3.2 trap the brief warned about: an
unbound array under `set -u` is fatal, and it makes the guard fail in the worst direction.

Fix the array expansion, and add a control that runs the gate with an **empty** diff and asserts it
passes.

## [Critical] C-2 — `--from-git-diff HEAD` cannot see committed work

The gate inspects the working diff, so the moment a worker commits, there is nothing left to
inspect. That means it misses the very incident it was built for: today a worker committed a test
suite that fails `bash -n`, four times. Inspect the committed range (`origin/main...HEAD`) as well
as the working tree, and prove it against that real case.

## [Critical] C-3 — zero coverage of the production call shape

The suite never exercises the way `freepool-coder.sh` actually invokes the gate. Add a test that
drives the production call path, then mutate the call site out and show RED.

## [Critical] the headline model claim is wrong

`report.md` says the free arm will run `groq/openai/gpt-oss-120b` first. Live, the selector picks
**`nemotron-3-super` in 34 s** for the `implement` role — the role `build` dispatches actually use —
and `gpt-oss-120b` is **absent from `role_rank.implement` entirely**. The `review` role fails
outright after 90 s.

Two things to fix: make `role_rank.implement` actually contain the models the bakeoff favours, and
make `review` resolve at all. Then re-run the selector for **every** role and paste what each one
picks and how long it takes. The 34 s and 90 s cascades are a real per-spawn cost — report them.

## [High] the bakeoff ranks latency, not correctness

4 of 5 candidates emitted **byte-identical** output (`md5 720130d8…`), so the ordering is response
time wearing a correctness label. Use a task that actually discriminates — one where a weak model
plausibly fails, e.g. editing a real shell function under bash-3.2 constraints — and rank on
`bash -n`-clean, behaviourally-correct output. If the candidates still tie, say so and rank on
latency **explicitly**, rather than implying a quality ordering the evidence does not support.

## [High] two single-source violations — the rule this repo lost a day to

- `test-arm-capability-honoured.sh:137` writes a **real copy** of `leadv2-dispatch-code.sh` into the
  production scripts directory.
- `test-worker-output-gate.sh:78-105` mutates the **production** gate in place with no restore trap
  — an interrupted run leaves the mutation on disk.

Both must use a temp dir; the second needs a trap that restores on any exit path.

## [High] `--scope changed` selects nothing for a `freepool-arm.yaml`-only change

And that file is this round's headline artifact — the ranking is data, so a data-only change must
select the suites that grade it. Add the mapping and prove it.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN; a zero-match anchor is a hard failure, not a skip. Logs in `round3-red/`.
- **Bash 3.2.57 only** — and after C-1, grep your whole write set for every `${arr[@]}` expansion and
  confirm each is guarded under `set -u`.
- No test may write a real copy of a plugin-owned file into the production scripts dir, and no test
  may mutate production without a restoring trap.
- Commit before you stop.

## Done means

The gate passing on an empty diff and inspecting committed work, both mutation-proven; a test
driving the production call shape; `role_rank.implement` and `review` resolving, with per-role
selector output and timings pasted; a bakeoff that discriminates, or an explicit statement that the
ranking is by latency; both single-source violations removed; `--scope changed` selecting on a
yaml-only change; and a `report.md` whose first line names the model each role will actually run.
