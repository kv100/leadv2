# Architect prepass — FORK-RUNS-A-SESSION-01, fix round 1

Target worktree: `.claude/worktrees/810129d0` (resume, do not re-create).
Review under repair: `docs/handoff/dispatch-810129d0/review-codex.md` — FAIL, 0 critical, 3 high.

This is a design, not an implementation. No code is written here.

---

## 0. Ground truth read (what the code does today)

| Fact | Evidence |
|---|---|
| `leadv2-lane-worktree.sh ensure` **never fails** — on any git error, kill-switch `LEADV2_LANE_WORKTREE=off`, missing task_id, or unresolvable root, it calls `fallback()` which prints `$ROOT`, the **shared checkout**, and returns 0 | `leadv2-lane-worktree.sh:64-65, 94-97, 116-125, 151-153` |
| `preflight` accepts that return value on the sole test `[[ -d "$lane_root" ]]` — the shared checkout is a directory, so the check always passes | `leadv2-fork-session.sh:107-111` |
| `leadv2-ask.sh` mints a fresh random QID per invocation (`q-$(secrets.token_hex(4))`) | `leadv2-ask.sh:184` |
| `cmd_ask` calls `leadv2-ask.sh` unconditionally on every invocation, so each retry after exit 3 creates a **new** question record and polls only the new one | `leadv2-fork-session.sh:175`, exit 3 at `:225` |
| `leadv2-ask.sh` has a degrade path that, when the control-plane write fails, records the declared default and prints a **label** where `--no-block` normally prints a QID | `leadv2-ask.sh:317-339` |
| The mission forbids `cd` and says "commit inside the lane", but names no lane-scoped git form — a bare `git commit` uses the shared session CWD | `prompts/fork-session-mission.md:15, 39-40` |

`cmd_path_of` (`leadv2-lane-worktree.sh:157-166`) already implements exactly the
validation `preflight` is missing: directory exists **and** appears in
`git worktree list --porcelain` under its physical path. It is the reference
predicate for H1 — reuse its shape, do not invent a second one.

---

## 1. H1 — a fork that cannot get isolation must refuse

### Design

`ensure`'s never-block contract is correct **for lanes** and wrong **for forks**.
A lane that loses isolation degrades to the historical behaviour a lead already
survives. A fork sharing the lead's session CWD in the shared checkout is the
2026-07-28 mutual-clobber incident by construction. So do not change
`leadv2-lane-worktree.sh` (it is on the untouched-by-design list, `:45-47`, and
other callers depend on never-block). Put the strictness in `preflight`, which is
the fork-specific caller.

Add `assert_isolated_lane()` to `leadv2-fork-session.sh`, run **after** `ensure`
and **before** `leadv2_active_register` (so a refusal leaves no registry row and
no `fork-lane.env` to mislead a later reader). Four conjunctive checks:

1. **Kill-switch is fatal here.** If `LEADV2_LANE_WORKTREE == off` → refuse before
   even calling `ensure`. Reason string: `lane isolation disabled
   (LEADV2_LANE_WORKTREE=off) — a fork-owned session requires an isolated lane`.
   Codex asked for this explicitly ("including when lane isolation is disabled").
2. **Expected path.** Recompute the lane path the same way `lane_dir()` does —
   `${LEADV2_WORKTREE_DIR:-$project_root/.claude/worktrees}/$task_id` — and compare
   the **physical** form (`cd … && pwd -P`) of both sides. macOS `/tmp → /private/tmp`
   makes a textual compare wrong; `phys()` at `leadv2-lane-worktree.sh:106` is the
   precedent to mirror.
3. **Registered worktree.** `git -C "$project_root" worktree list --porcelain` must
   contain `^worktree <phys lane_root>$`. This is what makes "shared checkout
   returned" detectable: the main checkout **is** listed by `worktree list` as the
   first entry, so check 2 (path ≠ expected) is what rejects it, and check 3 rejects
   a stale directory that git no longer tracks. Both are needed — neither alone
   covers both failure modes.
4. **Branch identity.** `git -C "$lane_root" symbolic-ref --short HEAD` must equal
   `worktree-<task_id>`. Guards the case where `ensure`'s second attempt attached the
   worktree to a pre-existing branch that has since been switched, and guarantees
   `leadv2-deploy-merge.sh`'s `worktree-<id>` resolution will find it later.

Any failure → `log_error` naming **which** check failed and the two values compared,
then `exit 1`. `preflight`'s documented contract already is "fails loud, the lead must
not spawn the fork" (`leadv2-fork-session.sh:58-60`) — this makes the code match the
header comment.

### Explicitly not done

- No silent repair, no retry loop, no `--force` escape on `preflight`. A `--force`
  here would be exactly the degrade path being removed.
- `ensure`'s own fallback stays. Non-fork lanes keep never-block.

### Risk

`ensure` may have printed a diagnostic to `$ERRF` and returned the shared root; the
refusal message must point at `${LEADV2_LANE_WORKTREE_ERRF:-/tmp/pe-lane-worktree.err}`
or the operator gets a refusal with no cause. Mitigation: include that path in the
error text.

---

## 2. H2 — the pending Gate-1 question must survive a retry

### Design

Persist the question identity per task, outside the lane (the lane can be reaped;
the control plane is the shared durable surface, and `leadv2-answer.sh` already
writes there).

**Record:** `<control-plane>/fork-ask/<task_id>.yaml` — a new sibling directory of
`questions/`, deliberately **not** inside `questions/` so `/leadv2 questions` and any
`questions/*.yaml` glob are unaffected. Fields:

| Field | Purpose |
|---|---|
| `qid` | the question to poll on every subsequent invocation |
| `fingerprint` | `sha256(question ‖ "\n" ‖ sorted options ‖ default_option ‖ phase)` — identifies "the same question" across retries |
| `asked_at` | ISO-8601, for the operator reading a stuck gate |
| `question` | verbatim, so a refusal can quote what is still pending |

**`cmd_ask` control flow (replacing the unconditional ask at `:175`):**

1. Compute `fingerprint` from this invocation's arguments.
2. Read the record if present.
   - **No record** → ask (mint QID), write the record, then poll.
   - **Record, fingerprint matches, `<control-plane>/questions/<qid>.yaml` exists and
     is not `answered`** → **do not ask again**; poll that QID. This is the fix: one
     question, N bounded polls.
   - **Record, fingerprint matches, question file missing** → stale record (control
     plane rotated/wiped). Log `stale pending record for qid=… — question file gone,
     re-asking`, delete the record, ask fresh.
   - **Record, fingerprint DIFFERS, prior question still pending** → `exit 1`, quoting
     the pending QID and its question text, with `answer it via /leadv2 reply, or run
     'ask --cancel-pending <task-id>' to withdraw it`. A fork must not stack a second
     Gate-1 question on top of an unanswered one — that is precisely the
     "duplicate prompts, answer lands against a question nobody is polling" mode.
   - **Record whose question is already `answered`** → return the recorded answer,
     delete the record, `exit 0`. This closes the race where the founder answers
     between the poll deadline and the retry.
3. On a successful answer, **delete the record** before `exit 0`, so the next genuine
   Gate-1 question in the same task is unblocked.
4. On poll-cap expiry, **keep** the record and `exit 3`, logging
   `qid=… still pending — re-invoke to resume polling THIS question` (today's message
   implies a fresh ask, which is what misled the implementation).

**Concurrency:** two invocations of `ask` for one task should not both mint a QID.
Guard the read-modify-write with an `mkdir`-based lock (`<control-plane>/fork-ask/<task_id>.lock`,
`mkdir` is atomic on every filesystem in play) held only across steps 1–2, never across
the poll. Stale lock older than 120s is broken with a logged warning. In practice a
single fork serialises its own calls; the lock is cheap insurance against a lead
re-running `ask` for the same task.

**"Unanswered gate blocks rather than passes" — three parts:**

- `exit 3` writes **nothing to stdout** (already true at `:224-225`; keep it, and add a
  test asserting stdout is empty, because a fork that reads stdout as "the answer"
  would otherwise read a log line).
- QID validation: `--no-block` is contracted to print a QID, but the degrade path at
  `leadv2-ask.sh:317-339` can print a chosen **label** instead when the control-plane
  write fails. `cmd_ask` must reject any `qid` not matching `^q-[0-9a-f]{8}$` with
  `exit 1` ("ask degraded to a default without a control-plane record — refusing to
  treat a degraded write as an answered gate"). Accepting it would let a failed write
  manufacture the founder's consent, which is H2's whole complaint.
- Mission text: `exit 3` explicitly means *the gate is NOT passed*. The fork may
  continue ungated work; it may not enter Phase 4 or any step the gate protects.

### Risk

Deleting the record on answer while a second process still polls the same QID is
benign — the second poll reads `questions/<qid>.yaml`, which `leadv2-answer.sh` leaves
in place; it returns the same label.

---

## 3. H3 — fork commits can target the lead checkout

**The finding holds.** It is not paper-overable by prompt wording alone, because the
current mission's own Phase 6 line (`fork-session-mission.md:39-40`) says "commit
inside the lane" while the only concrete git command it shows is a `cd` into
`PROJECT_ROOT`. A fork that reads that literally, with the session CWD at the lead
checkout, commits to the lead's branch.

### Design — two layers, mechanism first

**(a) A lane-scoped commit wrapper** (Codex's own recommendation, second form). New op:

```
leadv2-fork-session.sh commit <task-id> -m "<message>" [--all|--paths <p> …]
```

Behaviour:
1. `lane_root="$(leadv2-lane-worktree.sh path-of <task-id>)"`; empty → `exit 1`
   (no lane, nothing legitimate to commit).
2. Re-run `assert_isolated_lane` (§1). The same predicate that gates spawn gates the
   commit — a lane that lost its registration between preflight and Phase 6 must not
   receive a commit either.
3. Refuse when the resolved lane root equals the project root (belt-and-braces against
   a future `path-of` regression).
4. `git -C "$lane_root" add -- <paths|-A>` then `git -C "$lane_root" commit -m "<msg>"`.
   Every git invocation carries `-C "$lane_root"`; **no `cd`, no bare `git`.**
5. Empty-index commit → `exit 0` with `nothing to commit in lane <id>` (idempotent
   re-run must not fail a Phase 6 retry).

**(b) Mission wording that names the mechanism.** Replace "commit inside the lane" with:
*every* git operation is either `bash <plugin>/scripts/leadv2-fork-session.sh commit …`
or an explicit `git -C "$LANE_ROOT" …`. A bare `git` command is added to the banned
list beside `EnterWorktree`/`cd`/`git reset --hard`. The Phase 6 land step keeps its
`(cd <PROJECT_ROOT> && … leadv2-deploy-merge.sh)` subshell — that is a process-local
cd into an existing, audited lead-side script, not hand-rolled git, and it is the one
place the lead checkout is legitimately the git cwd.

### Risk

The wrapper is opt-in by prompt; nothing stops a fork calling bare `git`. Full
enforcement would need a PreToolUse hook matching `^git ` without `-C`, which is a
separate blast radius (it would fire on every lead session too). Out of scope here —
state it in the report as a residual, do not claim it is enforced.

---

## 4. Report correction — narrow the ownership claim to what the code now does

`plugins/leadv2/commands/leadv2.md:147-170` currently reads as "Phase 0→8 end to end,
minus carve-outs A/B/C". After these fixes the honest table is:

| Phase | Fork owns? | After this round |
|---|---|---|
| 0 Intake | yes, minus lane creation | **and only if `preflight` succeeded** — no isolated lane, no fork; the lead runs the task itself |
| 1 Classify / 2 Plan | yes | unchanged |
| 3 Gate 1 | **conditionally** | fork asks once; exit 3 = gate NOT passed, work that the gate protects stays blocked until exit 0. A fork cannot self-clear its own gate. |
| 4 Build / 5 Review | yes | unchanged; no gate relaxed |
| 6 Deploy | **split** | commit is fork-owned **via the `commit` wrapper only**; the land step invokes `leadv2-deploy-merge.sh` against the lead checkout — fork-invoked, not fork-authored git |
| 7 Verify | yes | unchanged |
| 8 Close | yes up to `phase8-passed.flag` | reaping + self-spawn remain lead-side (carve-outs B, C) |

Residual, stated not hidden: bare `git` from a fork is discouraged by mission text and
unenforced by hook. `phases.md:87` and `:344` need the same "preflight must succeed or
there is no fork" qualifier — today they read as if the lane always exists.

---

## 5. Files this round touches

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-fork-session.sh` | `assert_isolated_lane()`; `preflight` refuses instead of degrading; `cmd_ask` QID persistence + fingerprint + lock + QID-shape validation; new `commit` op; header comment updated (exit-code table, new op, new control-plane dir) |
| `plugins/leadv2/prompts/fork-session-mission.md` | `git -C "$LANE_ROOT"` / `commit` wrapper mandatory, bare `git` banned; exit 3 ⇒ gate not passed; preflight-failed ⇒ no fork |
| `plugins/leadv2/scripts/tests/test-fork-session.sh` | new cases, below |
| `plugins/leadv2/commands/leadv2.md` | ownership table per §4 |
| `plugins/leadv2/docs/phases.md` | `:87` / `:344` qualifier |

**Not touched (untouched-by-design list holds):** `leadv2-ask.sh`, `leadv2-answer.sh`,
`leadv2-lane-worktree.sh`, `leadv2-deploy-merge.sh`, `leadv2-phase8-close.sh`,
`leadv2-state-atomic-write.sh`, `leadv2-active-registry.sh`.

### Test cases to add (Codex asked for failure/retry coverage explicitly)

1. `LEADV2_LANE_WORKTREE=off` → `preflight` exits 1, stderr names the kill-switch, and
   `active.yaml` gains **no** row for the task.
2. `ensure` forced to fall back (stub `git worktree add` failure via a shim on PATH, or
   `LEADV2_WORKTREE_DIR` pointed at an unwritable path) → `preflight` exits 1 and does
   **not** print the shared root on stdout.
3. Happy path unchanged: `preflight` prints the lane root, twice, identically.
4. `ask` retry: invoke, get exit 3; invoke again with identical args; assert
   `ls <control-plane>/questions/*.yaml | wc -l` is **1**, not 2.
5. Answer the ORIGINAL qid via the real `leadv2-answer.sh`, re-invoke `ask` → exit 0,
   stdout is the chosen label, record removed.
6. `ask` with a different question while one is pending → exit 1, stderr quotes the
   pending question.
7. `ask` exit 3 writes nothing to stdout.
8. `commit` puts the commit on `worktree-<id>` in the lane and leaves the project
   root's `git log` unchanged.

---

## 6. Non-goals

- No change to `leadv2-lane-worktree.sh`'s never-block contract for ordinary lanes.
- No PreToolUse hook enforcing `git -C` (separate task, wider blast radius).
- No new founder-facing surface: the question still lands in the control-plane
  `questions/` dir and is answered with `/leadv2 reply`.
- No `reset --hard` / `clean` / `stash` anywhere; three live repos share this tree.
- `docs/leadv2/open-threads.md` untouched.
- No widening of the ownership claim — §4 narrows, it does not restore.

---

## acceptance:

```yaml
acceptance:
  authored_at: 2026-08-16T21:04:56Z
  criteria:
    - surface: log_line
      observable: >
        With lane isolation unavailable, the operator running preflight sees a
        stderr line naming the task and stating that the fork refuses because it
        did not get an isolated lane, and the lane path it expected versus what it
        got — and no lane root is printed on stdout for a caller to use.
    - surface: file_artifact
      observable: >
        After a Gate-1 question is asked and the fork re-invokes ask twice more
        with the same question, the control-plane questions/ directory holds
        exactly one question file for that task — a reader listing the directory
        sees one pending question, not three.
    - surface: rendered_line
      observable: >
        In /leadv2 questions the founder sees a single Gate-1 entry for the task;
        after answering it, the fork's next ask reports the chosen option label
        and the gate is shown as answered rather than re-appearing as a new
        pending question.
    - surface: file_artifact
      observable: >
        After the fork commits through the wrapper, git log in the lane shows the
        new commit on branch worktree-<task-id>, and git log in the main checkout
        shows its previous tip unchanged.
    - surface: rendered_line
      observable: >
        The fork-ownership table in /leadv2 documentation shows Phase 6 split
        (commit owned, land delegated) and Phase 3 conditional, with a stated
        residual that a bare git command from a fork is not mechanically blocked.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-fork-session.sh, plugins/leadv2/prompts/fork-session-mission.md, plugins/leadv2/scripts/tests/test-fork-session.sh, plugins/leadv2/commands/leadv2.md, plugins/leadv2/docs/phases.md

DELIVERABLE_COMPLETE
