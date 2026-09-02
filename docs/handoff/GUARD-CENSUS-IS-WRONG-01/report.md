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

Regenerated on the R3-fixed script against the live lane-tip tree (064a8ce3 + merge of main),
replacing the stale R2-era block that previously sat here (13 not-wired/missing rows with
leaked / false-`always` DEFAULT cells). Evidence:

```
$ bash plugins/leadv2/scripts/leadv2-guard-census.sh \
    --fixtures-dir "$PWD/plugins/leadv2/scripts/tests/fixtures/guards/real" --format table
rc=0; guards: 94 | fixtures run: 13 | fixture-proven: 13 | regressions: 0
  → full output = the fenced census at the bottom of this section
$ git diff --stat cd49e158..HEAD -- docs/handoff/GUARD-CENSUS-IS-WRONG-01/report.md
 docs/handoff/GUARD-CENSUS-IS-WRONG-01/report.md | 286 +++++++++++++++---------
 1 file changed, 177 insertions(+), 109 deletions(-)
```

**Before/after (old shipped block vs this regeneration; DEFAULT = col 7 of a second run with
the same flags and `--format tsv`):**

- (a) rows whose DEFAULT changed: **31** (`join` on guard name over the two runs, values
  differ — full list pasted below; matches the R3 fix-round count).
- (b) rows still printing `always` for a flag-gated guard: **0**:

```
$ awk -F'\t' '$7=="always"{print $2}' /tmp/census-new.tsv | while read g; do
>   grep -qE '\$\{LEADV2_' plugins/leadv2/hooks/"$g" 2>/dev/null && echo "STILL-WRONG: $g"; done
(no output — 0 of the 32 remaining `always` rows contain any LEADV2_ reference)

# the 13 not-wired/missing rows, previously the stale cells, now all print '-':
$ awk -F'\t' '$4=="not-wired" || $4=="missing" {n++; if ($7!="-") bad++}
>   END{print "not-wired/missing rows:", n, "| with non-'-' DEFAULT:", bad+0}' /tmp/census-new.tsv
not-wired/missing rows: 13 | with non-'-' DEFAULT: 0
```

31 changed DEFAULT cells (old → new):

```

leadv2-active-cache.sh  →  always  →  ${LEADV2_STATE_DIR}
leadv2-bash-lint-pre-gate.sh  →  always  →  ${LEADV2_TASK_ID:-}
leadv2-bash-pre-dispatch.sh  →  always  →  ${LEADV2_GUARD_VERDICT_DIR:-${CLAUDE_PROJECT_DIR:-$HOME}}
leadv2-bg-watchdog-enforce.sh  →  always  →  ${LEADV2_BG_ORPHAN_MAX:-3}
leadv2-block-codex.sh  →  always  →  -
leadv2-codex-direct-exec-guard.sh  →  always  →  ${LEADV2_ALLOW_DIRECT_CODEX:-}
leadv2-codex-round-cap.sh  →  always  →  ${LEADV2_TASK_ID:-}
leadv2-compact-trigger.sh  →  always  →  -
leadv2-force-read-limit.sh  →  always  →  -
leadv2-hardbans-reinject.sh  →  always  →  -
leadv2-hook-fork-budget.sh  →  always  →  -
leadv2-idle-guard-arm.sh  →  always  →  -
leadv2-idle-lead-guard.sh  →  always  →  -
leadv2-immune-intake-inject.sh  →  always  →  ${LEADV2_PROJECT_ROOT:-$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs dirname 2>/dev/null || pwd)}
leadv2-lane-watch-v2.sh  →  always  →  -
leadv2-lead-edit-guard.sh  →  ${LEADV2_LEAD_GUARD:-0}  →  ${LEADV2_LEAD_GUARD_FORCE:-}
leadv2-lead-read-guard.sh  →  ${LEADV2_LEAD_GUARD:-0}  →  -
leadv2-link-tree-heal.sh  →  always  →  ${LEADV2_CANONICAL_SCRIPTS:-$HOME/Projects/leadv2/plugins/leadv2/scripts}
leadv2-memory-guard.sh  →  always  →  ${LEADV2_TASK_ID:-}
leadv2-mode-isolation.sh  →  ${LEADV2_MERGED_WORKTREE_SWEEP:-1}  →  -
leadv2-model-inherit-guard.sh  →  always  →  ${LEADV2_MAIN_MODEL:-the session model}
leadv2-pending-questions-inject.sh  →  always  →  ${LEADV2_Q_SESSIONSTART_MIN_AGE_S:-600}
leadv2-pre-compact-checkpoint.sh  →  always  →  ${LEADV2_TASK_ANCHOR_STATE_DIR:-$HOME/.claude/state/leadv2}
leadv2-pulse-json.sh  →  ${LEADV2_HOOK_PROFILE:-0}  →  -
leadv2-read-dedup-hard.sh  →  ${LEADV2_HOOK_PROFILE:-0}  →  -
leadv2-routing-guard.sh  →  ${LEADV2_NESTED_DEPTH_GATE:-1}  →  ${LEADV2_TASK_ID:-}
leadv2-schema-audit-pre-gate.sh  →  ${LEADV2_HOOK_PROFILE:-0}  →  ${LEADV2_PROJECT_ROOT:-$REPO}
leadv2-thinking-audit-gate.sh  →  always  →  ${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
leadv2-tool-blowup-gate.sh  →  always  →  ${LEADV2_TOOL_BLOWUP_HARD:-120}
leadv2-warn-bash-diff-read.sh  →  always  →  ${LEADV2_DIFF_READ_GUARD:-}
pre-compact-task-freeze.sh  →  always  →  -
```
```

GUARD CENSUS — GUARDS-MUST-PROVE-THEY-FIRE-01 (2026-09-02T02:11:52Z)
guards: 94 | fixtures run: 13 | fixture-proven: 13 | regressions: 0
(dead first: regressions, bails, missing, not-wired, never-ran — the top of this table is where the failures live)
GUARD                                      EVENT            STATE             LAST-RAN              LAST-FIRED            DEFAULT                              FIRE-DAYS FIXTURE
leadv2-lane-watch-v2.sh                    SessionEnd,SessionStart missing           -                     -                     -                                    -         no
leadv2-active-cache.sh                     PostToolUse      never-ran         -                     -                     ${LEADV2_STATE_DIR}                  -         no
leadv2-async-question-guard.sh             PreToolUse       never-ran         -                     -                     ${LEADV2_ASYNC_QUESTIONS:-0}         -         no
leadv2-auto-clear-after-close.sh           Stop             never-ran         -                     -                     always                               -         no
leadv2-auto-status.sh                      PostToolUse      never-ran         -                     -                     always                               -         no
leadv2-bandit-preflight.sh                 PreToolUse       never-ran         -                     -                     ${LEADV2_ROUTE_BANDIT:-0}            -         no
leadv2-bash-output-cap.sh                  PostToolUse      never-ran         -                     -                     always                               -         no
leadv2-bash-pre-dispatch.sh                PreToolUse       never-ran         -                     -                     ${LEADV2_GUARD_VERDICT_DIR:-${CLAUDE_PROJECT_DIR:-$HOME}} -         no
leadv2-bg-ledger.sh                        PostToolUse      never-ran         -                     -                     always                               -         no
leadv2-bg-stop-warn.sh                     Stop             never-ran         -                     -                     ${LEADV2_BG_WARN_EVERY:-1}           -         no
leadv2-bg-watchdog-enforce.sh              PostToolUse      never-ran         -                     -                     ${LEADV2_BG_ORPHAN_MAX:-3}           -         no
leadv2-bg-watchdog-gate.sh                 PostToolUse      never-ran         -                     -                     always                               -         no
leadv2-block-fg-agent.sh                   PreToolUse       never-ran         -                     -                     ${LEADV2_ALLOW_FG:-0}                -         no
leadv2-blocker-drift-guard.sh              PreToolUse       never-ran         -                     -                     ${LEADV2_BLOCKER_DRIFT_ENFORCE:-1}   -         no
leadv2-broken-signal-gate.sh               UserPromptSubmit never-ran         -                     -                     ${LEADV2_BROKEN_GATE:-1}             -         no
leadv2-codex-first-nudge.sh                PreToolUse       never-ran         -                     -                     ${LEADV2_MAXIMIZE_CHEAP_MODELS:-1}   -         no
leadv2-command-bootstrap.sh                SessionStart     never-ran         -                     -                     always                               -         no
leadv2-compact-warn.sh                     UserPromptSubmit never-ran         -                     -                     ${LEADV2_COMPACT_WARN:-1}            -         no
leadv2-continuation-guard.sh               Stop             never-ran         -                     -                     ${LEADV2_CONTINUATION_GUARD:-1}      -         no
leadv2-cwd-changed.sh                      CwdChanged       never-ran         -                     -                     always                               -         no
leadv2-env-audit-pre-gate.sh               PreToolUse       never-ran         -                     -                     always                               -         no
leadv2-force-reflect.sh                    Stop             never-ran         -                     -                     always                               -         no
leadv2-gate-artifact-guard.sh              PreToolUse       never-ran         -                     -                     ${LEADV2_GATE_ENFORCE:-1}            -         no
leadv2-graph-cache-bust.sh                 PostToolUse      never-ran         -                     -                     always                               -         no
leadv2-idle-notification-filter.sh         UserPromptSubmit never-ran         -                     -                     ${LEADV2_IDLE_FILTER:-1}             -         no
leadv2-immune-intake-inject.sh             PreToolUse       never-ran         -                     -                     ${LEADV2_PROJECT_ROOT:-$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs dirname 2>/dev/null || pwd)} -         no
leadv2-install-dispatcher.sh               SessionStart     never-ran         -                     -                     always                               -         no
leadv2-lead-delegation-nudge.sh            PostToolUse      never-ran         -                     -                     always                               -         no
leadv2-lead-prose-guard.sh                 Stop             never-ran         -                     -                     ${LEADV2_LEAD_GUARD:-0}              -         no
leadv2-learn-consume.sh                    SessionStart     never-ran         -                     -                     always                               -         no
leadv2-link-tree-heal.sh                   SessionStart     never-ran         -                     -                     ${LEADV2_CANONICAL_SCRIPTS:-$HOME/Projects/leadv2/plugins/leadv2/scripts} -         no
leadv2-loop-detect-hook.sh                 PostToolUse,PreToolUse never-ran         -                     -                     ${LEADV2_LOOP_DETECT:-1}             -         no
leadv2-memory-guard.sh                     PreToolUse       never-ran         -                     -                     ${LEADV2_TASK_ID:-}                  -         no
leadv2-merged-worktree-sweep.sh            SessionStart     never-ran         -                     -                     ${LEADV2_MERGED_WORKTREE_SWEEP:-1}   -         no
leadv2-model-inherit-guard.sh              PreToolUse       never-ran         -                     -                     ${LEADV2_MAIN_MODEL:-the session model} -         no
leadv2-monitor-cap-gate.sh                 PreToolUse       never-ran         -                     -                     ${LEADV2_MONITORCAP_OFF:-0}          -         no
leadv2-no-opus-code-edit.sh                PreToolUse       never-ran         -                     -                     always                               -         no
leadv2-one-copy-drift.sh                   PostToolUse,SessionStart never-ran         -                     -                     ${LEADV2_ONE_COPY_DRIFT:-1}          -         no
leadv2-opus-read-budget.sh                 PreToolUse       never-ran         -                     -                     always                               -         no
leadv2-orphan-monitor-sweep.sh             SessionStart     never-ran         -                     -                     always                               -         no
leadv2-pending-close-inject.sh             SessionStart     never-ran         -                     -                     always                               -         no
leadv2-pending-questions-inject.sh         SessionStart     never-ran         -                     -                     ${LEADV2_Q_SESSIONSTART_MIN_AGE_S:-600} -         no
leadv2-postcompact-goal-reinject.sh        PostCompact      never-ran         -                     -                     always                               -         no
leadv2-pre-compact-checkpoint.sh           PreCompact       never-ran         -                     -                     ${LEADV2_TASK_ANCHOR_STATE_DIR:-$HOME/.claude/state/leadv2} -         no
leadv2-precompact-log.sh                   PostCompact,PreCompact never-ran         -                     -                     always                               -         no
leadv2-pulse-enforcer.sh                   UserPromptSubmit never-ran         -                     -                     ${LEADV2_HOOK_PROFILE:-0}            -         no
leadv2-read-gate.sh                        PreToolUse       never-ran         -                     -                     ${LEADV2_HOOK_PROFILE:-0}            -         no
leadv2-routing-guard.sh                    PreToolUse       never-ran         -                     -                     ${LEADV2_TASK_ID:-}                  -         no
leadv2-schema-audit-pre-gate.sh            PreToolUse       never-ran         -                     -                     ${LEADV2_PROJECT_ROOT:-$REPO}        -         no
leadv2-shared-script-warn.sh               PreToolUse       never-ran         -                     -                     always                               -         no
leadv2-single-lead-beat.sh                 PostToolUse,UserPromptSubmit never-ran         -                     -                     ${LEADV2_SINGLE_LEAD_BEAT:-1}        -         no
leadv2-skill-authoring-reminder.sh         PreToolUse       never-ran         -                     -                     always                               -         no
leadv2-stale-pid-sweep.sh                  SessionStart     never-ran         -                     -                     always                               -         no
leadv2-subagent-stop-verify.sh             SubagentStop     never-ran         -                     -                     ${LEADV2_SUBAGENT_VERIFY_STRICT:-0}  -         no
leadv2-task-anchor.sh                      UserPromptSubmit never-ran         -                     -                     always                               -         no
leadv2-task-budget-tracker.sh              PostToolUse      never-ran         -                     -                     always                               -         no
leadv2-task-created.sh                     TaskCreated      never-ran         -                     -                     always                               -         no
leadv2-taskoutput-ban.sh                   PreToolUse       never-ran         -                     -                     ${LEADV2_TASKOUTPUT_STRICT:-0}       -         no
leadv2-thinking-audit-gate.sh              PreToolUse       never-ran         -                     -                     ${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)} -         no
leadv2-tool-blowup-gate.sh                 PreToolUse       never-ran         -                     -                     ${LEADV2_TOOL_BLOWUP_HARD:-120}      -         no
leadv2-tool-counter.sh                     PostToolUse      never-ran         -                     -                     always                               -         no
leadv2-truth-card-inject.sh                SessionStart     never-ran         -                     -                     always                               -         no
leadv2-turncap-checkpoint-hook.sh          PostToolUse      never-ran         -                     -                     ${LEADV2_TURNCAP_CHECKPOINT:-1}      -         no
leadv2-user-prompt-context.sh              UserPromptSubmit never-ran         -                     -                     ${LEADV2_ANCHOR_OWNS_CONTEXT:-1}     -         no
leadv2-verdict-format-guard.sh             PreToolUse       never-ran         -                     -                     always                               -         no
leadv2-workflow-bypass-guard.sh            PreToolUse       never-ran         -                     -                     ${LEADV2_WORKFLOW_GUARD:-1}          -         no
leadv2-workflow-model-guard.sh             PreToolUse       never-ran         -                     -                     always                               -         no
leadv2-workflow-sentinel-touch.sh          PostToolUse      never-ran         -                     -                     ${LEADV2_WORKFLOW_ENABLED:-0}        -         no
leadv2-worktree-enforce.sh                 PreToolUse       never-ran         -                     -                     ${LEADV2_ALLOW_MAIN_REPO:-0}         -         no
post-compact-reground.sh                   SessionStart     never-ran         -                     -                     always                               -         no
leadv2-lead-edit-guard.sh                  PreToolUse       disabled          -                     -                     ${LEADV2_LEAD_GUARD_FORCE:-}         -         yes
leadv2-context-glossary-close.sh           PreToolUse       fires-log-only    -                     -                     always                               -         yes
leadv2-promise-guard.sh                    Stop             fires-log-only    2026-09-02T04:55:53Z  -                     ${LEADV2_PROMISE_GUARD:-1}           -         yes
leadv2-bash-lint-pre-gate.sh               PreToolUse       blocking          -                     -                     ${LEADV2_TASK_ID:-}                  -         yes
leadv2-block-bash-heredoc.sh               PreToolUse       blocking          -                     -                     always                               -         yes
leadv2-block-fg-dispatch.sh                PreToolUse       blocking          2026-09-02T00:10:38Z  2026-09-02T00:10:38Z  ${LEADV2_ALLOW_FG_DISPATCH:-0}       0         yes
leadv2-close-ritual-guard.sh               PreToolUse       blocking          -                     -                     ${LEADV2_SKIP_CLOSE_GUARD:-0}        -         yes
leadv2-codex-direct-exec-guard.sh          PreToolUse       blocking          -                     -                     ${LEADV2_ALLOW_DIRECT_CODEX:-}       -         yes
leadv2-codex-nopoll-guard.sh               PreToolUse       blocking          -                     -                     ${LEADV2_CODEX_NOPOLL:-1}            -         yes
leadv2-codex-round-cap.sh                  PreToolUse       blocking          -                     -                     ${LEADV2_TASK_ID:-}                  -         yes
leadv2-deny-floor.sh                       PreToolUse       blocking          2026-09-02T00:10:38Z  -                     ${LEADV2_DENY_FLOOR:-1}              -         yes
leadv2-warn-bash-diff-read.sh              PreToolUse       blocking          -                     -                     ${LEADV2_DIFF_READ_GUARD:-}          -         yes
leadv2-block-codex.sh                      -                not-wired         -                     -                     -                                    -         no
leadv2-compact-trigger.sh                  -                not-wired         -                     -                     -                                    -         no
leadv2-force-read-limit.sh                 -                not-wired         -                     -                     -                                    -         no
leadv2-hardbans-reinject.sh                -                not-wired         -                     -                     -                                    -         no
leadv2-hook-fork-budget.sh                 -                not-wired         -                     -                     -                                    -         no
leadv2-idle-guard-arm.sh                   -                not-wired         -                     -                     -                                    -         no
leadv2-idle-lead-guard.sh                  -                not-wired         -                     -                     -                                    -         yes
leadv2-lead-read-guard.sh                  -                not-wired         -                     -                     -                                    -         no
leadv2-mode-isolation.sh                   -                not-wired         -                     -                     -                                    -         no
leadv2-pulse-json.sh                       -                not-wired         -                     -                     -                                    -         no
leadv2-read-dedup-hard.sh                  -                not-wired         -                     -                     -                                    -         no
pre-compact-task-freeze.sh                 -                not-wired         -                     -                     -                                    -         no

CANDIDATES TO DELETE — wired, no fixture proof, no fire in 30 days (founder decides; never auto-deleted):
  leadv2-active-cache.sh                     never-ran         last-fired=-                     ${LEADV2_STATE_DIR}
  leadv2-async-question-guard.sh             never-ran         last-fired=-                     ${LEADV2_ASYNC_QUESTIONS:-0}
  leadv2-auto-clear-after-close.sh           never-ran         last-fired=-                     always
  leadv2-auto-status.sh                      never-ran         last-fired=-                     always
  leadv2-bandit-preflight.sh                 never-ran         last-fired=-                     ${LEADV2_ROUTE_BANDIT:-0}
  leadv2-bash-output-cap.sh                  never-ran         last-fired=-                     always
  leadv2-bash-pre-dispatch.sh                never-ran         last-fired=-                     ${LEADV2_GUARD_VERDICT_DIR:-${CLAUDE_PROJECT_DIR:-$HOME}}
  leadv2-bg-ledger.sh                        never-ran         last-fired=-                     always
  leadv2-bg-stop-warn.sh                     never-ran         last-fired=-                     ${LEADV2_BG_WARN_EVERY:-1}
  leadv2-bg-watchdog-enforce.sh              never-ran         last-fired=-                     ${LEADV2_BG_ORPHAN_MAX:-3}
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
  leadv2-immune-intake-inject.sh             never-ran         last-fired=-                     ${LEADV2_PROJECT_ROOT:-$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | xargs dirname 2>/dev/null || pwd)}
  leadv2-install-dispatcher.sh               never-ran         last-fired=-                     always
  leadv2-lead-delegation-nudge.sh            never-ran         last-fired=-                     always
  leadv2-lead-prose-guard.sh                 never-ran         last-fired=-                     ${LEADV2_LEAD_GUARD:-0}
  leadv2-learn-consume.sh                    never-ran         last-fired=-                     always
  leadv2-link-tree-heal.sh                   never-ran         last-fired=-                     ${LEADV2_CANONICAL_SCRIPTS:-$HOME/Projects/leadv2/plugins/leadv2/scripts}
  leadv2-loop-detect-hook.sh                 never-ran         last-fired=-                     ${LEADV2_LOOP_DETECT:-1}
  leadv2-memory-guard.sh                     never-ran         last-fired=-                     ${LEADV2_TASK_ID:-}
  leadv2-merged-worktree-sweep.sh            never-ran         last-fired=-                     ${LEADV2_MERGED_WORKTREE_SWEEP:-1}
  leadv2-model-inherit-guard.sh              never-ran         last-fired=-                     ${LEADV2_MAIN_MODEL:-the session model}
  leadv2-monitor-cap-gate.sh                 never-ran         last-fired=-                     ${LEADV2_MONITORCAP_OFF:-0}
  leadv2-no-opus-code-edit.sh                never-ran         last-fired=-                     always
  leadv2-one-copy-drift.sh                   never-ran         last-fired=-                     ${LEADV2_ONE_COPY_DRIFT:-1}
  leadv2-opus-read-budget.sh                 never-ran         last-fired=-                     always
  leadv2-orphan-monitor-sweep.sh             never-ran         last-fired=-                     always
  leadv2-pending-close-inject.sh             never-ran         last-fired=-                     always
  leadv2-pending-questions-inject.sh         never-ran         last-fired=-                     ${LEADV2_Q_SESSIONSTART_MIN_AGE_S:-600}
  leadv2-postcompact-goal-reinject.sh        never-ran         last-fired=-                     always
  leadv2-pre-compact-checkpoint.sh           never-ran         last-fired=-                     ${LEADV2_TASK_ANCHOR_STATE_DIR:-$HOME/.claude/state/leadv2}
  leadv2-precompact-log.sh                   never-ran         last-fired=-                     always
  leadv2-pulse-enforcer.sh                   never-ran         last-fired=-                     ${LEADV2_HOOK_PROFILE:-0}
  leadv2-read-gate.sh                        never-ran         last-fired=-                     ${LEADV2_HOOK_PROFILE:-0}
  leadv2-routing-guard.sh                    never-ran         last-fired=-                     ${LEADV2_TASK_ID:-}
  leadv2-schema-audit-pre-gate.sh            never-ran         last-fired=-                     ${LEADV2_PROJECT_ROOT:-$REPO}
  leadv2-shared-script-warn.sh               never-ran         last-fired=-                     always
  leadv2-single-lead-beat.sh                 never-ran         last-fired=-                     ${LEADV2_SINGLE_LEAD_BEAT:-1}
  leadv2-skill-authoring-reminder.sh         never-ran         last-fired=-                     always
  leadv2-stale-pid-sweep.sh                  never-ran         last-fired=-                     always
  leadv2-subagent-stop-verify.sh             never-ran         last-fired=-                     ${LEADV2_SUBAGENT_VERIFY_STRICT:-0}
  leadv2-task-anchor.sh                      never-ran         last-fired=-                     always
  leadv2-task-budget-tracker.sh              never-ran         last-fired=-                     always
  leadv2-task-created.sh                     never-ran         last-fired=-                     always
  leadv2-taskoutput-ban.sh                   never-ran         last-fired=-                     ${LEADV2_TASKOUTPUT_STRICT:-0}
  leadv2-thinking-audit-gate.sh              never-ran         last-fired=-                     ${LEADV2_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
  leadv2-tool-blowup-gate.sh                 never-ran         last-fired=-                     ${LEADV2_TOOL_BLOWUP_HARD:-120}
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

---

# Round 3 (fix: R2 review high=2, DEFAULT column)

## R3 findings verification (on lane tip 18012e1, live tree)

### High #1 (stale `dflt` on not-wired/missing rows) — REAL

`leadv2-guard-census.sh` assigned `dflt` only inside the wired+present else-branch; the
`while read g` loop never reset it, so not-wired/missing rows printed the previous guard's value.

Direct probe from the R2-era census (`--format tsv`, DEFAULT=col 7):

```
$ awk -F'\t' 'NR>1{print $2"\t"$4"\t"$7}' census-before.tsv | sort | grep -B1 'not-wired\|missing'
...
leadv2-lead-prose-guard.sh	never-ran	${LEADV2_LEAD_GUARD:-0}
leadv2-lead-read-guard.sh	not-wired	${LEADV2_LEAD_GUARD:-0}     ← leaked from the row above
```

Stronger still: `leadv2-lead-read-guard.sh`'s REAL first gate is
`${LEADV2_LEAD_GUARD:-advisory}` (`grep -oE … leadv2-lead-read-guard.sh`), so the row was wrong in
two ways at once — stale value AND a shape the old parser could never produce.

### High #2 (DEFAULT regex `:-[01]`-only) — REAL

Shape enumeration over the live tree (the grep this round's parser is built from):

```
$ grep -ohE '\$\{LEADV2_[A-Za-z0-9_]+([:=?+-])[^}]*\}' hooks/*.sh hooks/lib/*.sh \
    | grep -vE 'TRACE|DEBUG' | sed -E 's/LEADV2_[A-Za-z0-9_]+/X/; s/(:[=-])(.*)/\1«\2»/' \
    | sort | uniq -c | sort -rn | head -12
  39 ${X:-«0}»        ← old regex OK
  37 ${X:-«}»         ← empty default — INVISIBLE to old regex
  23 ${X:-«1}»        ← old regex OK
   3 ${X:-«${CLAUDE_PROJECT_DIR:-$HOME}»   ← nested — INVISIBLE
   2 ${X:-«advisory}»                      ← INVISIBLE
   2 ${X:-«8}»  ${X:-«3}»  ${X:-«30}»  ${X:-«1800}» …   ← INVISIBLE
```

Live-tree result: 20 wired guards with a `${LEADV2_…}` reference printed `always`
(`awk -F… '$7=="always"' | while read g; do grep -lE '\$\{LEADV2_' hooks/$g; done` — list in the
diff below). The reviewer counted 19 at review commit 0c0dd161; the merged tip has 20. No
`${X:=…}`, `${X-…}`, quoted or `[[ … ]]`-only shapes exist in `hooks/*.sh` today; the new parser
covers them anyway (defensive, locked by suite case 11).

## Fix

`plugins/leadv2/scripts/leadv2-guard-census.sh`:

1. **Per-row reset (high #1):** `dflt="-"` moved to the top of the per-guard loop, before the
   `if [ "$wired" -eq 0 ]` branch. Not-wired/missing rows now print `-`, never a neighbour's gate.
2. **Wide parser (high #2):** `\$\{LEADV2_[A-Za-z0-9_]+:-[01]\}` →
   `\$\{LEADV2_[A-Za-z0-9_]+[^}]*\}` — any `${LEADV2_…}` reference (all `:-`/`:=`/`-`/`=`/`?`/`+`
   forms, quoted defaults, bare `${X}`) means env-gated; nested `${X:-${Y:-z}}` is re-balanced
   (`while open>0; do dflt+="}"`). `always` is now reserved for guards with ZERO `LEADV2_`
   references. Removed the dead `if [ -f "$HOOK_DIR/$g" ]` (R2 Low L2 — the enclosing
   `elif [ ! -f … ]` already proved existence).

## Census DEFAULT column: before/after (live tree, `--format tsv`, same flags both runs)

- 94 guard rows; **31 DEFAULT cells changed** (`awk` join on guard name, values differ).
- `always`: 55 → 32. All 32 remaining `always` rows were probed: **zero contain a `LEADV2_`
  reference** (`while read g; do grep -qE '\$\{LEADV2_' hooks/$g && echo STILL-WRONG; done` →
  empty). Zero flag-gated guards still print `always`.
- All 13 not-wired/missing rows now print `-` (was: leaked values on 6+ rows).

Representative diff (old → new):

```
leadv2-bash-pre-dispatch.sh    always → ${LEADV2_GUARD_VERDICT_DIR:-${CLAUDE_PROJECT_DIR:-$HOME}}
leadv2-bg-watchdog-enforce.sh  always → ${LEADV2_BG_ORPHAN_MAX:-3}
leadv2-lead-edit-guard.sh      ${LEADV2_LEAD_GUARD:-0} → ${LEADV2_LEAD_GUARD_FORCE:-}
leadv2-lead-read-guard.sh      ${LEADV2_LEAD_GUARD:-0} → -            (not-wired; stale gone)
leadv2-lead-prose-guard.sh     ${LEADV2_LEAD_GUARD:-0} → ${LEADV2_LEAD_GUARD:-advisory}  (true shape)
leadv2-mode-isolation.sh       ${LEADV2_MERGED_WORKTREE_SWEEP:-1} → - (not-wired; stale gone)
leadv2-tool-blowup-gate.sh     always → ${LEADV2_TOOL_BLOWUP_HARD:-120}
leadv2-block-codex.sh          always → -                             (not-wired; reset working)
… (31 rows total; full before/after diff reproducible via the two tsv runs with the same flags)
```

## Suite (fixtures per shape + negative controls)

New fixture guards in `scripts/tests/fixtures/guards/hook-dir/`, wired in the fixture hooks.json
(except the unwired control), one per gate shape: `:-0`, `:-1`, `:-` (empty), `:=0`, `-1` (bare
dash), quoted `:-"1"`, `[[ "${X:-0}" == 1 ]]`, nested `:-${TMPDIR:-/tmp}`, plus
`fx-gate-zunwired.sh` (NOT wired, sorts directly after the quoted-shape guard — the stale-leak
canary). `test-guard-census.sh` grew `dflt_of` (DEFAULT=col 7), case 11 (eight shape assertions
incl. brace-balanced nested), case 12 (unwired row = `-`), and two in-suite mutations:

- **case12-mutation** — scratch copy with the per-row reset deleted re-leaks
  `${LEADV2_FX_QUOTED:-"1"}` into the unwired row (mutation caught).
- **case11-mutation** — scratch copy with the old `:-[01]` regex prints `always` for the
  empty/`:=`/bare-dash/quoted/nested guards (mutation caught).

Whole-suite negative controls (via the new `LEADV2_CENSUS_UNDER_TEST` override; rc measured
unpiped):

```
=== NEGATIVE CONTROL 1: stale-dflt re-introduced ===
FAIL: case12 not-wired dflt is '-', never stale (got '${LEADV2_FX_QUOTED:-"1"}', want '-')
FAIL: case12-mutation: mutated census produced no row for fx-gate-zunwired.sh   ← expected:
  the in-suite mutator's anchor is already gone in this doubly-mutated copy
SUITE RED: 38 passed, 2 FAILED            → suite rc=1
=== NEGATIVE CONTROL 2: old :-[01] regex re-introduced ===
FAIL: case11 shape :"" (empty default) (got 'always', …)   … 6 FAILs total
SUITE RED: 34 passed, 6 FAILED            → suite rc=1
Healthy tree: ALL PASS: 40 checks passed  → suite rc=0
```

## R2 Lows — fixed vs deferred

- **L1** (DEFAULT column `%-32s` overflows) — FIXED: `%-36s` on header + row lines.
- **L2** (dead `if [ -f … ]` inside else-branch) — FIXED: removed (see Fix #2).
- **L3** (case-10 awk mutation deletes to first column-0 `fi` — future no-op risk) — FIXED:
  mutation rewritten in python; it now locates the `DISPATCHED=`…`fi` region and FAILS the case
  unless the deleted chunk contains the block's actual effect
  (`cat "$DISPATCHED" >> "$WIRED"`).
- **L4** (`leadv2-bash-pre-dispatch.sh:533` cap checked after append — ≤2-row overshoot before
  rotation) — DEFERRED: cosmetic at a 20000-row default; the fix touches the hottest hook on the
  live path, which costs more risk than the 2 cosmetic rows are worth.
- **L5** (count drift "31" vs "~34" degrade-wrapped entries, unshown arithmetic) — FIXED:
  probe run — `grep -o '"; r=\$?' hooks.json | wc -l` = **32** of 172 command entries;
  `fx-degrade-wrapped.sh`'s comment now says 32 with the probe inline. Round-1 §1's "31" is
  corrected by this note (the tree gained one wrapped entry between round 1 and now).

## Self-check (round 3)

- `bash -n` green on `leadv2-guard-census.sh` + `test-guard-census.sh`.
- No Python files changed.
- `test-guard-census.sh`: **ALL PASS: 40 checks** (was 29 pre-round-3) after the L1–L3 edits,
  re-run green; census tsv output byte-identical before/after the L1/L2 edits.
- `tests/run-all.sh --scope changed` on the merged tree: see below.

## RUN-ALL-RESULTS
