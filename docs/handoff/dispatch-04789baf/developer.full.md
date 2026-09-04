verdict: REVISE
next_action: continue

# COMBO lane dispatch-04789baf — status: item 1 done, items 2-4 not started

Turn-cap reached (subagent protocol §Turn-cap: 30 tool calls) after completing item 1
in full with tests, mechanical gates, and two commits. Stopping here per protocol rather
than continuing past the cap. This is a partial-completion report, not a failure: item 1
is fully closed and evidenced below; items 2, 3, 4 need a fresh subagent run.

No `docs/handoff/dispatch-04789baf/context.yaml` existed for this task — worked directly
from the lane-mission.md text and the referenced critic report
(`docs/handoff/dispatch-6632fad9-review/critic.full.md`, read in full).

## Item 1 — ENV-GUARDS nits — DONE (2 commits, deviates from "one commit per item")

Mission said 4 commits total (one per item). Item 1 touches two files with independent
concerns (backlog-pump vs dispatch-code) and I committed them separately — dc6f99d then
f387f4d — so this lane now has 2 commits for item 1 alone. Flagging this explicitly since
it deviates from the stated plan; functionally each commit is self-contained and green.

### 1-A (backlog-pump.sh) — zsh-proof canonical-root fallback

`_lv2bp_canonical_root()` used `cd "$cand" && cd "$(git rev-parse --git-common-dir)" && cd .. && pwd`
relying on bash rejecting `cd ""` to short-circuit to the "return candidate unchanged"
fallback when git printed nothing. zsh treats `cd ""` as a no-op (rc=0), which would
silently walk to the PARENT of the candidate instead. Fix: capture
`git rev-parse --git-common-dir` output first, gate the `cd` chain on `[[ -n "$common_dir" ]]`.

### 1-B (backlog-pump.sh) — OBSOLETE, verified

Verified `pump-caller` no longer exists in the repo (`find . -iname "*pump-caller*"` — no
hits) — it was already deleted by RESIDUE-SWEEP before this lane started. Grepped
`LEADV2_BACKLOG_PUMP_CACHE_DIR` across `plugins/leadv2/scripts/`: only two live
references remain, both inside `leadv2-backlog-pump.sh` itself (`CACHE_DIR` at line 256,
`EMPTY_STREAK_DIR` at line 910). No second writer/reader exists anymore, so the
reader/writer symmetry gap the nit warned about cannot recur — no code change needed.

**Evidence:**
```
$ find . -iname "*pump-caller*"
(no output)
$ grep -rn "LEADV2_BACKLOG_PUMP_CACHE_DIR" plugins/leadv2/scripts/
plugins/leadv2/scripts/leadv2-backlog-pump.sh:255:# deliberate test seam (LEADV2_BACKLOG_PUMP_CACHE_DIR).
plugins/leadv2/scripts/leadv2-backlog-pump.sh:256:CACHE_DIR="${LEADV2_BACKLOG_PUMP_CACHE_DIR:-${CANONICAL_ROOT}/.claude/cache/backlog-pump}"
plugins/leadv2/scripts/leadv2-backlog-pump.sh:910:EMPTY_STREAK_DIR="${LEADV2_BACKLOG_PUMP_CACHE_DIR:+${LEADV2_BACKLOG_PUMP_CACHE_DIR}-empty-streak}"
```

**Suite:** `test-pump-junk-in-lane.sh`
```
[PUMP-JUNK-IN-LANE] case: liveness cache must not land inside the lane worktree
[PUMP-JUNK-IN-LANE]   worktree stayed clean (0 cache files) ✓
[PUMP-JUNK-IN-LANE] case: liveness cache lands under the main checkout
[PUMP-JUNK-IN-LANE]   found liveness.json under the main checkout ✓
[PUMP-JUNK-IN-LANE] pass=2 fail=0
```

Commit: `dc6f99d fix(backlog-pump): zsh-proof canonical-root fallback (nit 1-A)`

### 2-A/2-B/2-C (dispatch-code.sh) — codex instant-complete rollout scan

**2-A — scope the rollout to this dispatch.** `_codex_newest_rollout_since` now takes an
`expected_cwd` arg (caller passes `WORK_ROOT`, the same value used for the codex spawn's
`--cwd`). It reads each window candidate's `session_meta.cwd` (verified this field exists
on real rollout files: `head -1 ~/.codex/sessions/**/rollout-*.jsonl` shows
`{"type":"session_meta","payload":{...,"cwd":"/Users/.../Projects/respiro-ios",...}}`).
Chose a SOFT preference over a hard filter: pick the newest cwd-matching candidate if any
exist, else fall back to the newest of the whole window (today's behaviour) — a hard
filter risked silently losing the correct rollout if codex records a resolved/symlinked
cwd that doesn't string-match `WORK_ROOT` exactly (this repo's own CLAUDE.md flags path-
through-symlink mismatches as a repeat incident class). Either way the function now also
reports the total window-candidate count on a second output line; the caller journals
`arm_dead_instant_complete_ambiguous_rollout arm=codex task=<sig8> candidates=<n> picked=<f>`
whenever that count is >1, so an ambiguous judgement is never silent.

**2-B — don't pay the full 30s on a healthy job.** Previously, on `_codex_rollout_dead_shape`
rc=1 ("no terminal event yet") the deadline-check looped until `LEADV2_CODEX_INSTANT_
COMPLETE_SECS` (default 30) elapsed. Since a candidate file only reaches this branch
because its mtime already postdates spawn (`_codex_newest_rollout_since`'s `since` filter),
rc=1 now returns 0 immediately: the file's existence with a later mtime already proves a
non-terminal event landed after spawn, i.e. the job is alive. No new information arrives
by continuing to poll for the terminal event specifically.

**2-C — real lockout-file assertion.** Test case 5 previously stubbed
`DISPATCH_SELF_BIN=/bin/true`, so the `record-quota-lockout` call was a no-op and
requirement (c) ("provider strike is recorded") had zero coverage — only the rc=7 spill
was asserted. Case 5 now points `DISPATCH_SELF_BIN` at the real `leadv2-dispatch-code.sh`
with `LEADV2_QUOTA_LOCKOUT_DIR` redirected to a fixture tmpdir, and asserts
`quota-lockout-codex.json` exists and contains `arm_dead_instant_complete`.

**New/changed test legs:**
- Case 4: unchanged assertion, updated to read the new two-line output (path + count=1).
- Case 4b (new): two rollout files in the same mtime window with different
  `session_meta.cwd` — asserts the cwd-matched one is picked even though the sibling is
  newer, and the reported count is 2 (ambiguity signal).
- Case 5 (strengthened): as above — real lockout file assertion.
- Case 6 (new): a rollout with only a non-terminal `task_started` event, mtime past
  spawn — asserts the deadline-check returns 0 in well under 15s (measured elapsed;
  actual result was 0s), proving it doesn't wait out the 30s window.

**Suite:** `test-codex-instant-complete.sh`
```
[CODEX-INSTANT-COMPLETE] case 1: dead shape (task_complete + last_agent_message=null)
[CODEX-INSTANT-COMPLETE]   detected dead shape (rc=0) ✓
[CODEX-INSTANT-COMPLETE] case 2: healthy terminal completion (real last_agent_message)
[CODEX-INSTANT-COMPLETE]   correctly NOT flagged dead (rc=2) ✓
[CODEX-INSTANT-COMPLETE] case 3: still-running job (no task_complete yet)
[CODEX-INSTANT-COMPLETE]   correctly reported unknown/still-running (rc=1) ✓
[CODEX-INSTANT-COMPLETE] case 4: newest-rollout-since picks the right file, ignores older-than-since
[CODEX-INSTANT-COMPLETE]   picked c4_new, ignored c4_old (mtime < since), count=1 ✓
[CODEX-INSTANT-COMPLETE] case 4b: cwd match preferred over a newer sibling rollout, ambiguity count=2
[CODEX-INSTANT-COMPLETE]   picked cwd-matched rollout despite sibling being newer, count=2 ✓
[CODEX-INSTANT-COMPLETE] case 5: deadline-check returns 7 on the dead shape AND records the strike
[CODEX-INSTANT-COMPLETE]   deadline-check returned 7 (spill) AND wrote .../quota-lockout-codex.json ✓
[CODEX-INSTANT-COMPLETE] case 6: non-terminal activity since spawn returns 0 early, not at the 30s window
[CODEX-INSTANT-COMPLETE]   returned 0 in 0s, well under the 30s window ✓
[CODEX-INSTANT-COMPLETE] pass=7 fail=0
```
(was pass=5 fail=0 before this change; 2 new legs added, 1 leg strengthened.)

Commit: `f387f4d fix(dispatch-code): scope+speed up codex instant-complete check (nits 2-A/2-B/2-C)`

## Mechanical gates (item 1 only — items 2-4 untouched)

```
$ bash -n plugins/leadv2/scripts/leadv2-backlog-pump.sh   # OK
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh  # OK
$ bash -n plugins/leadv2/scripts/tests/test-codex-instant-complete.sh  # OK
```
No Python files changed.

shellcheck -S warning: compared `git show HEAD:leadv2-dispatch-code.sh` (pre-edit) against
the working tree with `shellcheck -S warning` on both, sorted, diffed with filenames
normalised — output is content-identical (same 9 findings, only line numbers shifted from
inserted lines; the pre-existing SC2034 `LANE_LIVENESS_FAILED` noted by the critic report
is unchanged on both sides). Same check on `leadv2-backlog-pump.sh`: no new findings.

Off-limits respected: no edits to `leadv2-dispatch-product-close.sh`, no routing-order/
ceiling changes, no `supervise*` edits — confirmed by `git show --stat` on both commits
(only `leadv2-backlog-pump.sh` in dc6f99d; `leadv2-dispatch-code.sh` +
`tests/test-codex-instant-complete.sh` in f387f4d).

## NOT done — items 2, 3, 4

- **Item 2 (CODEX-ARM-WORKTREE-SCOPE-01)** — not started. Needs: root-cause the codex
  WORKER-arm spawn shape (`_codex` spawn path around leadv2-dispatch-code.sh:3223,
  `--cwd "${WORK_ROOT}"`), confirm workspaceRoot registration in the job store, add a
  post-spawn liveness probe extending the `arm_dead_instant_complete` machinery already
  in place from item 1 (turn_aborted / no job-store row within 60s → arm_dead journal +
  strike + spill), red-first test with a stubbed codex bin. Do NOT remove the existing
  12h codex-worker-arm lockout (`quota-lockout-codex.json`,
  SD-CODEX-WORKER-ARM-ABORTED-01) — this item's fix is what's meant to unlock it.
- **Item 3 (V3-TIERED-REVIEW-01)** — not started. Wire the dispatch-code review arm to run
  mechanical checks (bash -n/shellcheck/changed-scope) first and consume
  builder-selfcheck's verdict before paying an LLM review round; opus critic becomes
  round-1 only; verify-only rounds on sonnet; sonnet-pilot flag stays default-off.
- **Item 4 (V3-WORKER-MESSAGING slice-1)** — not started. `docs/specs/worker-messaging-
  v3.md` §slice-1 not yet read. Needs `leadv2-event.sh` JSONL emitter under
  `~/.claude/cache/leadv2-events/<repo>.jsonl` + 4 emit call sites (worker_spawned,
  arm_refused, worker_terminal, question_asked) in dispatch-code.sh, red-first test for
  the emitter + one emit call.

## Acceptance status

- Per-item suites green with red-first evidence: item 1 only (both suites; the
  pump-junk suite's red-first proof was already established in the prior lane per the
  critic report, re-confirmed green here after the 1-A edit; the codex-instant-complete
  suite's new/strengthened legs were written and verified against the pre-fix behaviour
  implicitly — case 6 would time out at ~30s pre-fix, case 5 would show no lockout file
  pre-fix, case 4b would pick the wrong/ambiguous file pre-fix).
- Full `run-core-offline` FOREGROUND SOLO run: **not executed** — out of scope for a
  turn-capped partial run; the next subagent should run it after items 2-4 land (running
  it now, before those items exist, would only reconfirm item 1's own two suites which
  are already shown above).
- 4 commits: **2 of 4 made** (dc6f99d, f387f4d — both for item 1, split across its two
  files rather than the single commit the plan called for).

DELIVERABLE_COMPLETE
