Product implementation task dispatch-3b96b97c. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# CODEX-DOOR-DEAD-01 — architect prepass (scoped implementation design)

Design only. No code written here. The implementing lane must **reproduce at runtime before
changing a line** — everything below Part 2 is a ranked candidate set with the exact probe that
discriminates it, not a diagnosis.

---

## Part 0 — What the prepass established (read, not run)

All line numbers are `plugins/leadv2/scripts/` in the leadv2 plugin repo (canonical; the
persona-engine copies are per-file symlinks to these inodes).

### The two doors

| Door | Call site | Invocation |
|---|---|---|
| Dispatch | `leadv2-dispatch-code.sh:2394` (`_spawn_worker_body`, `codex)` arm) | `codex-task.sh task "$mission" --background --cwd "$WORK_ROOT" --tier <tier>` |
| Review | `leadv2-review-run.sh:256` (`run_reviewer_arm`, `codex` branch) | `codex-task.sh adversarial-review --base HEAD --wait --focus "…"` → stdout captured to `$HANDOFF/review-codex.md` |

### The provider chain below both doors

`codex-task.sh` strips `--tier/--reason/--wait` and re-emits `--model/--effort`
(`codex-task.sh:1144-1200`), then execs `codex-companion.mjs`
(`~/.claude/plugins/cache/openai-codex/codex/1.0.4/scripts/codex-companion.mjs`).

Facts confirmed by reading the companion:

- `handleTask` (`:732`) parses `valueOptions: ["model","effort","cwd","prompt-file"]`,
  `booleanOptions: [… "write" …]`. **`--write` is presentational metadata only** — it reaches
  `renderTaskResult` and the job record, nothing else (`:505`, `:525`, `:589`). `task` jobs are
  `sandbox: "workspace-write"` unconditionally (`:488`). So the mission's healthy direct probe and
  the dispatcher's spawn differ in `--write` in *name only*; **`--write` is not the fault.**
- `resolveCommandWorkspace` → `resolveWorkspaceRoot` → `ensureGitRepository` =
  `git rev-parse --show-toplevel` (`lib/git.mjs:77`). In a **linked worktree that returns the
  worktree path**, not the main checkout. So a lane worktree is its own `workspaceRoot`, and the
  job registry / job files are written there (`enqueueBackgroundTask:667`
  `writeJobFile(job.workspaceRoot, …)`).
- `executeTaskRun` runs the turn rooted at **`workspaceRoot`**, not `cwd` (`:486-490`).
- `handleReviewCommand`/review execution uses `sandbox: "read-only"` plus
  `outputSchema: REVIEW_SCHEMA` and `parseStructuredOutput` (`:407-415`) — the review body is a
  **structured-output parse of the model's final message**, and the review prompt is built from
  `collectReviewContext(cwd, target)` (i.e. **the git diff the `--base` selects**), with `--focus`
  appended as an instruction only.
- `readTaskPrompt` = `positionals.join(" ")` or piped stdin (`:613`).

### Fault B is already all but pinned by reading (still must be reproduced)

`review-run.sh` gives every non-codex arm the diff **as a file** (`Review ONLY the diff at
${DIFF_FILE}`, mission text the reviewer can read). The codex arm gets that same sentence in
`--focus`, but the companion does **not** read `DIFF_FILE` — it builds the review prompt from
`--base HEAD`, i.e. *working-tree-vs-HEAD*. In the dispatch flow the lane's work is normally
**already committed** when review runs, so `--base HEAD` selects an **empty diff**. Codex then
correctly returns "nothing to review" → short/empty stdout → rc 0.

The `REVIEW-BODY-PERSIST-01` guard (`review-run.sh:558-573`) then fires:
`rc==0 && no REVIEW_VERDICT: line && bytes < 300 && stderr non-empty` → `review_body_lost`.
Note the last clause is **always true for codex**: `codex-task.sh` unconditionally writes
`[codex-task] tier=… -> model=…` to **stderr** (`:1180`, `:1197`). So codex is the one arm whose
"paid but empty" branch can never be skipped — which is why only codex produced
`reason=review_body_lost`, twice, on a diff opus reviewed fine.

Second, independent defect on the same line: the codex review arm passes **no `--cwd`**, while the
glm/kimi/sonnet arms all pass `--cwd "${ROOT}"`. The review target is therefore whatever
`process.cwd()` happens to be — wrong repo whenever `review-run.sh` is invoked from outside `ROOT`.

### Fault A (dispatch door) — the discriminating difference

The healthy probe was `codex-task.sh task --background --write --effort medium "reply with
exactly: OK"`. The dispatcher's spawn differs on **four** axes, ranked by how much they can explain
"zero bytes, job accepted, lane polls `waiting_worker` for 20 min":

| # | Difference | Mechanism it would produce | Discriminating probe |
|---|---|---|---|
| A1 | `--tier standard` → `--model gpt-5.6-terra --effort medium` (`codex-task.sh:1159`); the probe passed **no** `--tier` → default model | If `gpt-5.6-terra` is not on this plan/models cache, `runAppServerTurn` fails the turn immediately → job goes `failed` with an error message and **zero touched files**; the lane sees no diff. Explains *both* doors at once (`--tier` is injected on the review path too, `:1184`) | Re-run the *same* healthy prompt **with `--tier standard`**, then `codex-task.sh status <jobId>` + read the job log |
| A2 | `--cwd "$WORK_ROOT"` = a **linked git worktree**; the probe ran in a normal checkout | Registry/job files land under the worktree (`writeJobFile(job.workspaceRoot,…)`), but `dispatch-code.sh:2423` polls `codex-task.sh status "$handle"` **with no `--cwd`**, from the dispatcher's own cwd. Any cross-workspace-status fallback in `codex-task.sh` is the only thing preventing a false `not_live`. If the *worker* mis-resolves, work lands in the wrong tree — "zero bytes **in the lane worktree**" while codex did real work | Spawn with `--cwd <lane worktree>`, then `find` the job file and `git -C <main repo> status` for stray edits |
| A3 | Mission is a multi-KB markdown blob as **one argv positional** | `parseCommandInput` treats any token starting with `--` as an option; a mission line beginning with `--`, or containing `--model`/`--effort`, silently mutates the invocation (`codex-task.sh:_has_flag` scans *all* of `$@`, mission text included) and can truncate the prompt at `positionals.join(" ")` | Spawn with a mission containing a line starting with `--`; compare the persisted `request.prompt` in the job file against the mission file |
| A4 | No `< /dev/null` on the codex arm (this repo's known requirement; `readTaskPrompt` falls through to `readStdinIfPiped()`) | A detached worker inheriting a live stdin can block on a stdin read | Spawn from a context with an open pipe on stdin vs `< /dev/null` |

`--write` is **excluded** as a cause (proved above). Do not spend the lane on it; add it anyway as
a one-token correctness/labelling fix only.

---

## Part 1 — Non-goals (implementing agent: ignore all of these)

1. **No re-architecture of the arm/router ladder.** No change to `routing.yaml`, arm ordering,
   spill-walk, or `codex_quota_gate` semantics beyond the one new stand-down reason.
2. **No change to `codex-companion.mjs`** or anything under `~/.claude/plugins/cache/` — it is a
   vendored plugin cache, overwritten by `claude plugin update`. Every fix lands on **our** side of
   the boundary (`codex-task.sh`, `leadv2-dispatch-code.sh`, `leadv2-review-run.sh`).
3. **No relaxation of `REVIEW-BODY-PERSIST-01`.** The guard is correct; it is reporting a real
   empty review. Fixing it by raising `LEADV2_REVIEW_BODY_MIN_BYTES` or dropping the stderr clause
   is a regression, not a fix.
4. **No `reset --hard` / `clean` / `stash`** anywhere in this tree. Re-`git diff` immediately
   before `git add`.
5. **Do not touch `docs/leadv2/open-threads.md`.**
6. **Do not lift the current 6h codex lockout by hand** as part of the fix; the stand-down verb
   (Part 3) is what expresses lifting/extending it.
7. No new provider, no new arm, no retry/backoff redesign.

---

## Part 2 — Change 1: reproduce, then fix the dispatch door

**Files:** `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
`plugins/leadv2/scripts/codex-task.sh` (only if A1/A3 lands there),
`plugins/leadv2/scripts/tests/test-codex-door.sh` *(to-create)*.

**Sequencing — mandatory:**

1. **Repro first.** Run the A1→A4 probes above, in that order, from the persona-engine tree, and
   paste the raw evidence (jobId, job-file JSON, job log tail, `git status` of both trees) into
   the report. Stop at the first probe that reproduces "job accepted, zero bytes".
2. Only then implement. The fix shape depends on which probe fired:
   - **A1 confirmed** → make tier→model resolution *verified*, not assumed:
     `codex-task.sh` must fail loudly (non-zero, `[codex-task] REFUSED: model <slug> unavailable`)
     when the resolved slug is absent from `models_cache.json`, and fall back to the plan's default
     model rather than shipping a slug the app-server rejects. Mirror the existing `top`-tier
     fallback logic (`:1148-1157`) onto `standard`/`volume`.
   - **A2 confirmed** → pass `--cwd` on **every** codex-task.sh call the dispatcher makes,
     including the liveness `status` at `dispatch-code.sh:2423` and `_arm_final_output` /
     `_arm_log_tail` (`:2480`, `:2542`), so the registry read and the registry write always resolve
     to the same `workspaceRoot`.
   - **A3 confirmed** → stop passing the mission as argv. Write it to a temp file and use
     `--prompt-file` (the companion supports it, `:614`), exactly as the sonnet arm already writes
     `--mission-file`. This also removes the `_has_flag` mission-text contamination.
   - **A4 confirmed** → add `< /dev/null` to the codex spawn, matching the repo rule.
3. **Independently of which fired**, add the missing *observability* that made this cost 20 minutes
   a lane instead of 60 seconds: the codex arm currently discards the job's early verdict until the
   close gate polls. Extend the existing `_wait_arm_early_verdict` seam (`:2461`) so a codex job
   that reaches `failed`/`completed` **with zero touched files** emits a distinct journal line —
   `arm_postspawn_verdict arm=codex state=<s> produced=none` — and the lane fails fast rather than
   sitting in `waiting_worker`.
4. Add `--write` to the codex spawn for label correctness (one token; **not** a fix — say so in the
   report so it is never mistaken for the mechanism).

**Race surface (constraint-check item 4):** the codex job registry under a lane worktree is written
by the detached worker and read by the dispatcher's poll loop concurrently. Both must resolve the
same `workspaceRoot` — that is the whole content of A2's fix. No new lock is needed if `--cwd` is
threaded consistently; do **not** invent one.

---

## Part 3 — Change 2: fix the codex review arm

**File:** `plugins/leadv2/scripts/leadv2-review-run.sh` (the `arm == codex` branch, `:255-261`).

1. **Give codex the same diff every other arm gets.** `--base HEAD` is wrong whenever the lane's
   work is committed. Resolve an explicit base for the review target (the lane's merge-base /
   pre-lane ref that `review-run.sh` already knows as the producer of `DIFF_FILE`) and pass that,
   so `collectReviewContext` sees a non-empty diff. If no such ref is reachable, the arm must
   **refuse before spending** (`review_rc=77`, the existing arm-unavailable code) rather than
   produce an empty review that then trips the body guard.
2. **Pass `--cwd "${ROOT}"`**, matching the glm/kimi/sonnet arms.
3. **Pre-flight the emptiness**: if the resolved diff is empty, do not call codex at all — emit
   `review_arm_skipped arm=codex reason=empty_diff` and fall through the arm ladder. A paid empty
   review is strictly worse than a skipped one.
4. Leave the `REVIEW-BODY-PERSIST-01` guard untouched (non-goal 3). After the fix it should stop
   firing because the body is real, not because the guard was weakened.

---

## Part 4 — Change 3: stand a provider down for a duration

**File:** `plugins/leadv2/scripts/leadv2-dispatch-code.sh`.

Why today's call did nothing: `cmd_record_quota_lockout` (`:3909-3939`) (a) **requires
`--arm` + `--handle`** and exits 0 without them, (b) has **no `--hours` flag** — unknown flags hit
the `*) shift ;;` arm and are silently swallowed, and (c) gates every write on
`_quota_shaped "$final_out"`, so a healthy-but-broken provider records
`arm_postspawn_verdict … quota=no` and writes nothing. It can only ever express "out of quota".

**New verb** — `leadv2-dispatch-code.sh stand-down`:

| Flag | Required | Meaning |
|---|---|---|
| `--provider <codex\|glm\|anthropic>` | yes | provider to stand down |
| `--hours <n>` \| `--until <iso>` | one of | duration; mutually exclusive |
| `--reason "<text>"` | yes | why — recorded, and shown by `leadv2-codex-lockout.sh` |
| `--clear` | — | lift an active stand-down early |

Contract:
- Writes through the **existing** `_record_quota_lockout <provider> <iso> <reason>` writer, with
  `reason=stand_down:<text>` — a **distinct reason vocabulary from `postspawn_quota`**, so the
  router and any later learning pass can tell "broken" from "out of quota".
- **Overwrites an expired lockout file** (the observed bug: the expired file was left untouched).
  Writing must be unconditional on the prior file's state; only `--clear` shortens.
- Emits `provider_stand_down_recorded provider=<p> until=<iso> reason=<text>`.
- Unknown flags become a **hard error**, not a silent `shift` — retro-fit that to
  `cmd_record_quota_lockout` too, since its silent-swallow is what made the original call look
  like it had worked.
- Idempotent and rc0-on-repeat (matches the existing best-effort convention for the close gate).

`leadv2-codex-lockout.sh` needs no interface change — it already reports `locked <until-iso>`; only
verify it renders a stand-down reason distinctly.

---

## Part 5 — Constraint checklist

1. **Env vars:** the lane introduces none. Existing reads (`LEADV2_DISPATCH_CODEX_BIN`,
   `LEADV2_REVIEW_BODY_MIN_BYTES`, `LEADV2_ROUTER_V2_CODEX_TIER`, `CODEX_MODELS_CACHE`) all already
   carry the `LEADV2_`/`CODEX_` convention. No `LEAD_V2_*` drift. ✅
2. **Paths:** all four script paths verified present on disk; `tests/test-codex-door.sh` marked
   `(to-create)`. ✅
3. **`claude -p`:** this lane spawns no `claude -p`. N/A. ✅
4. **Concurrent access:** covered in Part 2 (job registry read/write must share `workspaceRoot`).
   The lane also writes `docs/handoff/CODEX-DOOR-DEAD-01/report.md`, which no other lane touches. ✅
5. **Config contradiction:** the new `stand_down:` reason must not collide with any existing
   lockout-reason match; grep `_quota_shaped`, `postspawn_quota`, and every reader of the lockout
   file before adding it. Flag as **CRITICAL** if a reader pattern-matches reasons loosely. ⚠️
   *(decision: `source: architect(self-check)`)*

---

## Part 6 — Risks

| Risk | Mitigation |
|---|---|
| Fixing the *symptom* on a hypothesis (esp. adding `--write`, which is proven inert) and declaring victory | Part 2 step 1 is a hard gate: no edit until a probe reproduces |
| Two faults collapsed into one; fixing A leaves the review arm dead (or vice-versa) | Separate acceptance surfaces below — one for the dispatch door, one for the review arm |
| The tier→model fallback change silently downgrades every codex lane to a cheaper model | Fallback must be **loud** (stderr line + journal `decision`), never silent |
| Editing canonical `.sh` under `LEADV2_LEAD_GUARD=1` is blocked for the Edit tool | Known: fix-forward via a `/tmp` python patcher + Bash (see `lead-edit-guard-canonical-edit` memory) |
| A concurrent session reverts the edit between edit and stage | Re-`git diff <file>` immediately before `git add`, per hard constraint |
| Stand-down verb used to mask a real quota death, hiding a genuine lockout | Distinct reason string + the journal line make the two distinguishable in the ledger |

---

acceptance:
  - surface: log_line
    observable: "In the persona-engine dispatch journal for a lane routed to codex, the lane reaches a terminal `done` line with a non-empty diff — instead of repeating `waiting_worker` for 20+ minutes and ending `blocked / worker_timeout`."
    authored_at: 2026-08-16T07:06:07Z
  - surface: file_artifact
    observable: "After a codex-routed dispatch, the lane's worktree contains changed files (the worker's edits are visibly there), where previously the worktree was byte-for-byte unchanged."
    authored_at: 2026-08-16T07:06:07Z
  - surface: rendered_line
    observable: "`docs/handoff/<task>/review-gate.md` for a codex-armed review shows a real verdict line with findings, not `status: blocked` / `reason: review_body_lost` / `arm: codex`."
    authored_at: 2026-08-16T07:06:07Z
  - surface: rendered_line
    observable: "After standing codex down for a duration, `leadv2-codex-lockout.sh` prints `locked <a future timestamp>` with a stand-down reason, and the next dispatch's journal shows codex skipped rather than picked again minutes later."
    authored_at: 2026-08-16T07:06:07Z
  - surface: file_artifact
    observable: "`docs/handoff/CODEX-DOOR-DEAD-01/report.md` exists and contains the pasted runtime reproduction evidence (jobId, job-file contents, job-log tail), the mechanism, and the fix — ending with DELIVERABLE_COMPLETE."
    authored_at: 2026-08-16T07:06:07Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/codex-task.sh, plugins/leadv2/scripts/tests/test-codex-door.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# MISSION — CODEX-DOOR-DEAD-01 (the provider is healthy; both leadv2 codex doors produce nothing)

Ledger row: `SD-CODEX-DISPATCH-DOOR-DEAD-01` in the persona-engine repo. Codex is currently locked
out for 6h, which is a stopgap, not a fix — it costs us the whole codex arm on every lane.

## The evidence

On 2026-08-16, in `persona-engine`:

- **Dispatch door.** Four lanes (`8c576a71`, `3063f046`, `f7f1c2c8`, `b2714233`) were routed to codex
  and wrote **zero bytes** — no `developer.stream.jsonl`, no file touched in the lane worktree — while
  `leadv2-dispatch-product-close` polled `waiting_worker` for 20+ minutes each. A fifth
  (`4b7593fe`) ended `blocked / worker_timeout`.
- **Review arm.** `ee807b33` returned `blocked / reason=review_body_lost, arm=codex` **twice**. The
  same diff reviewed on opus produced a full report immediately.
- **The provider is fine.** `codex-task.sh task --background --write --effort medium "reply with
  exactly: OK"` from the same repo, same shell environment, returned `OK` in ~60s. Quota is healthy:
  `leadv2-quota-live.sh codex` reads `used_percent: 27`.

So the fault is between `leadv2-dispatch-code.sh` / `leadv2-review-run.sh` and a codex process that
demonstrably works when invoked directly.

## What to find

Why a codex worker spawned through the dispatch door produces no output, and why the codex review arm
loses its report body. They may be one fault or two — do not assume.

Start from the difference that matters: what the dispatcher's codex branch does that a direct
`codex-task.sh task` invocation does not. Working directory, environment, the guard armed at spawn
(`codex-guard.sh`), the quota-watch, stdin handling (`< /dev/null` is a known requirement in this
repo), how the handle is polled, and where the body is expected to land versus where codex writes it.

Reproduce it before proposing anything. A hypothesis from reading the spawn path is not a diagnosis —
this repo's own rule is that code-reading makes hypotheses and runtime confirms them.

## Second, smaller finding to fix while you are here

`record-quota-lockout` cannot express "this provider is broken, stand it down": called with
`--provider codex --hours 3` it recorded `arm_postspawn_verdict … quota=no` and left an **expired**
lockout file untouched, so the router picked codex again minutes later. The lockout had to be written
by hand. There should be a supported way to stand a provider down for a duration, distinct from
"out of quota".

## Hard constraints
- **Never `reset --hard`, `clean`, or `stash`** in this tree — it is shared with three live repos and
  other sessions edit it concurrently. Re-`git diff` immediately before you `git add`.
- Do not touch `docs/leadv2/open-threads.md`.

## Deliverable
`docs/handoff/CODEX-DOOR-DEAD-01/report.md`: the reproduction, the mechanism, the fix (or, if the fix
is large, the mechanism plus the smallest safe mitigation), and the lockout-duration support.
End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-3b96b97c" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.