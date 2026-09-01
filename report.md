# Report — PROMISE-GUARD-TURN-IT-ON-01

## What was done

1. **Flip (Critical-2).** `plugins/leadv2/hooks/leadv2-promise-guard.sh` now defaults
   `LEADV2_PROMISE_GUARD_BLOCK` to `1`. Blocking applies in every adopted repo once the
   plugin-cache copy is refreshed (hook-cache rule: `claude plugin update` no-ops on
   version-unchanged directory sources — the cache file must be copied, sessions
   restarted). One-step rollback: `LEADV2_PROMISE_GUARD_BLOCK=0`.
2. **Classified-only blocking (Critical-1).** A `verdict=fired` row blocks only when
   `primary_promise_kind` is set; unclassified fired rows get the new journal field
   `block_decision=no` and do not block. `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED=1`
   restores old (block-on-unclassified) behaviour in one step.
   **Design deviation from the first draft:** the draft set unclassified verdicts to
   `suppressed_action` to keep them silent — that would have drained the fired bucket
   (402 of 423 fired rows were unclassified) that the taxonomy-widening evidence and the
   GO-condition query read. Instead `verdict` keeps its pre-flip semantics (fired =
   promise unkept) and blocking is decided by the separate `block_decision` field.
3. **Taxonomy widened (Critical-3)** from the 425 unclassified fired rows in the real
   journal (read-only query; no test ever wrote to it):
   - promise `write` += `перепиш|чин|обнов|\b(беру|берусь)\b` — e.g. «Берусь за третье —
     контракт prepass» (96 rows, the dominant shape), «Сейчас перепишу регэксп»,
     «Сейчас обновлю фикстуры», «Чиню постраничную выборку Calendly»;
   - promise `commit` += `мерж|мердж|merge`; action `commit` += `git merge` —
     «Сейчас смерджу ветку», «Начинаю с мержа fix/...» (no invented kinds; every added
     promise shape has a modelled action that can keep it);
   - **deliberately not added:** `подним-` («Сейчас поднимаю наблюдателя», server/watcher
     startup — no modelled action keeps it, it would block forever); the «идут» recap
     family (descriptive text, extractor false positives); conditional promises
     («Как придут — сразу с цифрами»); «I'll do my best to assist you» (10 rows, not work).

## Test-assertion changes, stated openly

`test-promise-guard-morphology.sh` and `test-promise-action-binding.sh` were RED under
the classified gate because they asserted unclassified promises fire. The first draft
flipped 8 morphology cases + `case_promise_only` to SILENT. This session then widened the
taxonomy, which re-classifies 6 of those 8 shapes plus «Берусь за...» — so their
assertions went **back to FIRED**:

- back to FIRED (now classified, unkept): `case_escape_chinyu`, `case_leading_verb`
  (мерджа→commit), `case_r1_08_beru`, `case_r3_perepishu`, `case_r3_obnovlyu`,
  `case_r3_smerdzhu`, `case_promise_only`;
- stay SILENT (unclassified, no action-side kind): `case_known_verb`,
  `case_r1_11_podnimayu` — «Сейчас поднимаю наблюдателя»;
- `case_action_then_promise` / `case_promise_then_action`: fixture changed from the bare
  `act` token (git commit, commit-kind) to `write_act` (Edit) — the promise side
  («Берусь за...») is now a *write-kind* promise, and the kind-scoped binding is kept by
  a same-kind action. With the old fixture the cases fire — which is the 2026-08-21
  escape (commit work, then «Берусь за третье», stop) being caught, not a regression.

## New suite

`plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh` — all 7 acceptance
cases against the REAL hook with sandboxed `HOME` and a real-journal-unchanged control:
classified unkept blocks; classified kept silent; unclassified unkept silent + journal
row `verdict=fired, block_decision=no, kind=null`; same + `BLOCK_UNCLASSIFIED=1` blocks;
`BLOCK=0` never blocks (and still journals `block_decision=yes`); past-tense sha report
silent with no row; two Stops in one turn block at most once.

**Mutation proof:** replacing `BLOCK_DECISION="no"` with `BLOCK_DECISION="yes"` (removes
the classified gate) makes the suite RED — case 3 fails with
`FAIL: 3 unclassified promise does not block`. Reverted byte-identical; suite green again.

## Test results

- `test-promise-guard-classified-block.sh`: 8 passed, 0 failed (rc=0)
- `test-promise-action-binding.sh`: 2 passed(red->green), 0 failed, 8 green-pre-fix
- `test-promise-guard-morphology.sh`: 12 passed(red->green), 0 failed, 29 green-pre-fix
- All three ran with sandboxed HOME; each control asserts the real
  `~/.claude/leadv2-promise-guard.jsonl` was unchanged (1957 lines before and after).

## EXTRA_SUITE_MAP

Added `leadv2-promise-guard.sh:plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh`
to `tests/run-all.sh`; selection proven with `--scope changed` (see lane self-check output).

## Notes / anomalies

- A parallel session salvage-committed this lane mid-flight (`fa1fd31`), which also
  duplicated the ledger row and added an unused `plugins/leadv2/scripts/tests/test-lib.sh`
  (not referenced by any suite; only `test-red-first-gate.sh` writes its own fixture copy
  of that name into a sandbox). Ledger row deduped; `test-lib.sh` left as committed — not
  in this lane's write set.
- `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-*/phases.d/*.yaml` and two task
  journals are dirty in the worktree from other lanes — not staged by this lane.
- Post-salvage uncommitted in this commit: binding-suite `write_act` fixture fix,
  `tests/run-all.sh` EXTRA_SUITE_MAP row, ledger dedupe/amendment, this report.
