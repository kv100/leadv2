# GUARD-CENSUS-IS-WRONG-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GUARD-CENSUS-IS-WRONG-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-guard-census.sh,plugins/leadv2/hooks/lib/leadv2-guard-verdict.sh,plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh,plugins/leadv2/hooks/*.sh,plugins/leadv2/scripts/tests/test-guard-census.sh,plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh,plugins/leadv2/scripts/tests/fixtures/guards/**,tests/run-all.sh,docs/handoff/GUARD-CENSUS-IS-WRONG-01/
Continue from the existing commits on this branch (`git log main..HEAD`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). Never commit anything under
`docs/leadv2/` (`git checkout -- docs/leadv2` before each commit; commit by explicit pathspecs). Round 1
had NO `report.md` — brief step 6 was skipped; write it this round and `git add -f` it. An uncommitted
exit is a failed round.

## Review verdict on round 1 (reviewer opus, `review-opus.md`) — FAIL, high=2
1. `hooks/leadv2-bash-pre-dispatch.sh:98` — verdict-kind infers a "log" fire from ANY stdout/stderr
   bytes, so a guard that prints a pass/skip diagnostic on stderr and exits 0 is permanently recorded
   as `fires-log-only`. The census's `fired` column is therefore wrong for exactly the quiet-pass guards.
2. `hooks/leadv2-bash-pre-dispatch.sh:94` — every Bash tool call appends ≥4 rows to an unrotated
   `journal.tsv` that the census re-scans in full 3× per guard (282 full scans on the live tree); no
   rotation or cap exists anywhere.
Also (reviewer, verified): no suite invokes `leadv2-bash-pre-dispatch.sh` at all — every new line in
the hook is untested, including `LEADV2_GUARD_VERDICT_DIR` handling and record persistence.

## Do
1. Verdict kind = the guard's CONTRACT, not its chatter: exit 2 / `decision:block` → `block`;
   exit 0 with a `hookSpecificOutput`/`additionalContext` JSON on stdout → `inject`; exit 0 with only
   stderr text → `pass` (not a fire). Record `pass` separately so "ran but did nothing" is visible and
   distinct from `fires-log-only`.
2. Journal: cap and rotate (`journal.tsv` ≤ N rows or ≤ 1 MB, rotate to `.1`, keep 2), and have the
   census read it ONCE per run into memory (no per-guard rescans). Paste before/after: rows appended per
   Bash call, scans per census run.
3. New suite `test-bash-pre-dispatch-verdict.sh` that runs the REAL hook with a fake
   `LEADV2_GUARD_VERDICT_DIR` and stub guards: (a) exit-0 + stderr text → recorded `pass`, never a fire;
   (b) exit 2 → `block`; (c) exit 0 + JSON → `inject`; (d) rotation triggers at the cap and the census
   still sees the rotated rows; (e) the record survives to the census table (`fired`/`last-fired-days`).
4. Mutation negative controls, RUN and paste red: (a) restore "any bytes = log fire" → case (a) red;
   (b) remove rotation → case (d) red. Revert both.
5. Register both suites in `tests/run-all.sh` EXTRA_SUITE_MAP (`leadv2-bash-pre-dispatch` stem);
   `tests/run-all.sh --scope changed` → paste the selected-suite line;
   `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh <suite>` for both → paste FALSIFIABLE.
6. `report.md`: round-1 deliverables that were never reported (the live-tree census re-run with the full
   table + header, the `default` / `last-fired-days` columns, the fixtures for blocking guards) PLUS
   "## Round 2 evidence". The census table on the live tree is the founder-facing deliverable — it must
   be in the report, not only in a `census-*.txt` side file.
