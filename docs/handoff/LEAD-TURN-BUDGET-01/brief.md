# LEAD-TURN-BUDGET-01 — the lead spends ≤3 tool calls per lane event; the plugin does the rest

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/leadv2-fix-round-brief.sh,plugins/leadv2/scripts/leadv2-lanes-snapshot.sh,plugins/leadv2/scripts/leadv2-lane-close.sh,plugins/leadv2/hooks/leadv2-lead-turn-budget.sh,plugins/leadv2/hooks/hooks.json,plugins/leadv2/skills/leadv2/SKILL.md,plugins/leadv2/docs/single-lead-pulse.md,plugins/leadv2/scripts/tests/test-lead-turn-budget.sh,tests/run-all.sh,docs/handoff/LEAD-TURN-BUDGET-01/
Class: Heavy — run the real Phase-2 plan (architect + Codex + critic) before building. Run suites with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST. Never commit `docs/leadv2/`, `docs/LEAD_V2_STATE.md`,
`docs/handoff/dispatch-nw*`; commit by LANE_WRITES pathspecs. English review-facing text.

## Measured (lead session ad4d4b81, 2026-09-01/02, founder order to fix)
- 689 tool calls in one lead session (579 Bash, 49 Write, 35 Monitor), transcript 10 MB / 8,352 lines.
- 8–12 lead tool calls per lane round: check worker → clean runtime files → `git merge main` →
  resolve `tests/run-all.sh` EXTRA_SUITE_MAP conflict → produce diff → `leadv2-review-run.sh` →
  read verdict → hand-write `fix-round-N.md` → commit → re-dispatch → read result → arm Monitor.
- All of that duplicates `leadv2-dispatch-product-close.sh`, the plugin's own detached close gate
  (waits for the worker, resumes died-with-work once, runs e2e + review, writes the terminal). The lead
  bypassed it because it piped every dispatch through `grep … | head -N`, which SIGPIPE-kills the
  dispatcher right after `worker_spawned`, so the close gate never ran and the lead did its job by hand.
- The founder's standing format for status is a table (memory `feedback-status-as-markdown-table`);
  the lead re-derived it from 4–6 probes each time instead of one snapshot call.

## Do
1. **`leadv2-lane-close.sh <task-id>`** — one call that does the whole post-worker sequence the lead did
   by hand: restore runtime files from main (list shared with LAND-PATH-IS-BROKEN-01's
   `lib/leadv2-land.sh` if present, else inline here and referenced from there), `git merge main` with
   the EXTRA_SUITE_MAP union resolver (both sides' rows, one closing quote), commit, committed-tree
   diff (`git diff main HEAD`), `leadv2-review-run.sh`, and print ONE summary line:
   `lane_close task=… review=pass|fail high=N critical=N findings=docs/handoff/…/review-findings.json`.
   `product-close` calls this instead of its own partial sequence (or the two share one lib —
   pick one, no duplicate logic).
2. **`leadv2-fix-round-brief.sh <task-id>`** — generates `docs/handoff/<id>/fix-round-<N+1>.md` from
   `review-findings.json` + the previous brief's LANE_WRITES + the standing lane rules (merge main first,
   never commit runtime files, English sentinels, mutation control via the runner when present,
   FALSIFIABLE + `--scope changed` lines, "## Round N evidence"). One finding → one numbered Do step
   with the file:line and the reviewer's reproduction. The lead edits at most the LANE_WRITES line
   and adds one sentence; the script commits with `git add -f` and prints the path.
3. **Dispatch contract**: `leadv2-dispatch-code.sh` writes its full log to
   `docs/leadv2/tasks/<id>/dispatch-<attempt>.log` itself (no lead redirection needed) and prints only
   the two lines the lead reads (`worker_spawned …` and the log path). Document in `SKILL.md` and
   `single-lead-pulse.md`: dispatch always `run_in_background`, never through a pipe; the ONE watcher
   per lane is `Monitor: grep -m1 "dispatch_terminal task=<sig8>" <that log>`; on wake the lead reads
   `review-findings.json` (never a diff, never a review-*.md), runs (2), re-dispatches.
4. **`leadv2-lanes-snapshot.sh --founder`** prints the founder table in ONE call, exactly:
   `В работе | Линия | Кто | Коммитов сверх main | Оценка до конца` + `Не начато | Линия | Оценка` +
   `Итого до пустой очереди … Главный риск …`, with provider from the registry/run meta, commits from
   `git rev-list --count main..HEAD` per worktree, ETA from the phase (build/review/land) × class
   table. The lead pastes it verbatim.
5. **Budget hook** `hooks/leadv2-lead-turn-budget.sh` (PreToolUse, lead sessions only): counts tool
   calls since the last lane event (a `dispatch_terminal` / Monitor wake) and after 3 emits an
   advisory (`LEAD-TURN-BUDGET: 4th call on lane X — use lane-close / fix-round-brief / snapshot`);
   `LEADV2_LEAD_TURN_DENY_AT` (default never) hard-stops. Never blocks founder-question answers.
6. Suite `test-lead-turn-budget.sh`: (a) lane-close on a fixture lane with a run-all conflict →
   union, committed diff, summary line; (b) fix-round-brief from a fixture findings.json → file with
   one Do step per High, LANE_WRITES carried over; (c) snapshot prints the three founder blocks; (d)
   hook advisory fires on the 4th call and not on the 3rd. Mutation negative controls, RUN and paste
   red: drop the union resolver → (a) red; drop the High→step loop → (b) red. Revert. Register in
   `tests/run-all.sh`; paste `--scope changed` + FALSIFIABLE.
7. `report.md`: before/after tool-call count for one lane round (measure on a real lane: dispatch →
   terminal → fix brief → re-dispatch), the exact lead procedure in ≤10 lines, and what still needs
   the lead's judgment (class, Gate-1, refuting a reviewer, landing decision).

## Do NOT
- Do not remove the model review or weaken any gate; this changes WHO drives, not what is checked.
- Do not add lead narration; the pulse stays plugin-owned.
