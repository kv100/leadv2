# PHASES-ARE-THE-ONLY-PATH-01 — round 9 (plugin repo ~/Projects/leadv2)

Lane `d4d014e1`, HEAD `0ff871f`. Do not rebase. Baselines to preserve:
`test-phase-precondition.sh` = 61/0, `test-routing-enforcement-p1.sh` = 8/8 from BOTH the main repo
root and inside a lane worktree.

Round 8's B1 fix (adopted-marker + `guard_token`) is good work and closes the two attacks it names.
One hole remains, and it is the same class the whole B1 chain exists to close.

## R1 — the guard token is not bound to the diff it vouches for
`leadv2-phase-record.sh:494-499`:
```
if has_tokens:
    gt = obj.get("guard_token", "")
    if not gt or gt not in valid_tokens:
        continue
```
`valid_tokens` is the flat set of every token ever minted for this repo slug
(`${CACHE_BASE}/code-review-provenance/<slug>.tokens`, written by `_review_tokens_file` /
`atomic_review_check_and_record`). Membership is the only test — nothing ties a token to the
`diff_hash` of the row carrying it.

Consequence, and it needs no determined attacker: a build worker reads the tokens file (it is a
plain file in the same cache tree the worker can already read), copies ANY token minted by ANY
earlier legitimate review of this repo, and appends a row with **its own** `diff_hash`, an
allowlisted `reviewer`, and that stolen token. Review phase passes. In any real repo at least one
prior review exists, so the precondition is always met. This is two commands, and it defeats the
stated bar: *a build worker cannot satisfy its own review phase from inside its own run.*

**First: reproduce it.** Build the repro before you fix anything, and paste its output in your
report. If it does NOT reproduce, say so with evidence and stop — do not "fix" a hole you could not
demonstrate.

**Then fix by binding the token to the diff.** The token minted by
`atomic_review_check_and_record` must only be valid for the diff_hash it was minted for. Options:
store `<diff_hash> <token>` pairs in the provenance file and require BOTH to match the row; or mint
the token as a keyed digest over the diff_hash with a per-repo secret kept outside the ledger dir.
Pick one, implement it, and state plainly in your report what it stops and what it does not — do
not claim unforgeability.

Keep round 8's adopted-marker behaviour intact: sidecar absent after adoption must still be tamper.

## Tests
- Stolen-token forgery: row with this lane's diff_hash + allowlisted reviewer + a token minted for a
  DIFFERENT diff_hash ⇒ review NOT satisfied. Must FAIL against `0ff871f`.
- Legitimate `record-review` end-to-end ⇒ review satisfied. Must still pass.
- All existing forgery rejections keep rejecting.

## Do NOT
Do not weaken anything currently passing. Do not touch the Codex runner suite (quota-locked until
2026-08-08, fails on untouched main too). Do not rebase.

## Write set
`plugins/leadv2/scripts/leadv2-phase-record.sh`, `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
`plugins/leadv2/scripts/tests/test-phase-precondition.sh`.

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit sha + the repro output (before fix) + raw output of both
suites, and the new test's run against `0ff871f` showing it fails there. Commit before you finish.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-73fdf110" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.