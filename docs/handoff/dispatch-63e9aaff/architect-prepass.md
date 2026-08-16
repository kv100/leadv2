# ARCHITECT — FORK-RUNS-FULL-SESSION-01

Scoped implementation design. Design only; no code written here.

---

## 1. What actually blocks a fork today — per phase, from the source

Walked `plugins/leadv2/commands/leadv2.md` (phase spine), `docs/phases.md §Phase 0`, and the
scripts each phase calls. Verdict per phase:

| Phase | Mechanism | Blocks a fork? | Evidence |
|---|---|---|---|
| 0 lock | `leadv2_lock_acquire` → `leadv2_active_register` (`leadv2-helpers.sh:586`, registry `:533`) | **No.** The lock is *per-task*, keyed on `task_id` — not a global "one /leadv2 per repo". Two sessions on two tasks are already legal (that is what fanout does). | `docs/phases.md:77` |
| 0 registry | `active.yaml` row carries `durable_pid`, used as the liveness key (registry `:554`) | **Yes — silently.** A fork is not an OS process; any pid it registers belongs to the *parent* `claude`. The row then reads "alive" for as long as the parent lives — a dead fork is indistinguishable from a working one. This is exactly the failure mode the mission names. | registry `:554` comment |
| 0 worktree | `EnterWorktree(name="<task-id>")` switches session cwd (`docs/phases.md:87`) | **Unknown — the one real unknown.** Whether a `subagent_type="fork"` sub-session may call `EnterWorktree` and get its *own* cwd is not documented anywhere in the repo. Resolved by a probe (§3 Step 1), not by assumption. |
| 1 classify | inline | No | — |
| 1.5 diverge | Agent fan-out | No (out of scope anyway — Standard skips it) | — |
| 2 plan | Agent spawns + `leadv2-codex-planner.sh` | No for Agent arms. Codex/GLM arms are external processes and are already documented as un-forkable (`leadv2.md:153`) — they still work, they just receive context by file. | — |
| 3 Gate 1 | `leadv2-gate1-prompt.sh` | **Yes, two ways.** Non-Heavy: `[[ ! -t 0 ]]` → treated as daemon → `read -r -t 5` → **auto-accept after 5s with nobody asked** (`:186`, `:191`). Heavy/Strategic: bare `read -r` on stdin nobody feeds → **hangs forever** (`:164`). The script has *no* async branch — `grep -n ASYNC scripts/leadv2-gate1-prompt.sh` returns nothing, even though `LEADV2_ASYNC_QUESTIONS` and `leadv2-ask.sh` exist for precisely this. | gate1 `:150–205` |
| 4 build | Agent spawns | No | — |
| 5 review | critic/security Agent spawns | No | — |
| 6 deploy | `ExitWorktree(action="keep")` + `leadv2-deploy-merge.sh` | **Convention only.** The "never delegate ExitWorktree" ban (`leadv2.md:213`) protects a lead whose *own* cwd is the worktree from a subagent yanking it. A fork that entered its own worktree exits its own worktree — the ban's hazard does not apply. Merge is flock-protected already. | `leadv2.md:213` |
| 7 verify | `verify-probe.sh` | No | — |
| 8 close | control-plane writes + `phase8-passed.flag` | **No.** `leadv2-state-path.sh` resolves the control plane *outside* any worktree, identical from every session (documented in `leadv2-ask.sh:8–12`). Fork and parent write the same store safely. | — |

**Summary: two genuine blockers (registry/liveness identity, Gate 1), one unknown (worktree
entry), and one convention that is not a blocker (ExitWorktree).** Everything else already
works — because `leadv2-session-runner.sh` already drives Phase 0..8 for a *headless
`claude -p`* child. This feature is not "make a session runnable"; it is "make the existing
full-session contract survive a caller that has no pid and no tty."

---

## 2. Supported task shape (the narrowest that exercises all nine phases)

**Supported in this pass — exactly one shape:**
`class: Standard`, plugin-repo-only, ≤3 files, no migration, whose Phase 7 `live_signal` is a
`file_artifact` or `log_line` probe against the merged main checkout (not a browser, not a prod
DB, not an HTTP endpoint).

That shape still traverses all nine: worktree + lock (0), Standard classification (1), the full
plan triad (2), a real Gate 1 (3), Agent build (4), critic review with a verdict (5), commit +
ExitWorktree + ff-merge (6), `verify-probe.sh` (7), close + flag (8).

**Explicitly NOT supported yet — the fork must refuse these at launch:**
- `Heavy` / `Strategic` — Gate 1 must block on a human indefinitely; a fork holding an open
  `leadv2-ask.sh` poll for hours is untested and costs an Opus-tier agent slot the whole time.
- Any task whose deploy step calls a project deploy override (non-plugin repos).
- Any task whose live signal needs a browser, a prod DB row, or an external HTTP endpoint.
- Fan-out from inside a fork (a fork spawning a fork) — one level only, §5 R2.
- Codex / GLM / Kimi *lead* arms in a fork. Fork-internal Codex *helper* calls are fine.
- Recovery (Phase 7 exit 1/2) inside the fork — a fork that fails verification stops and reports;
  the parent decides. Recovery-in-fork is a follow-up.

---

## 3. Implementation — ordered, smallest-first

### Step 1 — Worktree probe (blocking, ~5 min, decides the rest)
Spawn one trivial fork whose entire mission is: call `EnterWorktree(name="probe-fork-wt")`,
report `pwd` + `git branch --show-current`, call `ExitWorktree(action="discard")`, write the
result to the report. Three outcomes:
- **A. Fork gets its own worktree cwd** → adopt the lead-identical path: fork calls
  `EnterWorktree` in Phase 0 and `ExitWorktree(action="keep")` in Phase 6. Nothing else changes.
- **B. `EnterWorktree` unavailable/affects the parent** → spawn the fork with
  `isolation: "worktree"` and have Phase 6 commit on that branch, with the *parent* running
  `leadv2-deploy-merge.sh`. This splits Phase 6 across two sessions and must be recorded as a
  deviation in the report.
- **C. Neither works** → the feature ships worktree-less for the supported shape (plugin repo,
  ≤3 files, no migration is safe on a task branch created by plain `git worktree add` from a
  Bash call inside the fork) — and that fallback is stated as a limitation, not hidden.

Record the outcome verbatim in the report. Do not proceed to Step 3 before this resolves.

### Step 2 — Gate 1 async branch (`leadv2-gate1-prompt.sh`)
Insert one branch **after** the existing `LEADV2_DRY_RUN` / `LEADV2_BOT_MODE` early-exits and
**before** the Heavy `read -r` case:

```
if [[ "${LEADV2_ASYNC_QUESTIONS:-0}" == "1" || "${LEADV2_FORK_SESSION:-0}" == "1" ]]; then
  # route to the control-plane question channel; never touch stdin
  leadv2-ask.sh "$task_id" "Gate 1 — <class>: <plan_summary>" \
      --option "go|принять план и строить" --option "n|отклонить, переделать план" \
      [--default-option go]        # non-Heavy ONLY
      --timeout "${LEADV2_GATE1_ASK_TIMEOUT_SEC:-900}"
fi
```
Contract preserved exactly: stdout label `go` → exit 0; `n` → exit 1; a
`decided_by=timeout_default` / `decided_by=architect` resolution → exit 2. The existing ledger
emit and `_gate1_register_active` calls stay on every path.

Two rules that are the whole point of the branch:
- **Heavy/Strategic get NO `--default-option` and run with `LEADV2_ASK_ARCHITECT_FALLBACK=0`.**
  There is no path on which a Heavy plan is accepted without a typed human answer. On timeout the
  fork re-asks rather than deciding.
- **Non-Heavy keeps today's degrade-to-accept semantics but stops being silent.** Where the
  current code accepts after 5s of an unread tty, the new path leaves a question record in the
  control plane with `decided_by=timeout_default` — visible in `/leadv2 questions` and in the
  answered YAML afterwards. Same outcome, auditable.

This patch is independently valuable: it fixes the same silent auto-accept for every
`LEADV2_ASYNC_QUESTIONS=1` fanout child that exists today.

### Step 3 — Fork session identity + anti-collision (`leadv2-fork-session.sh`, new)
A parent-side launcher/guard script, invoked by the lead *before* the `Agent(fork)` spawn. It:
1. Refuses if `LEADV2_FORK_SESSION=1` is already set → **one level of forking, enforced**.
2. Refuses if `task_id` already has a row in `active.yaml` (parent, or another session, already
   owns it) → **the collision answer**: the fork and any other session compete for the *same
   per-task lock they already competed for*. No new lock primitive is introduced; the fork simply
   becomes another legitimate claimant of a task-scoped lock, and the launcher never spawns a
   second claimant for one task.
3. Refuses a class it does not support (§2), determined from the task brief / prior classify.
4. Emits the env contract the fork's mission carries:
   `LEADV2_FORK_SESSION=1`, `LEADV2_SESSION_KIND=fork`, `LEADV2_ASYNC_QUESTIONS=1`,
   `LEADV2_DAEMON=0` (**critical** — `DAEMON=1` would re-arm the 5s auto-accept), `LEADV2_TASK_ID`.
5. Prints the cost estimate (`leadv2-cost-estimate.sh`) — a fork runs at the *lead's* model
   (`leadv2.md:151`), so a full session in a fork is an Opus-priced session.

### Step 4 — Registry: a fork row that cannot lie about being alive
`leadv2-active-registry.sh`: add `session_kind` to the register op (default `lead`, values
`lead|fanout|fork`). For `session_kind: fork`:
- register `pid: null` — **never** the parent's pid;
- exclude the row from pid-based stale sweeps (a null pid must not be read as "gone" either);
- `leadv2-lane-liveness.sh`: a fork row's verdict ceiling is `running_stale`, the same rule
  already applied to Codex/GLM rows that carry no local pid (`leadv2-lane-heartbeat.sh:28–33`).
  A fork resolves to `dead` only when heartbeat is stale **and** the parent has observed the
  Agent task terminate — the parent supplies that, the reader never guesses it.

### Step 5 — Liveness: wire the producer that was left as follow-up
`leadv2-lane-heartbeat.sh` already has `beat` / `mark_finished` ops and one authoritative reader;
its header states outright that **no producer is wired yet**. The fork becomes the first producer:
- `beat <task-id>` at **every phase boundary** (the fork already writes a phase pulse there — one
  extra Bash call, no new cadence to maintain);
- `mark_finished <task-id> --evidence docs/handoff/<id>/phase8-passed.flag` at Phase 8, so the
  parent sees `completed` and not `finished_empty`.
- Parent side: **one** `Monitor` per fork, watching the liveness verdict and filtered to the
  single terminal line, then closing. One watcher per lane, never two — every notification is
  permanent context.
- Staleness threshold from `LEADV2_FORK_HEARTBEAT_STALE_SEC` (default 1200). Phase 4 builds
  legitimately run long; `running_stale` is the honest "I don't know", not a death sentence.

### Step 6 — Docs + tests
`plugins/leadv2/skills/leadv2-fork-session/SKILL.md` — the fork's operating contract: identity
override (§5 R2), the supported shape, the phase walk, the heartbeat obligation, the refuse-list.
`commands/leadv2.md` — one invocation row + the fork rules under the existing fork section.
`docs/phases.md` — three notes (Phase 0 registration, Phase 3 async gate, Phase 8 mark_finished).
Tests in `scripts/tests/` (165 existing, same shape): `test-gate1-async-route.sh`,
`test-fork-session-guard.sh`, `test-fork-liveness-verdict.sh`.

---

## 4. Data flow — one task, end to end

1. Parent lead runs `leadv2-fork-session.sh --preflight <task-id>` → guard passes, env printed.
2. Parent spawns `Agent(subagent_type="fork", run_in_background=true)` with a ≤100-line mission:
   task id, env contract, identity override, "run Phase 0→8, skip nothing".
3. Parent attaches **one** Monitor on the fork's liveness verdict, then goes quiet.
4. Fork Phase 0: registers `session_kind=fork, pid=null`, acquires the per-task lock, enters its
   worktree (per Step-1 outcome), beats.
5. Fork Phases 1–2: classify Standard, plan triad, `context.yaml` written. Beat per boundary.
6. Fork Phase 3: `leadv2-gate1-prompt.sh` → async branch → question lands in the control plane.
   Founder sees it in the parent's window via `/leadv2 questions`; answers with `/leadv2 reply`.
   Fork's poll returns the label; exit code decides Phase 4 or a plan re-round.
7. Fork Phases 4–5: build + adversarial review. **Review verdict is written to disk** (it is the
   evidence the mission demands), not only spoken in the fork's chat.
8. Fork Phase 6: commit, exit worktree keeping it, ff-merge under the existing merge lock.
9. Fork Phase 7: `verify-probe.sh` against the merged tree. Fail → stop and report (no in-fork
   recovery in this pass).
10. Fork Phase 8: close writes, unregister, `phase8-passed.flag`, `mark_finished` with the flag as
    evidence. Parent's Monitor fires once on the terminal line and closes.

---

## 5. Risks and mitigations

- **R1 — `EnterWorktree` may not work in a fork.** The single load-bearing unknown. Mitigation:
  Step 1 probe before any other work; two named fallbacks; outcome recorded in the report either
  way. Do not design around an assumed answer.
- **R2 — A fork inherits the parent's conversation *and believes it is the parent lead.*** It may
  answer as the supervisor, adopt the parent's open threads, or spawn its own forks. Mitigation:
  the mission opens with a hard identity override ("you are a fork owning exactly task X; you are
  not the supervising lead; you do not touch other tasks"), plus the `LEADV2_FORK_SESSION=1`
  launcher refusal in Step 3.1 as the mechanical backstop. Prompt discipline alone is not enough.
- **R3 — Two sessions on the same task.** Mitigation: no new primitive — the fork claims the same
  per-task lock, and the launcher refuses to spawn when a row already exists. `active.yaml`
  writes stay flock-serialized; parent and fork Bash calls are distinct OS processes with distinct
  fds, so the existing flock holds. **Add a test for concurrent parent+fork registration** — this
  is reasoning, not yet an observation.
- **R4 — Gate 1 auto-accepting because nobody is at the tty.** The mission's explicit fear.
  Mitigation: Step 2's two rules — Heavy never gets a default option; non-Heavy's degrade leaves
  an auditable question record instead of a 5-second silence.
- **R5 — A dead fork looking identical to a working one.** Mitigation: Step 4 (never register a
  borrowed pid) + Step 5 (heartbeat producer, `running_stale` as an honest third state, terminal
  evidence required for `completed`).
- **R6 — Cost.** A fork ignores `model=` and runs at lead tier. A full nine-phase session at Opus
  price is the single most expensive spawn shape in the system. Mitigation: Standard-only scope,
  the launcher prints the estimate, existing cost-estimate/premortem gates still apply inside.
- **R7 — Parent compaction mid-fork.** The fork's inherited context is a snapshot; unaffected. The
  parent's knowledge is not — mitigation: everything the parent needs (task id, verdict, liveness)
  is on disk and re-derivable from `active.yaml` + the journal after compact.
- **R8 — Merge race parent↔fork on `main`.** Mitigation: existing merge lock, plus the fork
  re-runs `leadv2-main-sync.sh` immediately before Phase 6 merge, not only at Phase 0.

### Constraint checklist
1. **Env naming** — all new vars use the `LEADV2_*` prefix (`LEADV2_FORK_SESSION`,
   `LEADV2_SESSION_KIND`, `LEADV2_GATE1_ASK_TIMEOUT_SEC`, `LEADV2_FORK_HEARTBEAT_STALE_SEC`). No
   `LEAD_V2_*` form introduced. `LEADV2_DAEMON=0` is a *reuse* with inverted-from-fanout value —
   flagged deliberately in §3 Step 3.4 because setting it to 1 silently restores the 5s
   auto-accept this design exists to remove.
2. **Paths** — verified by listing. Existing on disk: `leadv2-gate1-prompt.sh`,
   `leadv2-active-registry.sh`, `leadv2-lane-heartbeat.sh`, `leadv2-lane-liveness.sh`,
   `commands/leadv2.md`, `docs/phases.md`, `scripts/tests/`. To-create:
   `leadv2-fork-session.sh`, the three `test-*.sh` files,
   `skills/leadv2-fork-session/SKILL.md`, `docs/missions/FORK-RUNS-FULL-SESSION-01.report.md`.
3. **`claude -p`** — this design introduces **no** `claude -p` invocation. The fork is an in-session
   Agent spawn; `leadv2-session-runner.sh`'s `claude -p` path is untouched.
4. **Concurrent access** — `active.yaml` is written by parent and fork (flock, R3, test required);
   the control-plane `questions/` dir is written by the fork and read/answered by the parent
   (already the fanout contract, unchanged).
5. **Config contradiction** — `LEADV2_ASYNC_QUESTIONS=1` currently means "fanned-out child, route
   questions to the control plane" (`leadv2.md:46`, `session-runner:24`). The fork uses it with
   identical semantics; the Gate-1 branch keyed on it *widens* the existing meaning to Gate 1,
   which is a consistent extension, not a contradiction — and it fixes today's fanout children too.

---

## 6. Out of scope for the implementing agent

No changes to Phase 2/4/5 internals, the plan triad, the review loop, or the router. No
supervise-loop or `leadv2-fanout.sh` integration. No tmux/headless changes. No new question UI —
`leadv2-ask.sh` / `/leadv2 reply` are used as-is. No multi-fork fan-out. No in-fork Phase 7
recovery. No `docs/leadv2/**` or `docs/handoff/**` product writes.

---

acceptance:
  - surface: file_artifact
    observable: |
      docs/handoff/<task-id>/phase8-passed.flag exists for a task whose whole Phase 0→8 was
      carried by a fork, and docs/missions/FORK-RUNS-FULL-SESSION-01.report.md contains that
      fork's transcript excerpt showing the Phase 5 review verdict line and the Gate-1 answer.
    authored_at: 2026-08-15T00:02:02Z
  - surface: rendered_line
    observable: |
      While the fork runs, the founder reading /leadv2 questions in the parent window sees the
      fork's Gate-1 question listed as pending with its two options, and after answering, the
      parent's sessions table shows that task's row as a fork whose verdict moves running →
      completed rather than staying alive because the parent process is alive.
    authored_at: 2026-08-15T00:02:02Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-gate1-prompt.sh, plugins/leadv2/scripts/leadv2-fork-session.sh, plugins/leadv2/scripts/leadv2-active-registry.sh, plugins/leadv2/scripts/leadv2-lane-heartbeat.sh, plugins/leadv2/scripts/leadv2-lane-liveness.sh, plugins/leadv2/scripts/tests/test-gate1-async-route.sh, plugins/leadv2/scripts/tests/test-fork-session-guard.sh, plugins/leadv2/scripts/tests/test-fork-liveness-verdict.sh, plugins/leadv2/skills/leadv2-fork-session/SKILL.md, plugins/leadv2/commands/leadv2.md, plugins/leadv2/docs/phases.md, docs/missions/FORK-RUNS-FULL-SESSION-01.report.md

DELIVERABLE_COMPLETE
