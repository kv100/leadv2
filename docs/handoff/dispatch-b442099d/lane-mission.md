# The review pool calls three launchable arms "unknown" and kills the lane

**Priority 0.** This kills lanes *after* their worker has already run — the most expensive possible
failure. It is the same doctrine violation as the empty-allowlist bug you just fixed
(`7351b176`), at a second site: an unknown is rendered as unusable and the path fails CLOSED.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed to
main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## The observation, whole

Lane `6763e6d5` (founder row `b0fe5f28527e`, the gate-budget work). Its worker spawned cleanly:

    2026-09-08T11:07:04Z model_select_telemetry task=6763e6d5 role=worker class=standard
      work_kind=build arm=codex model=gpt-6-astra fallback_depth=0 terminal=win cause=worker_spawned

Ten minutes later the lane was dead — not from the dispatcher, from the **review gate**:

    2026-09-08T11:17:28Z review_gate task=6763e6d5 status=arm_refused arm=glm reason=refused_quota
    2026-09-08T11:17:29Z review_gate task=6763e6d5 status=unreviewed reason=all_arms_unavailable
      author=codex
      pool=codex:author:,glm:ok:80,kimi:excluded:safety,fable:unknown:,opus:unknown:,sonnet:unknown:
      tried=glm refusal=all_arms_unavailable resolver_rc=0
    2026-09-08T11:17:36Z dispatch_terminal task=6763e6d5 terminal=dead cause=all_arms_unavailable

Read the pool one entry at a time:

| arm | state | verdict |
|---|---|---|
| codex | `author:` | correct — it wrote the diff, self-review is banned |
| glm | `ok:80` | the only arm tried, and it refused on quota |
| kimi | `excluded:safety` | correct |
| **fable** | `unknown:` | **never tried** |
| **opus** | `unknown:` | **never tried** |
| **sonnet** | `unknown:` | **never tried** |

All three of those are genuinely launchable on `kind=review` — measured 2026-09-08, the review set
is `codex, fable, glm, opus, sonnet`. And `resolver_rc=0`: the resolver **succeeded**. So unlike
the bug you just fixed, this is not a subprocess failure producing an empty set. The resolver ran
and deliberately classified three good arms as `unknown`.

One quota refusal killed a lane that had three available reviewers.

---

## The two seams — confirm them, do not re-derive them

**Seam 1, the consumer.** `leadv2-dispatch-product-close.sh:558`:

    if printf '%s\n' "${_resolver_out}" | sed -n 's/^pool=//p' | tr ',' '\n' | grep -q "^${_ra_candidate}:ok:"; then

A candidate qualifies only on a literal `:ok:`. `fable:unknown:` can never match. The refusal is
emitted at `:427-432`.

**Seam 2, the producer.** `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` builds that
pool string and decides which arm gets `ok` / `unknown` / `excluded:<reason>` / `author`.

**Start at seam 2, not seam 1.** The interesting question is not "should `:ok:`-only be relaxed"
— it is **why can the resolver not classify fable, opus and sonnet?** If it simply has no probe
for them, then `unknown` is honest and the bug is that an honest unknown is treated as a refusal.
If it has a probe and the probe failed, that is a different bug with a different fix. Find out
which before you change anything, and say which in your report.

---

## The constraint that makes the naive fix wrong

Do **not** fix this by trying every arm in the pool. `leadv2-dispatch-product-close.sh:448-451`
records two standing rules, and they are load-bearing:

- never collapse to sonnet — that just recreates the self-review bug when the author is sonnet;
- **GLM never reviews without going through its own quota check, never as a blind fallback**
  (founder rule).

So "unknown fails OPEN" cannot mean "unknown is treated as ok". It has to mean something like:
an unknown arm is *probed* before being written off, or is admitted only through the same checks
an `ok` arm passes. Which of those is right is yours to determine and defend — the acceptance is
that a single quota refusal must stop killing a lane that has capable reviewers, without punching
a hole in either standing rule.

---

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **Reproduce the kill.** Force glm to refuse on quota with the other arms in whatever state
   produced `unknown` here, and assert the lane reaches a reviewer instead of
   `terminal=dead cause=all_arms_unavailable`. Before your fix this must FAIL.
2. **Assert the rules still hold.** With the fix in, prove that (a) the author is still never
   selected as its own reviewer, and (b) glm is never selected without its quota check. Break each
   deliberately and show the suite goes red **on the value** — a reviewer identity, a call count —
   never on a log string alone.

Insert every mutation **inside the function body**, never as a top-level line: a top-level insert
reddens everything for the wrong reason and reads as a pass. That mistake has already invalidated
one measurement in this repo.

Register the suite so CI selects it on a change to `leadv2-dispatch-product-close.sh`. Use the
`# run-all-triggers: <stem>` header — it is a real supported mechanism
(`tests/run-all.sh:173-232`) and it works; your last suite proved it.

**When you prove selection, the checkpoint will lie to you.** `--scope changed` records HEAD in
`$GIT_DIR/leadv2-run-all-last-checked-sha` (`tests/run-all.sh:294-310`) and a later run counts
from that mark, not from the merge base. If your lane has already run the gate once, the proof run
will under-select and your suite will look unregistered. Move the sentinel aside for the proof and
put it back, and state in the report which range you measured from. This is filed as
`SCOPE-CHANGED-IS-STATEFUL-AND-A-SECOND-RUN-LIES-01`; it cost me a wrong conclusion on your last
lane an hour ago.

---

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- Do not widen into the dispatcher-side fix you already landed (`7351b176`); this is the review
  gate, a different function and a different failure.
- If the root cause turns out to be in the arbiter rather than in either seam, stop and report
  that — do not chase it across a third file without saying so first.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b442099d" "<question>" \
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