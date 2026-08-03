# CODEX-FULL-LEAD-FROM-TERMINAL-01 — critic review round 1 (sonnet, 2026-08-03)

Verdict: BLOCK. Fix exactly these; the mechanical bar (tests/syntax/shellcheck/doc/atomicity/no-leakage) is already clean — do not regress it.

## CRITICAL 1 — worktree isolation never reaches the Codex invocation
leadv2-codex-lead.sh launches the runner trampoline (lines 384-387) with NO cd anywhere; the trampoline exports LEADV2_PROJECT_ROOT/CLAUDE_PROJECT_DIR/PROJECT_ROOT = MAIN repo root (lines 29-32), and the runner invokes codex with -C "$PROJECT_ROOT" (leadv2-codex-session-runner.sh:455). Isolation currently depends on Codex's self-driven Phase-0 worktree entry — the exact defect SD-LANES-HAVE-NO-WORKTREE-01 already fixed in fanout by an external deterministic `cd "$_lane_dir"` before exec'ing the SAME runner (leadv2-fanout.sh:1157-1162). Risk: Codex edits/commits the shared main tree.
FIX: mirror fanout — cd into the lane worktree before launching, and point the ROOT env vars at the lane path exactly as fanout does.

## CRITICAL 2 — hand-rolled worktree + symlink alias; alias empirically collides with git worktree add
Wrapper hand-rolls `git worktree add -b $TASK_BRANCH $WORKTREE_PARENT/$SIG8` + `ln -s $SIG8 $WORKTREE_PARENT/$TASK_ID`. Reproduced: a pre-placed symlink at .claude/worktrees/<TASK_ID> makes any later plain `git worktree add .claude/worktrees/<TASK_ID>` die rc=128 "already exists".
FIX: delete the sig8+alias scheme entirely; call the existing idempotent helper `leadv2-lane-worktree.sh ensure "$TASK_ID"` (produces .claude/worktrees/<task_id> + branch worktree-<task_id> — exactly the runner's fixed convention, no alias needed; same helper fanout uses). Update tests accordingly.

## CRITICAL 3 — `next` can pick the "DUPLICATE - DO NOT DISPATCH" row (verified on prod tasks.yaml)
Wrapper takes leadv2_tasks_top_n 1 blindly (lines 80-83). tasks-lib only DEPRIORITIZES unknown priorities (rank 4), never excludes. Real row: persona-engine docs/tasks.yaml id 7f785e9103a0, status queued, priority 999, intent starts "DUPLICATE - DO NOT DISPATCH." — structurally eligible; picked whenever the queue drains to poisoned rows.
FIX in the wrapper's own filter (do not change tasks-lib): when resolving `next`, iterate top_n candidates and skip any row whose priority is non-numeric-standard (not in the known rank set) OR >=900 OR whose intent matches /^DUPLICATE|DO NOT DISPATCH/i; refuse with a clear reason if no eligible row remains. Test: seed a stub tasks.yaml where the top row is the poisoned shape → wrapper must skip it and pick the next eligible; and an all-poisoned queue → non-zero refuse, nothing claimed.

## HIGH 4 — dup-guard ignores the terminal ledger's write-once semantics
Guard reads reservation ledger + job registry + live claim but never the terminal ledger (leadv2-dispatch-ledger.sh via leadv2-state-path.sh; terminals landed|parked|refused|dead|no_work; landed/dead are write-once per 1674dde). A task permanently dead/landed can be re-claimed here.
FIX: add a terminal-ledger read to the dup-guard: refuse when the task's sig has terminal landed (already done) or dead (permanently failed — needs founder/lead re-plan, not an auto redispatch); parked/refused/no_work are allowed but print the prior terminal as a warning line. Test both refusal shapes with a stub state dir.

Verified-correct list (do NOT touch): runner zero-positional env contract; claim/unclaim trap atomicity; nohup detach with </dev/null; planner-pin doc text (byte-accurate); non-tautological tests; no prod-state leakage.
ACCEPTANCE unchanged: bash -n; focused suite green (extend per above); run-core-offline green (23/23 incl. your suite). Do NOT commit.
