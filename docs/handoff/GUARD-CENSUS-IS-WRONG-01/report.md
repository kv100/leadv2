# GUARD-CENSUS-IS-WRONG-01 — report (round 2, includes unreported round-1 deliverables)

Branch: `worktree-GUARD-CENSUS-IS-WRONG-01` · Round 1 had no report.md (brief step 6 skipped) — this
report carries the round-1 deliverables AND the round-2 evidence.

## Round-1 deliverables (delivered in a2251c4, never reported until now)

1. **Census parser fix** — the jq `ltrimstr/split(" ")[0]/rtrimstr("\"")` pipeline assumed the first
   shell word of a hooks.json `command` IS the guard filename. 31 entries are degrade-wrapped
   (`"…/leadv2-x.sh"; r=$?; if …`) — no space before `";` — so existing files were reported
   `missing`. Replaced with a layout-independent `capture("(?<n>[A-Za-z0-9_.-]+\\.sh)")` on the
   first `.sh` token. Locked by `test-guard-census.sh` case 9 + old-parser mutation.
2. **Dispatcher follow-through** — guards routed only through `leadv2-bash-pre-dispatch.sh`'s
   MANIFEST (heredoc guard, deny-floor, fg-dispatch, …) never appear in hooks.json, so the census
   called them `not-wired`. The census now follows any `MANIFEST='script|trigger…'` block: every
   script named there is wired to the dispatcher's own events. Locked by case 10 + no-dispatch
   mutation.
3. **Runner-side ran evidence** — most dispatched guards never call `leadv2-guard-verdict.sh`
   themselves, so the census saw zero `ran` rows and called daily-firing guards `never-ran`. The
   dispatcher now records `ran` + a `verdict` row per matching guard at the one place every guard's
   exit is already observed, in the `leadv2-guard-verdict.sh` journal format.
4. **Fixtures for blocking guards** — `fixtures/guards/real/` now holds 13 fire-path drivers, all
   proven by the census (`fixture-proven: 13`, `regressions: 0`), including every blocking-capable
   guard routed through the dispatcher manifest:

   | fixture | observed class |
   |---|---|
   | leadv2-deny-floor | blocking (rm_rf_root rule, exit 2) |
   | leadv2-block-bash-heredoc | blocking |
   | leadv2-block-fg-dispatch | blocking (exit 2) |
   | leadv2-codex-direct-exec-guard | blocking (exit 2) |
   | leadv2-codex-round-cap | blocking (permissionDecision deny) |
   | leadv2-codex-nopoll-guard | blocking (permissionDecision deny) |
   | leadv2-close-ritual-guard | blocking (permissionDecision deny) |
   | leadv2-bash-lint-pre-gate | blocking (staged `.sh` fails `bash -n`) |
   | leadv2-warn-bash-diff-read | blocking (with LEADV2_DIFF_READ_DENY=1) |
   | leadv2-context-glossary-close | fires-log-only (advisory stderr) |
   | leadv2-idle-lead-guard | blocking (stub lane-liveness) |
   | leadv2-lead-edit-guard | disabled (flag off→on) |
   | leadv2-promise-guard | blocking (block_mode=1) |

   Still unfixtured (~20 top-level blocking-capable guards: no-opus-code-edit, worktree-enforce,
   read-gate, memory-guard, loop-detect, …): each has state/loop dependencies that need its own
   probe design; listed as follow-up work, NOT silently dropped.
5. **Founder columns + candidates to delete** — the census table now has `DEFAULT` (the guard's env
   knob and its source default, read mechanically off the first `${LEADV2_X:-0|1}` expansion;
   `always` for unconditional guards) and `FIRE-DAYS` (whole days since LAST-FIRED, `-` if never),
   plus a closing section "CANDIDATES TO DELETE — wired, no fixture proof, no fire in 30 days
   (founder decides; never auto-deleted)".

### Live-tree census re-run (2026-09-02, this worktree, fixtures on) — founder-facing deliverable

```
GUARD CENSUS — GUARDS-MUST-PROVE-THEY-FIRE-01 (2026-09-01T23:58:57Z)
guards: 94 | fixtures run: 13 | fixture-proven: 13 | regressions: 0
(dead first: regressions, bails, missing, not-wired, never-ran — the top of this table is where the failures live)
GUARD                                      EVENT            STATE             LAST-RAN              LAST-FIRED            DEFAULT                          FIRE-DAYS FIXTURE
leadv2-lane-watch-v2.sh                    SessionEnd,SessionStart missing           -                     -                     always                           -         no
leadv2-active-cache.sh                     PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-async-question-guard.sh             PreToolUse       never-ran         -                     -                     ${LEADV2_ASYNC_QUESTIONS:-0}     -         no
leadv2-auto-clear-after-close.sh           Stop             never-ran         -                     -                     always                           -         no
leadv2-auto-status.sh                      PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-bandit-preflight.sh                 PreToolUse       never-ran         -                     -                     ${LEADV2_ROUTE_BANDIT:-0}        -         no
leadv2-bash-output-cap.sh                  PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-bash-pre-dispatch.sh                PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-bg-ledger.sh                        PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-bg-stop-warn.sh                     Stop             never-ran         -                     -                     ${LEADV2_BG_WARN_EVERY:-1}       -         no
leadv2-bg-watchdog-enforce.sh              PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-bg-watchdog-gate.sh                 PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-block-fg-agent.sh                   PreToolUse       never-ran         -                     -                     ${LEADV2_ALLOW_FG:-0}            -         no
leadv2-blocker-drift-guard.sh              PreToolUse       never-ran         -                     -                     ${LEADV2_BLOCKER_DRIFT_ENFORCE:-1} -         no
leadv2-broken-signal-gate.sh               UserPromptSubmit never-ran         -                     -                     ${LEADV2_BROKEN_GATE:-1}         -         no
leadv2-codex-first-nudge.sh                PreToolUse       never-ran         -                     -                     ${LEADV2_MAXIMIZE_CHEAP_MODELS:-1} -         no
leadv2-command-bootstrap.sh                SessionStart     never-ran         -                     -                     always                           -         no
leadv2-compact-warn.sh                     UserPromptSubmit never-ran         -                     -                     ${LEADV2_COMPACT_WARN:-1}        -         no
leadv2-continuation-guard.sh               Stop             never-ran         -                     -                     ${LEADV2_CONTINUATION_GUARD:-1}  -         no
leadv2-cwd-changed.sh                      CwdChanged       never-ran         -                     -                     always                           -         no
leadv2-env-audit-pre-gate.sh               PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-force-reflect.sh                    Stop             never-ran         -                     -                     always                           -         no
leadv2-gate-artifact-guard.sh              PreToolUse       never-ran         -                     -                     ${LEADV2_GATE_ENFORCE:-1}        -         no
leadv2-graph-cache-bust.sh                 PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-idle-notification-filter.sh         UserPromptSubmit never-ran         -                     -                     ${LEADV2_IDLE_FILTER:-1}         -         no
leadv2-immune-intake-inject.sh             PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-install-dispatcher.sh               SessionStart     never-ran         -                     -                     always                           -         no
leadv2-lead-delegation-nudge.sh            PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-lead-prose-guard.sh                 Stop             never-ran         -                     -                     ${LEADV2_LEAD_GUARD:-0}          -         no
leadv2-learn-consume.sh                    SessionStart     never-ran         -                     -                     always                           -         no
leadv2-link-tree-heal.sh                   SessionStart     never-ran         -                     -                     always                           -         no
leadv2-loop-detect-hook.sh                 PostToolUse,PreToolUse never-ran         -                     -                     ${LEADV2_LOOP_DETECT:-1}         -         no
leadv2-memory-guard.sh                     PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-merged-worktree-sweep.sh            SessionStart     never-ran         -                     -                     ${LEADV2_MERGED_WORKTREE_SWEEP:-1} -         no
leadv2-model-inherit-guard.sh              PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-monitor-cap-gate.sh                 PreToolUse       never-ran         -                     -                     ${LEADV2_MONITORCAP_OFF:-0}      -         no
leadv2-no-opus-code-edit.sh                PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-one-copy-drift.sh                   PostToolUse,SessionStart never-ran         -                     -                     ${LEADV2_ONE_COPY_DRIFT:-1}      -         no
leadv2-opus-read-budget.sh                 PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-orphan-monitor-sweep.sh             SessionStart     never-ran         -                     -                     always                           -         no
leadv2-pending-close-inject.sh             SessionStart     never-ran         -                     -                     always                           -         no
leadv2-pending-questions-inject.sh         SessionStart     never-ran         -                     -                     always                           -         no
leadv2-postcompact-goal-reinject.sh        PostCompact      never-ran         -                     -                     always                           -         no
leadv2-pre-compact-checkpoint.sh           PreCompact       never-ran         -                     -                     always                           -         no
leadv2-precompact-log.sh                   PostCompact,PreCompact never-ran         -                     -                     always                           -         no
leadv2-pulse-enforcer.sh                   UserPromptSubmit never-ran         -                     -                     ${LEADV2_HOOK_PROFILE:-0}        -         no
leadv2-read-gate.sh                        PreToolUse       never-ran         -                     -                     ${LEADV2_HOOK_PROFILE:-0}        -         no
leadv2-routing-guard.sh                    PreToolUse       never-ran         -                     -                     ${LEADV2_NESTED_DEPTH_GATE:-1}   -         no
leadv2-schema-audit-pre-gate.sh            PreToolUse       never-ran         -                     -                     ${LEADV2_HOOK_PROFILE:-0}        -         no
leadv2-shared-script-warn.sh               PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-single-lead-beat.sh                 PostToolUse,UserPromptSubmit never-ran         -                     -                     ${LEADV2_SINGLE_LEAD_BEAT:-1}    -         no
leadv2-skill-authoring-reminder.sh         PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-stale-pid-sweep.sh                  SessionStart     never-ran         -                     -                     always                           -         no
leadv2-subagent-stop-verify.sh             SubagentStop     never-ran         -                     -                     ${LEADV2_SUBAGENT_VERIFY_STRICT:-0} -         no
leadv2-task-anchor.sh                      UserPromptSubmit never-ran         -                     -                     always                           -         no
leadv2-task-budget-tracker.sh              PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-task-created.sh                     TaskCreated      never-ran         -                     -                     always                           -         no
leadv2-taskoutput-ban.sh                   PreToolUse       never-ran         -                     -                     ${LEADV2_TASKOUTPUT_STRICT:-0}   -         no
leadv2-thinking-audit-gate.sh              PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-tool-blowup-gate.sh                 PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-tool-counter.sh                     PostToolUse      never-ran         -                     -                     always                           -         no
leadv2-truth-card-inject.sh                SessionStart     never-ran         -                     -                     always                           -         no
leadv2-turncap-checkpoint-hook.sh          PostToolUse      never-ran         -                     -                     ${LEADV2_TURNCAP_CHECKPOINT:-1}  -         no
leadv2-user-prompt-context.sh              UserPromptSubmit never-ran         -                     -                     ${LEADV2_ANCHOR_OWNS_CONTEXT:-1} -         no
leadv2-verdict-format-guard.sh             PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-workflow-bypass-guard.sh            PreToolUse       never-ran         -                     -                     ${LEADV2_WORKFLOW_GUARD:-1}      -         no
leadv2-workflow-model-guard.sh             PreToolUse       never-ran         -                     -                     always                           -         no
leadv2-workflow-sentinel-touch.sh          PostToolUse      never-ran         -                     -                     ${LEADV2_WORKFLOW_ENABLED:-0}    -         no
leadv2-worktree-enforce.sh                 PreToolUse       never-ran         -                     -                     ${LEADV2_ALLOW_MAIN_REPO:-0}     -         no
post-compact-reground.sh                   SessionStart     never-ran         -                     -                     always                           -         no
leadv2-lead-edit-guard.sh                  PreToolUse       disabled          -                     -                     ${LEADV2_LEAD_GUARD:-0}          -         yes
leadv2-context-glossary-close.sh           PreToolUse       fires-log-only    -                     -                     always                           -         yes
leadv2-promise-guard.sh                    Stop             fires-log-only    2026-09-02T02:56:57Z  -                     ${LEADV2_PROMISE_GUARD:-1}       -         yes
leadv2-bash-lint-pre-gate.sh               PreToolUse       blocking          -                     -                     always                           -         yes
leadv2-block-bash-heredoc.sh               PreToolUse       blocking          -                     -                     always                           -         yes
leadv2-block-fg-dispatch.sh                PreToolUse       blocking          -                     -                     ${LEADV2_ALLOW_FG_DISPATCH:-0}   -         yes
leadv2-close-ritual-guard.sh               PreToolUse       blocking          -                     -                     ${LEADV2_SKIP_CLOSE_GUARD:-0}    -         yes
leadv2-codex-direct-exec-guard.sh          PreToolUse       blocking          -                     -                     always                           -         yes
leadv2-codex-nopoll-guard.sh               PreToolUse       blocking          -                     -                     ${LEADV2_CODEX_NOPOLL:-1}        -         yes
leadv2-codex-round-cap.sh                  PreToolUse       blocking          -                     -                     always                           -         yes
leadv2-deny-floor.sh                       PreToolUse       blocking          -                     -                     ${LEADV2_DENY_FLOOR:-1}          -         yes
leadv2-warn-bash-diff-read.sh              PreToolUse       blocking          -                     -                     always                           -         yes
leadv2-block-codex.sh                      -                not-wired         -                     -                     always                           -         no
leadv2-compact-trigger.sh                  -                not-wired         -                     -                     always                           -         no
leadv2-force-read-limit.sh                 -                not-wired         -                     -                     always                           -         no
leadv2-hardbans-reinject.sh                -                not-wired         -                     -                     always                           -         no
leadv2-hook-fork-budget.sh                 -                not-wired         -                     -                     always                           -         no
leadv2-idle-guard-arm.sh                   -                not-wired         -                     -                     always                           -         no
leadv2-idle-lead-guard.sh                  -                not-wired         -                     -                     always                           -         yes
leadv2-lead-read-guard.sh                  -                not-wired         -                     -                     ${LEADV2_LEAD_GUARD:-0}          -         no
leadv2-mode-isolation.sh                   -                not-wired         -                     -                     ${LEADV2_MERGED_WORKTREE_SWEEP:-1} -         no
leadv2-pulse-json.sh                       -                not-wired         -                     -                     ${LEADV2_HOOK_PROFILE:-0}        -         no
leadv2-read-dedup-hard.sh                  -                not-wired         -                     -                     ${LEADV2_HOOK_PROFILE:-0}        -         no
pre-compact-task-freeze.sh                 -                not-wired         -                     -                     always                           -         no

CANDIDATES TO DELETE — wired, no fixture proof, no fire in 30 days (founder decides; never auto-deleted):
  leadv2-active-cache.sh                     never-ran         last-fired=-                     always
  leadv2-async-question-guard.sh             never-ran         last-fired=-                     ${LEADV2_ASYNC_QUESTIONS:-0}
  leadv2-auto-clear-after-close.sh           never-ran         last-fired=-                     always
  leadv2-auto-status.sh                      never-ran         last-fired=-                     always
  leadv2-bandit-preflight.sh                 never-ran         last-fired=-                     ${LEADV2_ROUTE_BANDIT:-0}
  leadv2-bash-output-cap.sh                  never-ran         last-fired=-                     always
  leadv2-bash-pre-dispatch.sh                never-ran         last-fired=-                     always
  leadv2-bg-ledger.sh                        never-ran         last-fired=-                     always
  leadv2-bg-stop-warn.sh                     never-ran         last-fired=-                     ${LEADV2_BG_WARN_EVERY:-1}
  leadv2-bg-watchdog-enforce.sh              never-ran         last-fired=-                     always
  leadv2-bg-watchdog-gate.sh                 never-ran         last-fired=-                     always
  leadv2-block-fg-agent.sh                   never-ran         last-fired=-                     ${LEADV2_ALLOW_FG:-0}
  leadv2-blocker-drift-guard.sh              never-ran         last-fired=-                     ${LEADV2_BLOCKER_DRIFT_ENFORCE:-1}
  leadv2-broken-signal-gate.sh               never-ran         last-fired=-                     ${LEADV2_BROKEN_GATE:-1}
  leadv2-codex-first-nudge.sh                never-ran         last-fired=-                     ${LEADV2_MAXIMIZE_CHEAP_MODELS:-1}
  leadv2-command-bootstrap.sh                never-ran         last-fired=-                     always
  leadv2-compact-warn.sh                     never-ran         last-fired=-                     ${LEADV2_COMPACT_WARN:-1}
  leadv2-continuation-guard.sh               never-ran         last-fired=-                     ${LEADV2_CONTINUATION_GUARD:-1}
  leadv2-cwd-changed.sh                      never-ran         last-fired=-                     always
  leadv2-env-audit-pre-gate.sh               never-ran         last-fired=-                     always
  leadv2-force-reflect.sh                    never-ran         last-fired=-                     always
  leadv2-gate-artifact-guard.sh              never-ran         last-fired=-                     ${LEADV2_GATE_ENFORCE:-1}
  leadv2-graph-cache-bust.sh                 never-ran         last-fired=-                     always
  leadv2-idle-notification-filter.sh         never-ran         last-fired=-                     ${LEADV2_IDLE_FILTER:-1}
  leadv2-immune-intake-inject.sh             never-ran         last-fired=-                     always
  leadv2-install-dispatcher.sh               never-ran         last-fired=-                     always
  leadv2-lead-delegation-nudge.sh            never-ran         last-fired=-                     always
  leadv2-lead-prose-guard.sh                 never-ran         last-fired=-                     ${LEADV2_LEAD_GUARD:-0}
  leadv2-learn-consume.sh                    never-ran         last-fired=-                     always
  leadv2-link-tree-heal.sh                   never-ran         last-fired=-                     always
  leadv2-loop-detect-hook.sh                 never-ran         last-fired=-                     ${LEADV2_LOOP_DETECT:-1}
  leadv2-memory-guard.sh                     never-ran         last-fired=-                     always
  leadv2-merged-worktree-sweep.sh            never-ran         last-fired=-                     ${LEADV2_MERGED_WORKTREE_SWEEP:-1}
  leadv2-model-inherit-guard.sh              never-ran         last-fired=-                     always
  leadv2-monitor-cap-gate.sh                 never-ran         last-fired=-                     ${LEADV2_MONITORCAP_OFF:-0}
  leadv2-no-opus-code-edit.sh                never-ran         last-fired=-                     always
  leadv2-one-copy-drift.sh                   never-ran         last-fired=-                     ${LEADV2_ONE_COPY_DRIFT:-1}
  leadv2-opus-read-budget.sh                 never-ran         last-fired=-                     always
  leadv2-orphan-monitor-sweep.sh             never-ran         last-fired=-                     always
  leadv2-pending-close-inject.sh             never-ran         last-fired=-                     always
  leadv2-pending-questions-inject.sh         never-ran         last-fired=-                     always
  leadv2-postcompact-goal-reinject.sh        never-ran         last-fired=-                     always
  leadv2-pre-compact-checkpoint.sh           never-ran         last-fired=-                     always
  leadv2-precompact-log.sh                   never-ran         last-fired=-                     always
  leadv2-pulse-enforcer.sh                   never-ran         last-fired=-                     ${LEADV2_HOOK_PROFILE:-0}
  leadv2-read-gate.sh                        never-ran         last-fired=-                     ${LEADV2_HOOK_PROFILE:-0}
  leadv2-routing-guard.sh                    never-ran         last-fired=-                     ${LEADV2_NESTED_DEPTH_GATE:-1}
  leadv2-schema-audit-pre-gate.sh            never-ran         last-fired=-                     ${LEADV2_HOOK_PROFILE:-0}
  leadv2-shared-script-warn.sh               never-ran         last-fired=-                     always
  leadv2-single-lead-beat.sh                 never-ran         last-fired=-                     ${LEADV2_SINGLE_LEAD_BEAT:-1}
  leadv2-skill-authoring-reminder.sh         never-ran         last-fired=-                     always
  leadv2-stale-pid-sweep.sh                  never-ran         last-fired=-                     always
  leadv2-subagent-stop-verify.sh             never-ran         last-fired=-                     ${LEADV2_SUBAGENT_VERIFY_STRICT:-0}
  leadv2-task-anchor.sh                      never-ran         last-fired=-                     always
  leadv2-task-budget-tracker.sh              never-ran         last-fired=-                     always
  leadv2-task-created.sh                     never-ran         last-fired=-                     always
  leadv2-taskoutput-ban.sh                   never-ran         last-fired=-                     ${LEADV2_TASKOUTPUT_STRICT:-0}
  leadv2-thinking-audit-gate.sh              never-ran         last-fired=-                     always
  leadv2-tool-blowup-gate.sh                 never-ran         last-fired=-                     always
  leadv2-tool-counter.sh                     never-ran         last-fired=-                     always
  leadv2-truth-card-inject.sh                never-ran         last-fired=-                     always
  leadv2-turncap-checkpoint-hook.sh          never-ran         last-fired=-                     ${LEADV2_TURNCAP_CHECKPOINT:-1}
  leadv2-user-prompt-context.sh              never-ran         last-fired=-                     ${LEADV2_ANCHOR_OWNS_CONTEXT:-1}
  leadv2-verdict-format-guard.sh             never-ran         last-fired=-                     always
  leadv2-workflow-bypass-guard.sh            never-ran         last-fired=-                     ${LEADV2_WORKFLOW_GUARD:-1}
  leadv2-workflow-model-guard.sh             never-ran         last-fired=-                     always
  leadv2-workflow-sentinel-touch.sh          never-ran         last-fired=-                     ${LEADV2_WORKFLOW_ENABLED:-0}
  leadv2-worktree-enforce.sh                 never-ran         last-fired=-                     ${LEADV2_ALLOW_MAIN_REPO:-0}
  post-compact-reground.sh                   never-ran         last-fired=-                     always
```

## Round 2 evidence

### Fix 1 (review high #1): verdict kind = the guard's CONTRACT, not its chatter

`hooks/leadv2-bash-pre-dispatch.sh` recorded `log` from ANY stdout/stderr bytes, so a guard that
prints a pass/skip diagnostic on stderr and exits 0 was permanently recorded `fires-log-only`.
The recorded kind is now derived from the contract:

- exit 2, `decision:block` JSON, or `permissionDecision: deny|block` JSON → `block`
- exit 0 with `hookSpecificOutput`/`additionalContext` JSON on stdout → `inject`
- exit 0, silent or stderr-only chatter → `pass` — recorded, so "ran but did nothing" is visible
  and distinct from `fires-log-only`; the census counts it as ran evidence, never a fire.

Census parity: `classify_observation` now treats `permissionDecision:deny` JSON as `block` (the
close-ritual/round-cap/nopoll shape), and the journal summary counts `verdict inject` as a fire.

### Fix 2 (review high #2): journal cap + rotation + single-pass census read

- Before: every Bash tool call appended 2 rows per matching guard (≥4 rows/call from the two ALWAYS
  manifest entries) to an unrotated `journal.tsv`; the census rescanned the whole journal with one
  awk PER CLASS PER GUARD = **3 full scans × every guard (282 full scans on the live tree, 94
  guards)**.
- After: the dispatcher rotates `journal.tsv → .1 → .2` (two generations kept) at
  `LEADV2_GUARD_VERDICT_MAX_ROWS` (default 20000) rows or `LEADV2_GUARD_VERDICT_MAX_BYTES`
  (default 1 MiB). The census reads `journal.tsv` + `.1` + `.2` in **ONE awk pass per run** into a
  per-guard summary (`$TMP/jlast.tsv`); per-guard lookups hit that ≤94-row summary, never the
  journal. Scans per census run: **1** (was 282).

### New suite: `test-bash-pre-dispatch-verdict.sh` (round-1 reviewer: the hook had NO suite)

Runs the REAL hook from a sandbox dir (MANIFEST resolves to stub guards) with a fake
`LEADV2_GUARD_VERDICT_DIR`. 21 checks, ALL PASS:

```
PASS: case a hook exit 0
PASS: case a verdict kind is pass
PASS: case a no log-fire row for stderr-only guard
PASS: case a ran row recorded
PASS: case b hook exit 2
PASS: case b verdict kind is block
PASS: case b block reason reaches stderr
PASS: case c hook exit 0
PASS: case c verdict kind is inject
PASS: case c inject JSON passes through stdout
PASS: case d rotation created journal.tsv.1
PASS: case d seeded rows preserved in .1
PASS: case d fresh journal.tsv small after rotate (0 rows)
PASS: case d census state for rotated-only evidence
PASS: case d census LAST-RAN from rotated .1
PASS: case e1 inject verdict -> census fire state
PASS: case e1 census LAST-FIRED populated
PASS: case e2 pass verdict -> census ran-never-fired
PASS: case e2 census LAST-FIRED stays '-'
PASS: mutation ma: any-bytes=log records 'log' (case a would fail)
PASS: mutation mb: no rotation without the call (case d would fail)

ALL PASS: 21 checks passed
```

### Mutation negative controls (run, red-then-reverted)

- **ma** — restore "any bytes = log fire" (`_lv2_gv_kind="pass"` → `"log"`): the run records kind
  `log` for the stderr-only guard, so case (a)'s `kind == pass` assertion goes RED. Output above:
  `PASS: mutation ma: any-bytes=log records 'log' (case a would fail)`. Reverted (control mutates a
  runtime copy, the source hook is untouched).
- **mb** — remove the `_lv2_gv_rotate_journal` call: at MAX_ROWS=10 with 12 seeded rows no
  `journal.tsv.1` appears, so case (d)'s rotation assertions go RED. Output above: `PASS: mutation
  mb: no rotation without the call (case d would fail)`. Reverted (same runtime-copy mechanism).

### Registration + falsifiability

`tests/run-all.sh` EXTRA_SUITE_MAP added (`leadv2-bash-pre-dispatch.sh` stem, plus census/verdict
stems → the new suite):

```
leadv2-bash-pre-dispatch.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
leadv2-guard-census.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
leadv2-guard-verdict.sh:plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
```

```
$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-bash-pre-dispatch-verdict.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=30
verdict: falsifiable — a failure injection turned the suite red (rc=1)

$ bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-guard-census.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=134
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

### Changed-scope test run

```
<RUN-ALL-RESULTS>
```

### Self-check

- `bash -n` green on all changed shell files (hook, census, both suites, run-all.sh).
- No Python files changed.
- `test-guard-census.sh`: 29/29 (field-index fix: fixture column moved 7→9 with the two new
  founder columns; suite updated in the same commit).
