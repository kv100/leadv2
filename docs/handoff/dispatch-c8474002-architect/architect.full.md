# CODEX-LEAD-PILOT-PREP-01 — architect prepass (mechanism-closed design)

Task: `dispatch-c8474002-architect` · role: architect · base `2eaea77` · authored 2026-08-24T08:52:53Z

Scope: **docs only**. Two new files under `plugins/leadv2/docs/`. No dispatch script, no hook,
no `hooks.json`, no `AGENTS.md` write. `bash -n` n/a (no shell authored).

---

## 0. Where code contradicts the mission's framing — read this first

Three findings from the tree that the mission's deliverable list does not account for. Each one
changes what the implementer must write.

### 0.1 BLOCKING — `AGENTS.md` already exists in persona-engine and is live product context

Mission text: *"a file the founder copies to the repo root as AGENTS.md for the pilot day"*.

Probe:
```
$ ls ~/Projects/persona-engine/AGENTS.md
/Users/kostiantyn.vlasenko/Projects/persona-engine/AGENTS.md
$ wc -l ~/Projects/persona-engine/AGENTS.md
      90 /Users/kostiantyn.vlasenko/Projects/persona-engine/AGENTS.md
$ grep -n '@import' ~/Projects/persona-engine/AGENTS.md
10:@import ref/01-orchestrator.md
```
Its body (verified read, lines 12–90) is the persona-engine product contract: 5-agent table with
per-agent model/SLA/budget/max-actions, the six Guardrails (medical claims, crisis→helpline,
never-claim-human, rate limits 25 comments/3 posts/day, builder canary, no-git-push-from-agents),
Core Principles 1–7, and the Key Files index.

**Copying the pilot brief over that file deletes every publish-safety guardrail from the one file
Codex reads automatically, on the exact day a hookless orchestrator is driving the repo.** That is
the opposite of what the pilot is trying to measure. Recoverable via git, but the failure is
silent-while-live, not at-copy-time.

**Design decision D1 — install by import, not by overwrite.** The runbook's install step is:

```
cp plugins/leadv2/docs/codex-lead-AGENTS-pilot.md \
   ~/Projects/persona-engine/.claude/ref/90-codex-lead-pilot.md
# then append exactly one line to persona-engine/AGENTS.md:
@import .claude/ref/90-codex-lead-pilot.md
```
Rollback = delete that one line (`git checkout AGENTS.md`). The 90 existing lines survive; the
pilot brief is additive; the diff the founder must eyeball is one line, not 90.

Secondary probe finding, worth one runbook line: the existing import target is written
`ref/01-orchestrator.md` but the file lives at `.claude/ref/01-orchestrator.md` —
```
$ find . -maxdepth 4 -name '01-orchestrator.md'
./.claude/ref/01-orchestrator.md
```
i.e. the existing `@import` path does not resolve from repo root. The runbook must therefore state
the pilot import path **with the `.claude/` prefix**, and must not assume `@import` resolution has
ever been verified in this repo. Marked `UNVERIFIED:` in the runbook: whether Codex's `@import`
resolves relative to repo root or to the importing file — the pilot's first minute is a check that
the brief text is actually in context (ask the session to quote one line of it).

### 0.2 The burn digest cannot see the Codex lead — the headline metric is half-blind

The mission asks for "burn digest 24h delta" as a pilot measure. The telemetry source states its
own blind spot (`plugins/leadv2/scripts/leadv2-quota-status.sh:16-17`, verbatim):

> `codex is NOT in this db — it goes through the ChatGPT subscription and is unmeasured; said so
> explicitly (never imply zero).`

Same file:12-14 — `~/.claude/burn/history.db` splits by the `model` column: `claude%` → Claude Max,
`glm%` → Z.AI. Codex has no rows at all.

Consequence in plain words: the burn digest will show Claude-Max 24h burn **dropping** during the
pilot, and that drop is not a saving — it is the lead's cost moving to a meter this repo does not
read. A pre-registered success criterion phrased as "24h Claude burn down X%" would be passed by
doing nothing but moving the brain, which is the tautology, not the result.

**Design decision D2 — two-meter measurement.** The runbook's measurement table carries
`claude` burn and `codex` cost as separate columns from separate sources, and the success criteria
are phrased on *outcomes per unit of Claude burn*, never on Claude burn alone:
- Claude-Max + GLM: `~/.claude/state/leadv2/quota-cache/anthropic.json`, `glm.json` snapshot
  before/after, plus `plugins/leadv2/scripts/leadv2-quota-status.sh`.
- Codex: `~/.claude/state/leadv2/quota-cache/codex.json` before/after **and** the Codex TUI's own
  rate-limit readout pasted into the log — because nothing in this repo writes codex token counts.
Probe:
```
$ ls ~/.claude/state/leadv2/quota-cache/*.json
anthropic.json  codex.json  glm.json
```

### 0.3 The research the mission cites argues against this pilot — say so, don't bury it

`docs/research/reverse-bridges-deep-20260824.md` §5 (persona-engine, verified read):

> *"No candidate in this sweep argues for putting a non-Claude harness in the lead seat: every
> reverse path that works is narrower, less proven, or purely additive."*

`docs/research/harness-subscription-matrix-20260824.md` CORRECTION:

> *"You cannot make GPT the lead brain of a Claude Code session; you CAN dispatch work to it by
> subscription."* … *"only Claude Code takes all three."*

The founder's pilot is a *different* mechanism from the one the CORRECTION rules out: not "GPT as
Claude Code's model", but a Codex CLI process shelling out to the `claude` binary, which
authenticates under its own Max subscription in its own sanctioned client. That is subprocess
composition in the direction §2 of the reverse-bridges doc calls possible and legal. **The legality
premise holds.** What the research denies is *capability gain*, not legality. The runbook must open
with that framing so the pilot is judged on what it can actually win (hook-free orchestration cost,
GPT-5.6 planning quality) and not on a claim the research already answered.

---

## 1. CALLERS / CALLEES — every path the pilot's Codex lead touches

The "mechanism" this design ships is documentation, but the documentation is a *contract over
existing entry points*. Getting the contract wrong at any of these call sites is how a hookless
lead breaks the repo. Every line below is read from the tree.

### 1.1 Entry points the Codex lead calls (callees)

| Entry point | File:line evidence | Called by, in the pilot |
|---|---|---|
| `leadv2-dispatch-code.sh` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | Codex lead, one call per worker lane |
| `leadv2-review-run.sh --task --root --handoff --diff --author [--fanout]` | arg parser `leadv2-review-run.sh:70-87` (all five non-`--fanout` args **required**, `exit 2` otherwise) | Codex lead, after each lane's diff exists |
| `leadv2-quota-status.sh` | `plugins/leadv2/scripts/leadv2-quota-status.sh:1-25` | Codex lead, snapshot before/after |
| `codex` interactive TUI | `codex-cli 0.145.0-alpha.1`; `-m/--model`, `-c key=value`, `-p/--profile`, `-s/--sandbox {read-only,workspace-write,danger-full-access}` (`codex --help`) | founder, once, to open the pilot session |

### 1.2 Callers of the artifacts this task writes

Nothing in the tree reads either new file at runtime — both are prose. Their consumers are:
1. **The founder**, reading `codex-lead-pilot-runbook.md` by hand (the only caller of the launch
   and measurement steps).
2. **The Codex model**, reading `codex-lead-AGENTS-pilot.md` **only after** the founder performs
   the install step in D1. Until that step runs, the file has zero readers — it is inert on disk.
   The implementer must not write it in a voice that assumes auto-installation.
3. **The reviewer**, after the pilot, reading the runbook's gate-violation checklist against the
   Codex session transcript.

This is the "independent copy nobody named" check, and here it comes out clean: there is no second
copy of either file, and neither path is a symlink into `~/.claude/leadv2-shared/`. Probe: both
paths are new under `plugins/leadv2/docs/`, a directory whose current contents are 13 real files
(`OVERRIDES.md` … `work-placement.md`) plus `handoff/` and `leadv2/`.

### 1.3 The one caller relationship that actually matters: which hooks still fire

`plugins/leadv2/hooks/hooks.json` (670 lines) registers hooks on `SessionStart`,
`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`,
`PostCompact`, `CwdChanged`, `TaskCreated`. Every command is `${CLAUDE_PLUGIN_ROOT}/hooks/…` —
i.e. they are **Claude Code** hooks, loaded by the Claude Code harness.

Therefore, in the pilot:

- **Lead-side: zero hooks fire.** A Codex CLI session has no `CLAUDE_PLUGIN_ROOT`, no
  `PreToolUse`, no `Stop`. All 33 blocking guards are absent from the orchestrator.
- **Worker-side: hooks still fire, unchanged.** `leadv2-dispatch-code.sh` launches the `claude`
  binary for its GLM/Sonnet arms, and that child process loads the plugin normally. Worktree
  enforcement, `no-opus-code-edit`, `lead-edit-guard`, heredoc blocking etc. still bind **inside
  the worker**.

That asymmetry is the single most important sentence in both deliverables, and it narrows the
gate-violation checklist correctly: the checklist must cover only what the *lead* would have been
stopped from doing, because worker-side violations remain mechanically impossible.

The 33 blocking guards (grep `permissionDecision.*deny|exit 2` over `plugins/leadv2/hooks/*.sh`):
`bash-pre-dispatch, async-question-guard, block-fg-dispatch, block-fg-agent, bash-lint-pre-gate,
codex-direct-exec-guard, block-bash-heredoc, block-codex, close-ritual-guard, codex-round-cap,
codex-nopoll-guard, blocker-drift-guard, force-read-limit, cwd-changed, codex-first-nudge,
deny-floor, idle-notification-filter, lead-edit-guard, gate-artifact-guard, model-inherit-guard,
opus-read-budget, lead-read-guard, memory-guard, loop-detect-hook, monitor-cap-gate,
no-opus-code-edit, read-dedup-hard, thinking-audit-gate, taskoutput-ban, routing-guard,
workflow-bypass-guard, verdict-format-guard, worktree-enforce`.

Of these, the ones whose *subject is the lead* and which therefore become prose rules in the brief:
`block-bash-heredoc`, `lead-edit-guard` + `shared-script-warn` (shared-tree / canonical-plugin
edits), `worktree-enforce`, `no-opus-code-edit` (lead never writes application code),
`close-ritual-guard`, `memory-guard`, `taskoutput-ban`, `monitor-cap-gate`, `deny-floor`,
`block-fg-dispatch`. `block-codex` / `codex-direct-exec-guard` / `codex-first-nudge` are
**inapplicable by construction** — they exist to stop a Claude lead from shelling out to codex, and
in the pilot the lead *is* codex. Naming them as pilot rules would be a copy-paste error; the
runbook says explicitly that these three do not transfer.

---

## 2. STATES AND RETURN CODES

### 2.1 `leadv2-dispatch-code.sh` — verified exit sites

| rc | Meaning | Evidence (file:line) | What the Codex lead must do — and the user-visible consequence if it does not |
|---|---|---|---|
| 0 | Lane launched / resolve-only success | `:1529`, `:5510`, `:5620` | Record handle in ledger; wait. |
| 1 | Usage / internal failure (bad args, pending-append failed) | `:2718`, `:4618`, `:5073`, `:5108` | Fix the invocation. A lead that retries verbatim loops forever; **no lane starts and the task silently never runs.** |
| 2 | **Duplicate task signature** — another caller for this `sig8` is in flight | `:5431` (`dispatch_refused reason=duplicate_task_signature`), `:2713` | **Do NOT relaunch.** rc=2 means the work is already running. Retrying is the duplicate-editor incident: two workers writing one tree, and the founder sees a diff neither worker can explain. |
| 3 | Lock not acquired within 10s, or architect prepass parked after N attempts | `:2713` (`lv2_lock_wait … \|\| exit 3`), `:4947` | rc=3-from-prepass asks the founder retry/abort via `ask-lead.sh` and is **terminal for this call**; the lane does not start until answered. Lead must surface it, not swallow it. |
| 4 | **All arms refused** — `all_arms_not_dispatchable_v2` / `all_arms_quota_locked` / `all_arms_exhausted` / `all_arms_excluded` | `:5219`, `:5291`, `:5322`, `:5367`, `:5209` | Terminal. No provider is available. **Nothing is built for that task today**; re-dispatch only after the quota window resets or the arm chain is changed. A lead that treats rc=4 as transient burns the whole pilot day polling. |
| 5 | Lane placement refused — `no_lane_worktree_for_ref` | `:741` | The named worktree does not exist under `${LEADV2_WORKTREE_DIR:-<root>/.claude/worktrees}`. Create it or drop the ref; retrying unchanged is guaranteed to fail identically. |
| 6 | **Burn gate hard cap** — task parked, `_burn_park_deferred` written | `:1453` | Terminal and *deliberate*. The task is parked to `docs/leadv2/burn-deferred.*`, not lost. **This is the correct end of the pilot day**: hitting rc=6 means stop dispatching, not tune the cap. Consequence if the lead "fixes" it by raising the cap: the pilot's cost number becomes meaningless. |

The pilot's rc=6 handling is mission-named ("6=burn-park") and is the one exit code the brief must
teach as a *success* signal rather than a failure.

### 2.2 `leadv2-review-run.sh` — verified exit sites

| rc | Meaning | Evidence | Lead action + user-visible consequence |
|---|---|---|---|
| 0 | Review passed | `:1527` | Proceed to merge/close. |
| 2 | Bad/missing args (`--task --root --handoff --diff --author` all required) | `:78`, `:84` | Fix invocation. Until fixed, **the lane has no review verdict and must not merge.** |
| 6 | Blocked — `review_body_lost` (arm returned a body that vanished) or `empty_response` | `:1272`, `:1346` | The reviewer produced nothing. Not a pass. Re-run once with a different arm; second rc=6 → park. |
| 7 | **Review FAIL** — findings above threshold, or `selfcheck_red_round0` | `:1094`, `:1514` (`status=fail critical=… high=…`, optional `do_not_merge=1`) | One bounded fix round against named findings, then re-review. `do_not_merge=1` is absolute. |
| 8 | **Round cap / spawn cap reached** — `review_roundcap` / `review_spawncap` | `:1064`, `:1180` | Terminal for automation. The engine is refusing a further round. Escalate to architect or PARK; writes `${HANDOFF}/review-roundcap-escalation.md`. A lead that loops here spends the day re-reviewing one diff and lands nothing. |
| 9 | Unreviewed — `all_arms_unavailable` (no reviewer arm could be reached) | `:1118`, `:1253` | **Not a pass.** `review-gate.md` says `status: unreviewed`. Merging on rc=9 is the artifact-proxy failure L5 in single-lead-mode.md §5. |

**The pilot's single most dangerous confusion is rc=9 vs rc=0.** Both leave a `review-gate.md` on
disk. Only rc=0 is a pass. The brief states this as: *"a review-gate.md file existing is not a
verdict — read its `status:` line."*

### 2.3 Session-level states for the pilot itself

| State | Entered when | Exit |
|---|---|---|
| PREP | this task's two files land | founder performs D1 install |
| ARMED | `@import` line appended, snapshots taken | founder opens codex TUI |
| RUNNING | codex session live, WIP=1 | one working block ends, or rc=6 burn park |
| MEASURED | after-snapshots taken, checklist filled | reviewer reads transcript |
| ROLLED BACK | any point | delete the one `@import` line; close the codex session |

Rollback is total and costs one line, by construction of D1. Nothing persistent is written by the
pilot itself except normal lane artifacts (journals, handoff dirs, commits) that any lead produces.

---

## 3. CONFIGURATION BOUNDARIES

Every input the two documents describe or depend on, at absent / empty / minimum / over-cap /
malformed.

| Input | Absent | Empty | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|
| `persona-engine/AGENTS.md` | Codex starts with no repo rules; pilot brief silently not in context → **the whole gate-prose layer is missing and the lead does not know it**. Runbook mitigation: minute-1 quote-back check. | Same as absent. | one `@import` line | n/a | dangling `@import` (the existing `ref/01-orchestrator.md` case, §0.1) → import silently contributes nothing; same blindness as absent. |
| pilot brief file (`.claude/ref/90-codex-lead-pilot.md`) | import resolves to nothing | no rules in context | — | **≤150 lines is a mission constraint, not a system limit.** Over-cap here costs context, not correctness. | — |
| `codex` model | falls back to `~/.codex/config.toml` `model = "gpt-5.6-sol"` (probed) | — | — | — | `-m` with an unknown id → codex errors at launch, before any repo write. Safe failure. |
| `model_reasoning_effort` | config default `xhigh` (probed) | — | `low` | `xhigh` | unknown value → codex config error at launch. Safe. |
| `codex -s/--sandbox` | **the founder's shell aliases `codex` to `--dangerously-bypass-approvals-and-sandbox`** (probed: `codex: aliased to codex --dangerously-bypass-approvals-and-sandbox`) — so the default in practice is *no sandbox and no approvals*, on a lead with no hooks | — | `read-only` | `danger-full-access` | invalid → launch error |
| `~/.claude/state/leadv2/quota-cache/*.json` | snapshot step yields nothing; delta unmeasurable → pilot produces no cost number | `{}` → same | — | — | truncated JSON → the *measurement* is wrong, but nothing dispatches on it; blast radius is the report only |
| `~/.claude/burn/history.db` | burn digest reports `reason=no_telemetry`, `burn24h=0` (`leadv2-burn-governor.sh:140,168,177`) — **and `burn24h=0` means the burn gate at rc=6 never fires**, so the day's cost ceiling silently disappears | same | — | ≥ hard cap → rc=6 park (correct) | non-numeric `burn24h` → treated as no_telemetry, gate off (`:167-168`) |
| `LEADV2_WORKTREE_DIR` | defaults to `<root>/.claude/worktrees` (`:742`) | ref not found → rc=5 | — | — | path that exists but is not a worktree → rc=5 at placement |
| `--fanout` on review-run | optional; omitted is normal | — | — | — | unknown arg → rc=2, no review runs |

**Two over-cap/absent cases exceed the blast radius of their own operation and are called out as
runbook warnings, per the mechanism-closure rule:**

1. **`history.db` absent/malformed disables the burn gate entirely.** `burn24h=0` classifies as
   `verdict=ok reason=no_telemetry`, so `leadv2-dispatch-code.sh:1453` never reaches `exit 6`. A
   hookless lead with a broken telemetry db has *no cost ceiling at all* — the failure is
   fail-open, and it takes down the day's spend control, not one dispatch. The runbook's
   pre-flight therefore requires proving the burn digest returns a **non-zero** `burn24h` before
   the session starts, not merely that it runs.
2. **The `codex` alias defeats sandbox selection.** The founder's alias hard-codes
   `--dangerously-bypass-approvals-and-sandbox`, which the runbook's own `-s` recommendation
   cannot override by appending flags. The launch line must be written as an explicit
   `command codex …` (bypassing the alias) if a sandbox is wanted, and the runbook must say which
   it is choosing and why. This is a lead-wide property, not a per-command one.

---

## 4. COUNTEREXAMPLE

*After every finding in this mission is fixed, what can still violate the invariant these two
documents exist to protect?*

The invariant is: **a hookless orchestrator does not do, on the pilot day, anything the blocking
hooks would have stopped — and if it does, the transcript shows it.** Prose cannot enforce; it can
only inform and leave evidence. So the honest answer is that several things still can, and the
runbook is stronger for naming them than for pretending otherwise. The residual holes, in
descending severity: (a) **the checklist is audited after the fact, so any violation that is not
textually visible in the transcript is undetectable** — a `git checkout` or a file overwrite
performed inside a shell one-liner whose output the model summarised rather than pasted leaves no
trace, and `--dangerously-bypass-approvals-and-sandbox` means nothing else was watching either;
(b) **rc=9 and rc=0 both leave a `review-gate.md` on disk**, so a lead that files "review done"
against the file's existence rather than its `status:` line produces a merged, unreviewed diff that
looks identical in the ledger to a reviewed one — the brief warns, but the artifact shape makes the
mistake attractive; (c) **the two-meter cost design is only as good as the Codex-side number**, and
that number is transcribed by hand from a TUI, so a founder who forgets the after-reading leaves
the pilot with a Claude-burn drop and no Codex counterweight — which reads as a win and is not one;
(d) **`@import` resolution is unverified in this repo** (§0.1 probe shows the existing import path
does not resolve from root), so the brief may simply not be in context while everyone believes it
is — the minute-1 quote-back check is a mitigation, not a guarantee, because a model can quote a
line it inferred from the runbook the founder pasted; (e) **WIP=1 is unenforced without hooks**, so
nothing but the lead's own discipline stops two concurrent lanes in one tree, and single-lead-mode
§5 L2 records that this is exactly what `unscopable_diff` was. What I checked and found *not* to be
a hole: worker-side enforcement genuinely survives (the `claude` child loads `hooks.json`
normally), the burn park at rc=6 genuinely fires from inside `dispatch-code.sh` and needs no
lead cooperation *provided* telemetry is non-zero, and rollback genuinely is one line under D1.

---

## 5. What to write — file by file

### 5.1 `plugins/leadv2/docs/codex-lead-pilot-runbook.md` (new)

Sections, in order:

1. **Premise & what the research already settled** — §0.3 above, three sentences. Legality holds;
   capability gain is the open question; judge the pilot on cost-per-outcome, not on Claude burn.
2. **Launch** — exact invocation. Must include: `cwd ~/Projects/persona-engine`; model
   `gpt-5.6-sol` and `model_reasoning_effort` (state that both are already the probed config
   defaults, so `-m`/`-c` are belt-and-braces); the alias warning from §3 with the
   `command codex …` form; the D1 install step verbatim; the minute-1 quote-back check.
   Session lifetime: **one working block, 2–4 tasks, no marathon**, mirroring
   single-lead-mode.md §1 (session reset > compaction).
3. **Task menu — pick criteria, not ids.** Per mission. Criteria, each traceable to
   single-lead-mode.md §2/§3: Standard class; single subsystem, ≤2 write paths; acceptance
   provable from a file artifact or a live probe the founder can climb personally; reversible
   (no publish path, no payments, no migration); premise re-provable at dispatch time; not
   already parked in `docs/leadv2/burn-deferred.*`. Source: `~/Projects/persona-engine/docs/tasks.yaml`
   (probed to exist). Explicitly exclude: anything on the Codex-FULL not-for list
   (single-lead-mode.md:39-41).
4. **The dispatch door** — rc table from §2.1, verbatim, with the rc=2/rc=4/rc=6 consequences in
   plain words.
5. **The review door** — rc table from §2.2, with the rc=9-is-not-a-pass rule in bold.
6. **Measurement protocol** — the two-meter table from §0.2; before/after snapshot commands for
   the three `quota-cache/*.json` files; `leadv2-quota-status.sh` run; burn digest 24h delta **with
   the codex-is-unmeasured caveat quoted from `leadv2-quota-status.sh:16-17`**; lanes
   landed / stalled / parked counted from the ledger not from handoff dirs (L3); founder
   intervention count (one tally mark per time the founder had to correct or unblock the lead).
   Pre-flight assertion: burn digest `burn24h` is **non-zero** (§3 warning 1).
7. **Gate-violation checklist** — one row per lead-side guard from §1.3, each phrased as an
   observable in the transcript. Explicitly note the three inapplicable guards
   (`block-codex`, `codex-direct-exec-guard`, `codex-first-nudge`) and why.
8. **Pre-registered success / fail criteria** — numbers. Suggested and to be confirmed by the
   founder before launch (a criterion invented after the data is not a criterion):
   - PASS: ≥2 lanes reach an accepted, reviewed diff (rc=0 from review-run, `status: pass`);
     founder interventions ≤3; zero checklist violations in tier "would have been blocked";
     Claude-Max 24h burn not higher than a comparable Claude-lead day **and** Codex-side
     consumption recorded (not blank).
   - FAIL: any lane merged on rc=9/rc=6/`do_not_merge=1`; ≥1 shared-tree or canonical-plugin edit;
     >5 founder interventions; 0 lanes landed.
   - INCONCLUSIVE (a real outcome, must be pre-registered): burn telemetry absent, or Codex-side
     number not captured.
9. **Rollback** — delete the one `@import` line; close the session. Nothing persistent changes.
   Any commits the lanes produced are ordinary commits and are kept or reverted on their own merit.

### 5.2 `plugins/leadv2/docs/codex-lead-AGENTS-pilot.md` (new, ≤150 lines)

Written in the voice of rules addressed to the Codex lead. Content, in order:

1. Header: what this file is, that it is pilot-scoped, and **that it is additive to
   persona-engine's existing AGENTS.md — it does not replace the product guardrails above it**.
2. Single-lead WIP rules — WIP=1 across all channels including review/fix rounds; 2–4 named tasks;
   one ACTIVE; new asks go to `docs/leadv2/open-threads.md`, never into the session
   (single-lead-mode.md §1).
3. The dispatch door — `leadv2-dispatch-code.sh` usage and the rc table, compressed to
   rc/meaning/action; rc=6 taught as burn-park-is-correct.
4. The mandatory review gate — `leadv2-review-run.sh` with its five required flags; rc=0 only is a
   pass; rc=9 is `unreviewed`; `do_not_merge=1` is absolute; roundcap rc=8 → escalate or park,
   never loop.
5. Top-10 hard rules as prose (from §1.3): no `git reset`/`git clean`/`rm -rf` in shared trees; no
   edits to `~/.claude/leadv2-shared/` or canonical `plugins/leadv2/**` scripts; never write a real
   copy of a plugin-owned file into a project; no heredocs in Bash; worktree scope — write only
   under the lane's worktree root; lead never writes application code (delegate); ledger discipline
   — one row per task at every transition; journal appends, never rewrites; verify by evidence
   (diff + test output + review verdict + live probe), never by file-exists; founder chat in
   Russian, documents in English.
6. Where state lives — `docs/leadv2/active.yaml` (lead-owned), `docs/handoff/<task-id>/`,
   `docs/leadv2/founder-status.md`, `docs/leadv2/open-threads.md`,
   `docs/leadv2/scheduled-decisions.md`, `docs/leadv2/burn-deferred.*`.
7. Closing line: the three guards that do not transfer, so the lead does not shadow-box them.

**Deliberately left out of the ≤150-line brief** (the critic-facing statement the mission asks
for): the full 33-guard list (only the 10 lead-side ones are prose); the supervisor/fanout mode
entirely (paused, single-lead-mode.md §6); the Codex-FULL-cycle channel and the
`leadv2-codex-session-runner.sh` path (recursive in this pilot — the lead *is* Codex); the Kimi
arm and the ladder-spill semantics; the retry policy's six numbered clauses compressed to one
sentence ("every retry must change premise, scope, or channel"); MCP/repowise tooling; the plan
workflow's model pinning; and all measurement instructions (they live in the runbook, which the
founder reads, not in the brief, which the model reads).

---

## 6. Non-goals — do not do these

- Do **not** write, move, or append `persona-engine/AGENTS.md`. The install is a founder step,
  documented, not executed.
- Do **not** touch `plugins/leadv2/scripts/**`, `plugins/leadv2/hooks/**`, or `hooks.json`.
- Do **not** run the pilot, open a codex session, or dispatch a lane.
- Do **not** add a hook, cron, or wrapper to "help" the Codex lead — the pilot's whole point is
  measuring the hookless case.
- Do **not** create `<role>.md` symlinks, edit `docs/leadv2/active.yaml`, or touch shared trees.
- Do **not** pick specific task ids for the menu — criteria only, per mission.
- Do **not** propose replacing the tmux/dispatch layer with `awslabs/cli-agent-orchestrator`; the
  research marks that a separate scoped evaluation, not this pilot.

---

## 7. Risks and mitigations

| # | Risk | Severity | Mitigation (in the deliverable) |
|---|---|---|---|
| R1 | AGENTS.md overwrite deletes publish guardrails mid-pilot | Critical | D1 append-import install; one-line rollback (§0.1) |
| R2 | Brief silently not in context (`@import` unresolved) | High | minute-1 quote-back check; import path written with `.claude/` prefix; tagged `UNVERIFIED:` |
| R3 | Claude-burn drop misread as a saving | High | two-meter measurement; success criteria phrased per-outcome; codex-unmeasured caveat quoted (§0.2) |
| R4 | Burn gate silently off (`no_telemetry` → `burn24h=0`) | High | pre-flight requires **non-zero** burn24h before launch (§3) |
| R5 | Merge on rc=9 (`unreviewed`) or rc=6 | High | rc tables in both files; "read the `status:` line, not the file's existence" |
| R6 | rc=2 relaunch → two workers, one tree | High | rc=2 taught as "already running, never retry" |
| R7 | rc=4 treated as transient → day spent polling | Medium | rc=4 marked terminal with its plain-words consequence |
| R8 | Sandbox flag defeated by the shell alias | Medium | `command codex …` form + explicit statement of the chosen sandbox mode |
| R9 | Brief copy-pastes inapplicable codex-blocking guards | Medium | three guards named as non-transferring in both files |
| R10 | Pilot judged against a claim the research already settled | Low | §0.3 framing paragraph opens the runbook |

## 8. Constraint checklist

1. **Env var naming** — no new env vars introduced. All referenced names are existing and
   `LEADV2_*`-prefixed (`LEADV2_WORKTREE_DIR`, `LEADV2_DISPATCH_*`). No `LEAD_V2_*` drift.
2. **File paths** — verified on disk: `plugins/leadv2/hooks/hooks.json`,
   `plugins/leadv2/scripts/leadv2-{dispatch-code,review-run,quota-status,burn-governor}.sh`,
   `docs/leadv2/{active.yaml,founder-status.md}`, `~/Projects/persona-engine/docs/tasks.yaml`,
   `~/Projects/persona-engine/AGENTS.md`, `~/.claude/state/leadv2/quota-cache/{anthropic,codex,glm}.json`,
   `~/Projects/persona-engine/.claude/ref/01-orchestrator.md`.
   `(to-create)`: `plugins/leadv2/docs/codex-lead-pilot-runbook.md`,
   `plugins/leadv2/docs/codex-lead-AGENTS-pilot.md`. Founder-step-only `(to-create)`:
   `~/Projects/persona-engine/.claude/ref/90-codex-lead-pilot.md`.
3. **`claude -p` commands** — none authored by this task. The runbook does not hand-write a
   `claude -p`; worker launches go through `leadv2-dispatch-code.sh`, which owns its own flags.
4. **Concurrent access** — the two new files are written by one lane and read by humans; no
   race. The pilot's real race surface is *one tree, two lanes*, unenforced without hooks — covered
   by the WIP=1 rule and named as residual hole (e) in §4.
5. **Config contradiction** — no env var introduced or modified.

---

acceptance:
  surface: file_artifact
  observable: >
    Both `plugins/leadv2/docs/codex-lead-pilot-runbook.md` and
    `plugins/leadv2/docs/codex-lead-AGENTS-pilot.md` exist and, read by a person who has never
    seen this task, answer without further lookup: (a) the exact command that opens the pilot
    session and the exact install step for the brief, stated as an append of one `@import` line
    rather than an overwrite of persona-engine's existing 90-line AGENTS.md; (b) what each
    dispatch exit code 0–6 and each review exit code 0,2,6,7,8,9 means and what the lead does
    next, with rc=6 named as a correct stop and rc=9 named as not-a-pass; (c) two separate cost
    columns, one Claude/GLM and one Codex, with a written statement that the burn database
    contains no Codex rows; (d) pre-registered pass, fail, and inconclusive thresholds as
    numbers; (e) a one-line rollback. The brief is 150 lines or fewer and states in its own
    header that it is additive to the repo's existing AGENTS.md.
  authored_at: 2026-08-24T08:52:53Z

LANE_WRITES: plugins/leadv2/docs/codex-lead-pilot-runbook.md, plugins/leadv2/docs/codex-lead-AGENTS-pilot.md

DELIVERABLE_COMPLETE
