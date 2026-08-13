# PHASES-ARE-THE-ONLY-PATH-01 — round 8 (plugin repo ~/Projects/leadv2)

Lane `d4d014e1`, HEAD `93cbfcd`. Do not rebase. Baselines to preserve:
`test-phase-precondition.sh` = 53/0, `test-routing-enforcement-p1.sh` = 8/8 from BOTH the main repo
root and inside a lane worktree, core-offline = 39 passed / 1 failed (the 1 is the Codex runner,
quota-locked until 2026-08-08, not ours — do not touch it).

Four blocking findings from an independent adversarial review, all live-reproduced. Full report with
exact repro commands: `docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/c4-review-r6.md` (in
~/Projects/persona-engine) — read B1..B4 there before writing code.

Threat model, unchanged and binding: we are NOT defeating a determined attacker and we are NOT
adding signing. The bar is **a build worker cannot satisfy its own review or deploy phase from
inside its own run.** All four findings breach that bar.

## B1 — CRITICAL. `rm` one file and review-forgery works again
`leadv2-phase-record.sh:405-467`, `_verify_artifact` review case, sidecar-absent branch at :420-439.
When `code-review-ledger/<slug>.jsonl.rows` is absent, the code takes a "legacy ledger → accept"
branch unconditionally. Deleting the sidecar is a permanent, repeatable bypass: write a ledger row
with the correct `diff_hash` and `"reviewer":"codex"`, delete the sidecar, and the review phase
passes. Forging both files consistently works too — the row-count check compares two
attacker-writable files against each other.

Fix so that sidecar-absent cannot default to accept. The report suggests either a persisted
"sidecar adopted" marker outside the ledger dir (absent-after-adopted ⇒ tamper), or a per-invocation
token minted by `atomic_review_check_and_record` under its own flock and checked back by
`_verify_artifact` — something the guard generates that the caller cannot supply on the CLI. Choose
one, implement it, and state in your report exactly what it stops and what it does not.

## B2 — HIGH. `deploy` is self-satisfiable
`leadv2-phase-record.sh:475-483` accepts any commit that is an ancestor of `origin/main` — including
`origin/main`'s own tip, which requires zero work from the lane. `build` three cases above already
does this correctly via `_resolve_lane_diff_base "$sig8"`. Make `deploy` require the commit to be a
DESCENDANT of the lane's own start-sha, using that same base resolution.
Note: `tests/test-phase-precondition.sh:676-698` (G9) currently encodes the gap as the intended pass
case — its comment says "ancestor of origin/main = HEAD → ancestor of itself". Fix the test too.

## B3 — HIGH. The anti-self-forging test never executes the code it tests
`tests/test-phase-precondition.sh:588-608` (G7d): `git worktree add ... main` always fails rc=128
because the primary checkout is already on `main`; `2>/dev/null` swallows it, the `cd` then fails,
and the `&&`-chained `record-review` never runs. The assertion passes identically whether the guard
is correct or deleted. Use `git worktree add -b <throwaway-branch>`, and assert on the
`review_record_refused` journal line, not merely a nonzero rc.

## B4 — HIGH, pre-existing. Infra trouble silently turns warn into enforce
`leadv2-dispatch-code.sh:1553-1585`: the `*)` catch-all returns 1 unconditionally, ignoring `$mode`.
With a valid `.claude/leadv2-overrides/phases.yaml` present and `python3` missing from PATH,
`leadv2-phase-record.sh assert` exits 127, and warn mode becomes a hard repo-wide refusal with no
journal line saying why. Any exit outside {0,3,4} has the same blast radius. In warn mode an
unexpected exit must journal a distinct line and PROCEED. In enforce mode it may refuse, but must
say which exit code caused it.

## Do NOT
Do not weaken any currently-passing forgery rejection. Do not touch the Codex runner suite. Do not
rebase. Do not disable `REVIEW_RECORDER_GUARD` by default.

## Write set
`plugins/leadv2/scripts/leadv2-phase-record.sh`, `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
`plugins/leadv2/scripts/tests/test-phase-precondition.sh`.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit sha + raw output of `test-phase-precondition.sh` and
`test-routing-enforcement-p1.sh`. Every new test must FAIL against `93cbfcd` and pass after — show
both runs. Re-run the three attack repros from B1 verbatim and paste their output. Commit before you
finish; four workers today ended with uncommitted work.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-641dd299" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.