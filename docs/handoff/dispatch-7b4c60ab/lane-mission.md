# PHASE-GATE-RECORD-VS-ASSERT-01 — plugin repo `~/Projects/leadv2`

All edits go in the plugin repo, NOT persona-engine. Do not rebase. Baselines to preserve:
`plugins/leadv2/scripts/tests/test-phase-precondition.sh` = 64/0,
`plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh` = 8/8 from BOTH the repo root and
inside a lane worktree. Subject file: `plugins/leadv2/scripts/leadv2-phase-record.sh`.

Full write-up with reproductions:
`~/Projects/persona-engine/docs/handoff/comment-targets-2026-08-05/PHASE-GATE-VERDICT.md`.
These three defects were found by running the contract for real on a live task, not by reading it.

## F1 — `record` stamps `proof=verified` without running `assert`'s verification

`cmd_record` writes the proof label from its own weaker path; `cmd_assert` re-verifies via
`_verify_artifact` and refuses. Reproduce on any sig:

```
leadv2-phase-record.sh record <sig> build --artifact <A DIRECTORY> --commit <sha>
leadv2-phase-record.sh show   <sig>     # build  done  verified      <-- lie
leadv2-phase-record.sh assert <sig> --class Standard
# missing=build ...  rc=3               <-- the truth
```

A directory cannot be sha256'd, so `_artifact_integrity` fails — yet `record` reported `verified`.
Same shape for `gate1`: `record` accepts any artifact path and stamps `verified` while `assert`
requires a non-empty `docs/handoff/dispatch-<sig>/.gate1-passed` sentinel.

Fix: `record` must call the SAME `_verify_artifact "$sig8" "$phase" "$artifact" "$sha" "$commit"`
that `assert` calls, and write `proof: verified` only on rc=0. On non-zero, write
`proof: unverified` and print a warning naming the phase and the reason — do not fail the record
(a lead recording a phase whose proof is not yet available is legitimate), but never label it
verified. `show` must render `unverified` distinctly.

This is the lying-GREEN disease inside the mechanism built to kill it: today a lead reading `show`
believes a lane is proven when the gate would refuse it.

## F2 — `deploy` is `n/a:no_runtime_surface` for EVERY task and every class

`_phase_derived` decides `deploy` from a `writes` list, but `cmd_plan_for` parses only `--class`
and its `*) shift` catch-all silently discards `--writes`, so `writes` is always empty:

```
leadv2-phase-record.sh plan-for <sig> --class Heavy
# NA deploy no_runtime_surface
leadv2-phase-record.sh plan-for <sig> --class Heavy --writes platform/lib/foo.sh
# NA deploy no_runtime_surface     <-- identical; the flag was dropped
```

`deploy` carries the contract's strongest proof (the commit must be a DESCENDANT of the lane's
start-sha) and is never demanded. `live_verify` derives from `deploy.done`, so it weakens with it.

Fix: parse `--writes` in `cmd_plan_for` and thread it into `_resolve_mandatory` exactly as
`cmd_assert` already does. Then a writes list containing an engine path must flip `deploy` to
MANDATORY, and a docs-only list must keep it `n/a:no_runtime_surface`.

## F3 — `plan-for` accepts any class string

```
leadv2-phase-record.sh plan-for <sig> --class BANANA   # prints a full plan, rc=0
```

`cmd_assert` validates `Trivial|Light|Standard|Heavy` case-sensitively and exits 4. `cmd_plan_for`
does not — so the surface that tells a lead WHICH phases apply answers confidently for a class that
does not exist, and a lowercase `heavy` (how the class is written in prose everywhere) silently
yields the default set instead of Heavy's.

Fix: same case statement, same exit 4, in `cmd_plan_for`.

## F4 — document only, no mechanism

`.gate1-passed` need only be non-empty and any process in the repo can create it, so it cannot
carry founder authority. Add one honest paragraph to the proof-level doc-block saying so —
same residual class already documented for the review provenance directory. Do NOT invent a new
mechanism in this round.

## Tests
Add cases to `plugins/leadv2/scripts/tests/test-phase-precondition.sh` — one per F1, F2, F3. Each
MUST fail against the current HEAD of `~/Projects/leadv2` main and pass after your fix. Run the
suite both ways and paste both outputs; a test that passes in both directions is treated as absent
and will be rejected.

## Do NOT
Do not weaken any currently-passing rejection. Do not touch the Codex runner suite (quota-locked
until 2026-08-08, fails on untouched main too). Do not rebase.

## Return
`PASS|FAIL|BLOCKED` + commit sha + both suite runs verbatim + the before/after run of each new test.
Commit in the lane before you finish.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-7b4c60ab" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.