
---

## LEAD NOTE — do NOT edit `tests/run-all.sh` in this lane

This lane was refused once with `writeset_conflict`: lane `D4-NO-PATH-LOSES-WORK-01` holds
`tests/run-all.sh`, because every lane that adds a suite needs a row in the same
`EXTRA_SUITE_MAP` table. The refusal is CORRECT — two lanes editing one table produce a merge
conflict at best and a silently dropped row at worst.

So, for this lane only:

- **Do not touch `tests/run-all.sh`.** It is outside your declared write set and the dispatcher
  will refuse you again if you add it.
- Instead, put the exact row you need in your report, verbatim and ready to paste — the pattern it
  must match, the suite path it maps to, and the line it belongs after. The lead lands it once the
  file is free.
- Your CI-selection claim then reads honestly: *"the suite exists and is green; its
  `EXTRA_SUITE_MAP` row is specified in this report and is NOT yet landed, so CI does not select it
  yet."* Do not write that CI selects it. A row that is not in the file does not select anything,
  and claiming otherwise is the exact lying-green shape this wave exists to remove.

Everything else in this brief stands unchanged.
