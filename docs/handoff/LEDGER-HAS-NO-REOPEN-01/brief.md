# LEDGER-HAS-NO-REOPEN-01 — a lane whose worker died can never be re-dispatched

**Class:** Standard. **Repo:** leadv2 plugin. **Filed:** 2026-09-02 by the persona-engine lead.

## Symptom
`leadv2-dispatch-code.sh` refuses `dispatch_refused reason=duplicate_task_signature` for a task whose
every previous arm is dead, and there is **no supported way to clear it**:
- `--force` is a documented no-op for dedup (`dispatch_override_rejected reason=force_not_permitted`).
- `leadv2-dispatch-ledger.sh write-terminal <sig8> <task> dead <cause>` succeeds and
  `state <sig8>` then prints `dead` — the dispatcher still refuses.
- Only deleting the task's rows from `~/.claude/cache/dispatch-ledger/leadv2.jsonl` by hand unblocks it
  (done today, backup `leadv2.jsonl.bak-0957`, 10 rows dropped).
- Dispatching under a NEW task id is not a workaround: it routes a fix-round through the product
  intake and parks with `architect prepass produced no design for product task=<sig> after 2 attempts`.

Live evidence 2026-09-02: FABLE-THINK-TIER-01 was refused seven times in a row across four causes;
this was the last one, and it cost the most attempts. The other three are in
`STALE-ROW-STARTING-GRACE-01`.

## Required
1. A supported reopen: `leadv2-dispatch-ledger.sh reopen <sig8> --reason "<why>"` that appends a row
   the dedup honours, or make the dedup honour an existing terminal state (`dead` / `parked` /
   `no_work`) — a task whose last row is terminal is by definition not double-spending.
2. The refusal must print the remedy (which command clears it) the way the phase-precondition refusal
   already prints its `remedy:` line. Today the message is a dead end.
3. `write-terminal` must fail loud when the key it writes is not the key the dedup reads (sig8 vs full
   sig) — today it silently succeeds and changes nothing the dispatcher sees.
4. Suite: a task with a confirmed row + a terminal row must dispatch; without the terminal row it must
   refuse. Negative control in a mktemp ledger; EXTRA_SUITE_MAP row proven with `--scope changed`.

## Evidence
`dispatch-FABLE-THINK-TIER-01-r7{g,h,i,j,k,l}.log` in the 2026-09-02 scratchpad; dispatch-code.sh
~:7200-7225 (`ANTI-DOUBLE-SPEND` block); persona-engine `docs/leadv2/open-threads.md` 2026-09-02 entries.
