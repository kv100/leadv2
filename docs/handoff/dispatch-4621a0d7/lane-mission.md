# PHASES-ARE-THE-ONLY-PATH-01 — fix round 6 (plugin repo ~/Projects/leadv2)

Round 5's work is UNCOMMITTED in worktree `d4d014e1` on top of `f91fd70` (the worker died before
committing — commit it as part of this round, do not discard it).

Round 5 did fix both blocking items: `LEADV2_REQUIRE_PHASES=0` is an early return again, and the
review check now parses `reviewer` into an arm and requires it to be an allowed review arm.

**But it over-corrected: a LEGITIMATE review no longer satisfies the review phase.** Test run:
`pass=49 fail=3`, and the three failures are all in the "real thing must still work" direction:

```
FAIL: G7c: legitimate record-review should satisfy review phase
      (got: missing=…,review,…)
FAIL: G7c: sidecar rows () should equal ledger lines (1)
FAIL: G7f: malformed line should not hide valid row
      (got: missing=…,review,…)
```

A gate that nothing can pass is worse than no gate: it will be switched off within a day, and then
we are back to where this whole task started. This round is exactly these three, plus the commit.

## R1 — a legitimate `record-review` row must satisfy the review phase
Find what `record-review` actually writes today — the real field names, the real `reviewer` values,
and whether it writes a sidecar at all. Do NOT invent a vocabulary and then validate against it;
that is what broke here. Make the check accept what the real writer produces, and add a test that
runs the real `record-review` path end to end rather than hand-writing a row.

## R2 — the sidecar count mismatch (`sidecar rows () should equal ledger lines (1)`)
The sidecar appears to be empty while the ledger has one line. Either the sidecar is not being
written on the path the test exercises, or it is written somewhere the check does not look.
Determine which, and make writer and reader agree. If the sidecar is not actually needed for the
provenance property, say so and drop it rather than keeping a second store that can disagree with
the first — one writer, one reader, the same rule as the phase record itself.

## R3 — a malformed ledger line must not hide a valid row
Parsing must skip an unparseable line and keep scanning. Today one bad line makes a valid row
invisible, which is a denial-of-service on our own gate: anything that appends garbage to the
ledger disables review forever.

## Do NOT
Do not weaken the provenance property to make the tests pass: a row with an unknown `reviewer`, or
one the asserting run wrote itself, must still be rejected. Those cases pass now — keep them
passing. Do not touch anything outside the write set. Round 5 modified
`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py`, which was not in its write set — review
that change, and either justify it in your report or revert it.

## Base / write set
Worktree `d4d014e1`. Round 5's work is now COMMITTED as `1cdf7de` — start from that HEAD, do not
rebase, do not expect uncommitted edits.
`leadv2-phase-record.sh`, `leadv2-dispatch-code.sh`, `tests/test-phase-precondition.sh`, and the
`record-review` writer path if R1 or R2 requires it.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + the full `[PHASE-PRECONDITION]` summary line. Target
is `fail=0` with the forgery cases still failing when the forgery is attempted.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-4621a0d7" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.