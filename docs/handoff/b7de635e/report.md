# PLUGIN-PREPASS-HANGS-01 parity — lane report (b7de635e, 2026-09-10)

Mission: `test PLUGIN-PREPASS-HANGS-01 parity: slow-but-legitimate architect work`

## Finding: the parity guard was silently red (suite-vs-production drift)

The regression suite `plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh`
guards the two-population finding: architect prepass kills slow-but-legitimate
architect work (`status=failed reason=timeout rc=124`) rather than a hang.

Its check-1 dispatched with `--writes "a.txt"` — a single-path writeset. The
`provably_one_file` admission shortcut
(`leadv2-dispatch-code.sh:5673-5681`, landed in `0f18056a` AFTER the suite was
written in `9979dd9b`) skips the prepass entirely when the writeset has exactly
one entry, so the dispatch emitted
`architect_prepass status=skipped reason=provably_one_file` and the asserted
line could never appear. The suite went red at that commit and stayed red
unseen: `a2b08cd1` (SUITE-SELECTION-COVERS-140-OF-390-01) proved no
change-scoped run ever selected this suite. The 2026-09-05 journal rows for
this task id in the main checkout confirm the skip fired live:
`architect_prepass task=b7de635e status=skipped reason=provably_one_file writes=a.txt`.

The prepass mechanism itself is intact: the budget default is still 420s
(`leadv2-dispatch-code.sh:750`), the kill emits
`status=failed reason=${_pp_cls} rc=${rc}` at `:5857` (`_pp_cls=timeout`,
`rc=124` on budget expiry).

## Fix (one file, canonical)

`test-prepass-repo-parity.sh`: `--writes "a.txt"` → `--writes "a.txt,b.txt"`
(two entries ⇒ count≠1 ⇒ prepass runs) + a comment stating the constraint and
its origin. The mission string is byte-unchanged — it hashes to the sig8 the
historical journal rows were written under.

## Verification (raw output)

Red before the fix:

```
[FAIL] check1: expected 'architect_prepass status=failed reason=timeout rc=124' in dispatch output
[leadv2-dispatch-code] architect_prepass task=b7de635e status=skipped reason=provably_one_file writes=a.txt
...
[ok] check2: historical journal fixtures match the population split (where present)
=== 1 check(s) FAILED ===
SUITE_RC=1
```

Green after the fix (`bash -n` → `SYNTAX_OK` first):

```
[ok] check1: legitimate work exceeding ARCHITECT_PREPASS_TIMEOUT_SEC reproduces rc=124 (matches cd219000/85d0e45e mechanism)
[ok] check2: historical journal fixtures match the population split (where present)
=== all checks passed ===
SUITE_RC=0
```

check1's assertion is a byte-exact grep
(`architect_prepass .*status=failed reason=timeout rc=124`) over the dispatch
log, so the [ok] line is the mechanism proof — the stub architect's legitimate
6s workload exceeded the 2s test budget and was killed rc=124, exactly the
cd219000/85d0e45e mechanism.

Changed-scope runner: `bash tests/run-all.sh --scope changed` selected 2 of 95
suites (base=main@6099b6fc, 1 changed file — this suite; the report is not
mapped), fanned to 5 executions across 4 shards:
`run-all: 5 passed, 0 failed, scope=changed`, exited 0, including
`[PASS] plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh`.

## Side observations

- Same-id lock collision: this live lane and the suite's check-1 dispatch share
  the sig8 `b7de635e` (same mission string). After the prepass assertion is
  satisfied, the suite's dispatch tail may see `glm_refused_lock_busy` from the
  live lane's lock — this does not affect check-1, and the dispatch's
  active-lane release has an ownership guard (`not_owner_row_intact`) so the
  suite cannot release the live lane's row (observed on 2026-09-05).
- The 2026-09-05 stub-run leak (journal rows with `LABEL=test SESSION_ID=test`
  handles under the real tree) pre-dates this lane and is unchanged by it.
