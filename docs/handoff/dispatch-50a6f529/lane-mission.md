# PHASES-ARE-THE-ONLY-PATH-01 — round 10 (plugin repo ~/Projects/leadv2)

Lane `d4d014e1`, HEAD `79ba332`. Do not rebase. Baselines: `test-phase-precondition.sh` = 64/0,
`test-routing-enforcement-p1.sh` = 8/8 from both the main repo root and inside a lane worktree.

Round 9's FIX is correct and the vulnerability repro in its report is real. Its TEST is not.

## R1 — G7h passes against the pre-fix code, for the wrong reason
`tests/test-phase-precondition.sh:735`:
```
G7H_STOLEN_TOKEN="$(awk '{print $2}' "${G7_CACHE}/code-review-provenance/${G7_SLUG}.tokens" | head -1)"
```
Verified by the lead: restoring `leadv2-phase-record.sh` and `leadv2-dispatch-code.sh` from `0ff871f`
(the exact code the stolen-token forgery works against) and running THIS test file still gives
`[PHASE-PRECONDITION] pass=64 fail=0`. G7h does not discriminate.

Why: under `0ff871f` the tokens file holds one bare token per line, so `$2` is EMPTY. The forged row
carries `"guard_token":""`, the old check's `if not gt: continue` rejects it, and the test sees the
forgery blocked — by the empty field, not by any binding. Under the new format `$2` happens to be the
token, so it passes there too. A test that passes in both directions is treated as absent.

Fix: extract the token in a way that yields the REAL token under both formats — `awk '{print $NF}'`
is the obvious candidate (last field: the bare token in the old format, the token half of the pair in
the new one). Then the test must fail against `0ff871f` (forgery succeeds ⇒ review satisfied ⇒
assertion fails) and pass against `79ba332`.

**Prove both runs.** Restore the two scripts from `0ff871f`, run the suite, show G7h failing; restore
HEAD, run again, show 64/0. Do not commit with the scripts reverted.

While you are there, check G7h-2 (the positive control) the same way and say whether it
discriminates or is decorative.

## R2 — document the residual hole honestly, in the code
Round 9's own report states it: a process that can WRITE to `${CACHE_BASE}/code-review-provenance/`
can append a matching `<diff_hash> <token>` pair and forge again. Every build worker runs as the same
Unix user as the verifier, so there is no filesystem boundary between them — this cannot be closed by
file layout alone, only by an authority outside the process (or by making a forged row visible in a
diff a human reads).

Add this to the proof-level doc-block in `leadv2-phase-record.sh` as plain text: what the review
proof DOES establish (a matching row exists that was minted for this exact diff by the guarded write
path), and what it does NOT (it does not stop a process with write access to the provenance dir).
No new mechanism in this round — just stop the code from reading as if the property were stronger
than it is.

## Do NOT
Do not weaken any passing rejection. Do not touch the Codex runner suite. Do not rebase.

## Write set
`plugins/leadv2/scripts/tests/test-phase-precondition.sh`,
`plugins/leadv2/scripts/leadv2-phase-record.sh` (doc-block only).

## Return
`PASS|FAIL|BLOCKED` + commit sha + the two suite runs required by R1, verbatim. Commit before you
finish.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-50a6f529" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.