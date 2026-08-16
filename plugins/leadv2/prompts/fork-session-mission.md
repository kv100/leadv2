# MISSION — fork-owned /leadv2 session: <TASK_ID>, Phase 0 → 8

You are a FORK carrying one task, <TASK_ID>, end to end. You inherited the lead's
context; you are not starting cold. The lead created your lane and will reap it —
you never manage the worktree yourself.

**No lane, no fork.** If `preflight` refused (exit 1), there is no fork session:
the lead runs the task itself. A fork never degrades to working in the shared
checkout — that is the 2026-07-28 mutual-clobber incident by construction.

## Your lane (fill before use)

- `TASK_ID=<task-id>` · `LANE_ROOT=<abs lane root>` · read `<LANE_ROOT>/docs/handoff/<TASK_ID>/fork-lane.env` first.
- Source the mission with concrete values via the lead's spawn prompt; this template is the shape.

## Absolute-path rule (non-negotiable)

You share the session CWD with the lead. **Every file you touch, you address by
absolute path under `LANE_ROOT`.** Never `cd`. Never a bare relative path for
anything under the lane. Changing CWD would move the lead mid-task.

## Never-call list

`EnterWorktree` · `ExitWorktree` · `cd` · a **bare `git` command** (any git
invocation that does not carry `-C "$LANE_ROOT"` or go through the `commit`
wrapper below — with the session CWD at the lead checkout, a bare `git` targets
the LEAD's branch, not yours) · `leadv2-worktree-cleanup.sh` ·
`leadv2-self-spawn.sh` · `git reset --hard` · `git clean` · `git stash`.
The first two are lead-only by CWD-lifecycle law; the bare-git ban is why Phase 6
has a wrapper; the next two are the lead's pre/postflight carve-outs; the last
three are the shared-tree prohibition.

## Phases

- **0 Intake** — inside the lane (it already exists; `preflight` made it): STATE.md,
  journal via `leadv2-journal.sh`, absolute paths.
- **1 Classify** — pure reasoning over inherited context. Class: ____
- **2 Plan** — spawn your role agents (`run_in_background=true`, explicit `model=`);
  Codex/GLM arms are external processes, spawn them as such.
- **3 Gate 1 — ask the founder:**
  `bash <plugin>/scripts/leadv2-fork-session.sh ask <TASK_ID> "<question>" --option "a|<label>" --option "b|<label>" --default-option "a"`
  exit 0 → chosen label on stdout, proceed; **exit 3 → the gate is NOT passed** —
  continue ungated work if any, re-invoke later to resume polling the SAME
  question, and do not enter Phase 4 or any step this gate protects until you
  see exit 0. A fork cannot self-clear its own gate. The question appears in
  `/leadv2 questions`; the founder answers through the lead's existing surface.
  Do NOT use AskUserQuestion.
- **4 Build** — absolute paths under LANE_ROOT only.
- **5 Review** — unchanged gates. No gate is relaxed for a fork.
- **6 Deploy** — commit into the lane via the wrapper:
  `bash <plugin>/scripts/leadv2-fork-session.sh commit <TASK_ID> -m "<msg>" --all`
  (or `--paths <p> …`). Every git operation you run yourself is either this
  wrapper or an explicit `git -C "$LANE_ROOT" …`. Then land via
  `(cd <PROJECT_ROOT> && LEADV2_TASK_ID=<TASK_ID> CLAUDE_PLUGIN_ROOT=<plugin>   bash <plugin>/scripts/leadv2-deploy-merge.sh)` (resolves `worktree-<TASK_ID>`).
  That subshell cd is process-local and the ONE legitimate lead-checkout git
  cwd — it invokes an audited lead-side script, not hand-rolled git; the
  session CWD never moves. You never entered a tool worktree, so there is
  nothing to ExitWorktree from.
- **7 Verify** — `verify-probe.sh` against the live signal. "Tests green" is not verification.
- **8 Close** — locked state writes (same scripts N parallel lanes use), then
  `leadv2-phase8-close.sh`. STOP at `phase8-passed.flag`. Reaping and any
  self-spawn are the lead's postflight — not yours.

## Deliverable

`<LANE_ROOT>/docs/handoff/<TASK_ID>/` holds your plan/build/review artifacts; end
your final message with the report naming which phases you ran and DELIVERABLE_COMPLETE.
A phase you did not actually run is reported as handed back, never as owned.
