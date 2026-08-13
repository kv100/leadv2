# A reviewer that returns no verdict kills the lane instead of falling through to the pool

Repo for this lane: **`/Users/kostiantyn.vlasenko/Projects/leadv2`**. All edits land there.

## The defect

Lane `4fb7381a` reached review, the pool resolved cleanly
(`review_pool_resolve rc=0 reviewer=kimi pool_n=5`), and then died:

```
review_gate status=blocked reason=no_verdict_marker
dispatch_terminal terminal=dead cause=no_verdict_marker
```

The reviewer's own output (`docs/handoff/dispatch-4fb7381a/review-kimi.md`) ends in
`[Tool use interrupted]` under a banner stating it assumes a 200k window for
`moonshotai/kimi-k3-free`. It never emitted `REVIEW_VERDICT:`. So the diff was never reviewed at
all — and the lane was killed rather than handed to the next of **five** available arms.

The review-pool fix `717b16f` made the pool *populated*. It did not make a failed reviewer *fall
through*. Those are two different guarantees and only the first exists today. A no-verdict return
is precisely the case a pool exists for.

## What to build

On `no_verdict_marker` (and any other "the reviewer produced nothing usable" outcome — empty
output, truncation, a non-zero exit with no marker), the gate must try the **next arm in the pool**
and record the skip, killing the lane only when the pool is genuinely exhausted. The `tried=` list
already exists for exactly this bookkeeping — use it rather than inventing new state.

Emit a journal line per fall-through so the cost is visible, e.g.
`review_gate status=arm_no_verdict arm=<model> reason=<why> tried=<list> remaining=<n>`, and keep
the terminal `no_verdict_marker` death for the exhausted case with the full `tried=` list attached.

## Explicitly out of scope — do not do this

Do **not** fix it by excluding kimi (or any model) from the pool by name. Routing belongs to
quota/task/complexity, never to a hand-kept list. If a model is genuinely unfit for large-diff
review, that belongs in the **admission rule** with a measured threshold (e.g. diff bytes vs the
arm's context window), not in an exclusion list — and that is a separate change from this one.
Also do not change the reviewer prompt, the verdict marker format, or the pool resolver: the
resolver is not the bug.

## Tests

- A test that drives the gate with a first arm returning output containing no `REVIEW_VERDICT:`,
  and asserts the second arm is invoked and its verdict is the one recorded. **Show it RED against
  the current gate** (today it terminates instead).
- A test that a truncated/empty reviewer output is treated the same way, not as a pass.
- A test that when every arm returns no verdict, the lane still dies with `no_verdict_marker` and
  the journal carries the full `tried=` list — the guarantee must not become "never fails".
- A test that a normal PASS on the first arm still calls exactly one arm (no extra spend).

## Proof required

- Each new test pasted RED against the pre-fix file, then green.
- The journal lines from one real fall-through, pasted verbatim.
- The full plugin suite for the files you touched, with counts.

## Hard limits

- Do not touch `leadv2-review-run.sh`'s single-owner property — the one-path work merged this
  morning (`2916fe0` / `43a634e`) and must stay the sole flag=1 owner.
- Note three suites are red on untouched `main` and are **not yours**:
  `run-core-offline.sh` (rc=124 at 600s, two codex-lifecycle assertions). If a gate blocks you on
  it, say so rather than trying to fix it here.
- Never `git add -A` from the lane worktree: a lane earlier today would have silently reverted 890
  lines of `docs/leadv2/open-threads.md`. Stage your paths explicitly.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-30e50f97" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.