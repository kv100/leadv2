verdict: APPROVE
next_action: review_round_2

# FLEET-RUNTIME-UNATTENDED-01 — developer full report (round 2)

Lane worktree `.claude/worktrees/583d804d01e5` @ base `fa27042a`. Round 1 (commits `550b4389`,
`85475b83`) was reviewed and FAILED: `docs/handoff/dispatch-c7527bac-review/critic.full.md`,
verdict FAIL, critical=2 high=5 medium=7 low=4. This dispatch fixed every finding. Full narrative,
per-finding mapping, and every pasted command lives in
`docs/handoff/FLEET-RUNTIME-UNATTENDED-01/report.md`'s new "Round 2" section (appended, round-1
content left intact above it for its still-valid design rationale) — this file is the lead-facing
summary of that section.

## Findings fixed, one line each (full detail + evidence in report.md round-2 section)

**Critical**
- C1: round-1's C1-required scenarios were only manually smoke-tested. Codified into the suite as
  Group E (state contract: 5-line `read`, unknown-field rc=2, lock-steal) and Group F (runner
  self-stops: `no_landing_streak`, `no_arm`, `quota_window`, degrade-to-glm) and Group G (guard
  reap/reap_refused/stall). Judgment call: adapted C1(b)'s literal wording to M1's fixed semantics
  (quota_window reserved for an actual quota refusal, not any unusable arm) — stated explicitly in
  the report rather than silently diverging from the review text.
- C2: mutation markers previously proved only that a comment string existed, not that the
  mutation defeats the property. Added Group H — applies each of the 3 sed patches to a scratch
  copy and asserts the relevant scenario goes RED — plus registered all 3 in
  `tests/mutations/catalog.yaml`.

**High** — H1 (flap: never write `alive` until every self-stop check passes for the iteration),
H2 (`--lane-cmd` renders `Environment=LEADV2_FLEET_LANE_CMD=`, `install` warns loudly when
omitted), H3 (`--cap` forwarded to the pluggable lane hook as `LEADV2_FLEET_CAP` rather than
implemented as N-way concurrency — bash 3.2 has no `wait -n`), H4 (`git worktree remove` refusal
now records `reap_refused` and leaves the tree untouched — the `rm -rf` fallback is gone), H5
(runner touches `<worktree>/.fleet-terminal` on lane completion via an optional `FLEET_WORKTREE=`
stdout contract, so the guard's reap step is no longer dead code).

**Medium** — M1/M2 (`fleet_arm_reason`/`fleet_no_arm_reasons`/`fleet_stop_kind_for_no_arm` in
`leadv2-fleet-lib.sh` distinguish `credentials_missing`/`auth_expired`/`quota_exhausted`/
`key_missing`), M3 (state file's `day` field rolls `landed_today`/`rows_filed_today` to 0 at UTC
midnight), M4 (unit args quoted, `Wants=network-online.target` added), M5 (Group B's env vars
scoped via prefix-assignment per `mini_systemd_once` call instead of a suite-wide `export`), M6
(guard's stall check reads the worktree root's own mtime instead of walking every file with
`find`), M7 (mkdir-lock breaks on a provably-dead pid, not age alone; 30s age fallback kept only
for a pid-less lock dir).

**Low** — L1 (`grep -c` zero-match empty-string fixed with `${var:-0}`), L2 (removed a fixed-line
`sed -n '2,10p'` slice in Group B that H2's optional `Environment=` line silently invalidated —
this is what actually broke Group B during round-2 verification, see below), L3 (report already
stated the mini-systemd stub boundary; restated for round 2's own record), L4 (the apparent
lane-vs-base deletion is a non-ancestor diff artifact, confirmed via `git merge-base
--is-ancestor c5215469 HEAD` = false; not a regression, no rebase attempted).

## Two regressions caught and fixed while verifying the round-2 suite (not in the review, found here)

1. Adding the `# c1-mut: restart policy passthrough` marker onto the live `Restart=${4}` line in
   `leadv2-fleet-unit.sh` means the rendered unit's `Restart=` value now carries a trailing
   comment in production output (`Restart=always # c1-mut: ...`). This broke both the suite's
   exact-match `grep -q '^Restart=always$'` and `mini_systemd_once`'s `[[ "${restart}" == "always"
   ]]` comparison. Fixed: suite grep loosened to a prefix match; `mini_systemd_once` strips a
   trailing `# ...` comment before comparing.
2. H2's `--lane-cmd`-conditional `Environment=` line shifts every subsequent unit line down by one
   whenever `--lane-cmd` is omitted. Group B's pre-existing `sed -n '2,10p'` slice (written before
   H2 existed) silently sliced past `ExecStart=` entirely in that case, producing an empty
   `ExecStart` and a "process exited before kill — setup bug" false failure. This is exactly L2's
   finding; fixed by removing the slice (unnecessary — `mini_systemd_once` already greps with
   `head -1` on the full output).

## Suite evidence

29/29 green (up from round 1's 10/10), including 3/3 mutation controls RED (Group H) and 3/3
mutation-target markers present (Group 0). Full pasted run, per-group breakdown, and the
canonical `leadv2-mutation-control.sh` artifact are in report.md's round-2 section.

## Self-check

`bash -n` clean on all 6 changed `.sh` files; `tests/mutations/catalog.yaml` parses as valid YAML
(75 entries, 3 new). No Python files changed. `tests/run-all.sh --scope changed` was run; its
result is in report.md.

## Off-limits compliance (unchanged from round 1)

No file in `leadv2-dispatch-code.sh` / `leadv2-dispatch-product-close.sh` /
`leadv2-active-registry.sh` was read, grepped, or written. `grep -n '\bclaude\b'` across the three
non-runner fleet scripts still returns zero matches (unchanged from round 1 — the round-2 diff
added no new `claude` invocations).

DELIVERABLE_COMPLETE
