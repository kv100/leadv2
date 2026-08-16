Product implementation task dispatch-28c1c11d. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# CODEX-DOOR-DEAD-01 — architect prepass (dispatch-28c1c11d-architect)

Scope: land the already-written review-base fix with a red-first test, decide the dispatch-door
question by reproduction, and add duration-based provider stand-down to `record-quota-lockout`.
**No implementation in this document.**

---

## 0. State on disk (verified this pass)

| Fact | Evidence |
|---|---|
| Worktree `.claude/worktrees/3b96b97c` holds the fix | `git diff --stat` → `plugins/leadv2/scripts/leadv2-review-run.sh` +67/-1 |
| No report exists | `docs/handoff/CODEX-DOOR-DEAD-01/` contains only `mission.md`, `mission-finish.md` |
| No test exists for the base resolution | `ls tests/ \| grep base` → none |
| The worktree also carries **unrelated** journal churn | same `git diff --stat`: `dispatch-567ba028/journal.md`, `dispatch-59ae8b51/journal.md` |
| `run-core-offline.sh` is the suite registry | line 114 registers `test-review-body-persist.sh` |

**Implementer constraint (P0):** the two `docs/leadv2/tasks/*/journal.md` hunks are ambient
router churn from other lanes, not this lane's work. Stage **only** the paths in `LANE_WRITES`
(`git add <path>` per file, never `git add -A`, never `git add .`). Re-run `git diff <file>`
immediately before each `git add` — three live repos share this tree.

---

## 1. Fault A — review base (already diagnosed, needs landing)

### Mechanism (confirmed, keep as written)
`run_reviewer_arm()` at `leadv2-review-run.sh:256` passed `--base HEAD` unconditionally.
codex-companion's `resolveReviewTarget` treats an explicit `--base` as authoritative and never
falls back to working-tree mode, so a lane that has **already committed** its work diffs its own
HEAD against itself → empty branch diff → short/empty stdout. codex still writes its
`[codex-task] tier=…` banner to **stderr** regardless, so the REVIEW-BODY-PERSIST-01 guard sees a
live arm with no body and correctly reports `review_body_lost`. That is `ee807b33`'s two verdicts.

### The change already in the worktree — accepted as designed
`_review_resolve_codex_base()` resolves, in order:
1. `merge-base $LEADV2_LANE_START_SHA HEAD` (inherited env, exported by `spawn_product_close`)
2. `merge-base origin/main HEAD`
3. rc1 → arm is **skipped** (`review_arm_skipped … reason=no_base_resolved`, `review_rc=77`)

with a degenerate-environment escape: if `ROOT` is not a git work tree at all, print the literal
`HEAD` and rc0, so fixture tempdirs do not trip the refusal path. It additionally short-circuits
on an empty diff (`reason=empty_diff`) and now passes `--cwd "${ROOT}"`.

**Architect verdict: no redesign.** The two-candidate resolution mirrors
`leadv2-dispatch-product-close.sh:_pc_diff_base`, which is the right precedent. Two notes for the
implementer, neither a blocker:

- `git diff --quiet "${codex_base}" --` compares base↔working-tree. On a committed lane that is
  the same as base↔HEAD, which is what we want. Keep it.
- `review_rc=77` must be a value the caller's arm-outcome switch already treats as
  "arm produced nothing, not a crash". Verify that one call site before committing; if 77 is
  unhandled it will surface as an opaque non-zero rather than a skip.

### Test — `plugins/leadv2/scripts/tests/test-review-codex-base.sh` (to-create)
Red-first: written against the **pre-fix** script it must fail; against the post-fix script it
must pass. Drive the real `leadv2-review-run.sh` (never a reimplementation), stub the codex
launcher via `LEADV2_DISPATCH_CODEX_BIN` pointing at a recorder script that appends its own argv
to a file and exits 0 — the assertion is on **what base codex was handed**, not on codex's output.
Follow `test-review-body-persist.sh` structure: `lv2_mktemp_dir`, per-scenario throwaway git repo,
`bash -n` + `/bin/bash 3.2 -n` syntax checks first, PASS/FAIL counters, rc0 = all green.

| # | Scenario | Assertion |
|---|---|---|
| 1 | Lane repo with `origin/main` and one commit on top; `LEADV2_LANE_START_SHA` set to the pre-commit SHA | recorded argv contains `--base <sha>` where `<sha> != $(git rev-parse HEAD)`; argv contains `--cwd <ROOT>` |
| 2 | Same, but `LEADV2_LANE_START_SHA` unset | base resolves from `origin/main`, still `!= HEAD` |
| 3 | Committed lane, no start-SHA and no `origin/main` | codex launcher is **never invoked**; journal shows `review_arm_skipped arm=codex reason=no_base_resolved` |
| 4 | Lane whose HEAD == base (nothing to review) | launcher never invoked; `review_arm_skipped … reason=empty_diff` |
| 5 | `ROOT` is a non-git tempdir | launcher **is** invoked with the literal `--base HEAD` (degenerate escape preserved) |
| 6 | Regression guard | recorded argv never contains a bare `--base HEAD` in scenarios 1–4 |

Register in `run-core-offline.sh` beside line 114:
`run_check "review codex base (committed lane never diffs HEAD↔HEAD)" bash "$TEST_DIR/test-review-codex-base.sh"`.

---

## 2. Fault B — the dispatch door. Same root cause? **No.**

`8c576a71`, `3063f046`, `f7f1c2c8`, `b2714233` were routed to codex as **builders** and wrote zero
bytes while the close loop polled `waiting_worker` 20+ minutes.

### Two hypotheses already killed by reading, so the reproduction does not waste an arm on them

- **H1 — same fault as A (empty diff).** Falsified by construction: the builder path never asks
  codex for a diff. `--base` is not on the builder argv at all.
- **H2 — missing `--cwd`, so codex worked in the wrong tree.** Falsified on disk:
  `leadv2-dispatch-code.sh:2393` already spawns
  `codex-task.sh task "${mission}" --background --cwd "${WORK_ROOT}" --tier …`.
  The builder does pass `--cwd`. This is the tempting answer and it is wrong.

### Leading hypothesis H3 — **enqueue is mistaken for spawn**
`--background` returns rc0 the instant codex-companion's `enqueueBackgroundTask` *accepts* the
job; the script's success condition is only that a `task-<b36>-<rnd>` jobId parses out of stdout
(`leadv2-dispatch-code.sh:2411`). Nothing downstream ever proves the enqueued job **started**.
The script's own comment at line 2463 already admits this window problem. So: a job that is
accepted and then never runs — worker not draining the queue, or dying on a terminal error before
its first write — presents *exactly* as observed: valid handle, `waiting_worker` forever, zero
bytes, no `developer.stream.jsonl`. And because the death is not quota-shaped, the close gate's
`record-quota-lockout` fallback classifies it `quota=no` and does nothing — which is precisely the
`arm_postspawn_verdict … quota=no` line the mission reports.

**This is a second, distinct fault: leadv2 has no liveness proof between "job accepted" and
"job produced its first byte."**

### Reproduction the implementer must run (decides it, does not read the spawn path)
Against a scratch worktree, **not** a live lane:

1. `bash plugins/leadv2/scripts/codex-task.sh task "<trivial: create FILE.txt containing OK>" --background --cwd <scratch> --tier standard` → capture the jobId.
2. Poll codex-companion's own job status and the scratch dir for the first written byte, at
   10s intervals for ≤5 minutes. Record: does the job leave `queued`/`waiting`? Does any byte land?
3. Two arms to separate leadv2 from codex-companion:
   - **B1** codex runtime available → if the file lands, leadv2's spawn contract is sound and the
     four dead lanes died in the runtime (queue starvation / terminal error).
   - **B2** codex runtime locked out or stopped → if enqueue **still returns rc0 with a valid
     jobId** and no byte ever lands, H3 is confirmed directly and this is the mechanism.

Codex is currently locked out for 6h, so **B2 is runnable now and B1 is not.** Run B2 first; if B2
alone confirms H3, that is a sufficient verdict — say so and do not wait out the lockout.
If neither arm reproduces, say **plainly** that it did not reproduce and ship the mitigation below
anyway; do not invent a mechanism.

### Smallest safe mitigation (ship regardless of the repro outcome)
A **first-byte deadline** on the codex builder arm: after a successful enqueue, if no byte appears
in the arm's output/stream within `LEADV2_CODEX_FIRST_BYTE_SECS` (default 180), emit
`arm_dead_no_first_byte arm=codex task=… job=<jobId>`, stand codex down for a duration via the new
subcommand in §3, and spill to the next arm in the ladder. This converts a 20-minute silent hang
into a bounded, observable, self-healing spill. **Design it and state it; only implement it if §1
and §3 are already green** — it is the largest of the three changes and the least proven.

---

## 3. Duration-based stand-down for `record-quota-lockout`

### Present behaviour (verified)
`cmd_record_quota_lockout` (`leadv2-dispatch-code.sh:3909`) **requires** `--arm` and `--handle`,
fetches the arm's final output, and if `_quota_shaped` says no, emits
`arm_postspawn_verdict … quota=no` and exits 0 **without writing anything**. There is no `--hours`.
Given `--provider codex --hours 3` it therefore did exactly what was reported: recorded a
`quota=no` verdict, left the expired lockout file untouched, and the router re-armed codex minutes
later. The gap is real and is a missing capability, not a bug in the quota path.

### Design — a new, explicitly distinct mode
Add to `cmd_record_quota_lockout` an argument `--hours <N>` (accept `--minutes <N>` as the finer
sibling), plus `--reason <text>` (default `provider_broken`).

**Mode selection, unambiguous:**
- `--hours`/`--minutes` present → **stand-down mode**. `--handle` becomes optional; `--provider`
  (or `--arm`, which resolves via `_arm_provider`) is required. Skip `_arm_final_output` and
  `_quota_shaped` **entirely** — a stand-down asserts brokenness, it does not detect quota.
- Neither present → today's quota-classification mode, byte-identical. No existing call site
  passes a duration flag, so this is strictly additive.

**Write path:** compute `locked_until` as `now + N` using the same dual `date -u -v+…` /
`date -u -d …` idiom as `_default_quota_lockout_iso` (macOS + GNU), then call the existing
`_record_quota_lockout "${provider}" "${_iso}" "standdown:${reason}"`. The `source` field is what
distinguishes the two on disk; the schema is otherwise unchanged.

**Reader: no change required.** `_quota_precheck` reads only `locked_until_epoch` and compares to
now, so a stand-down record suppresses the provider through the identical path an exhausted-quota
record does. This is why the design is additive-only.

**Emit:** `quota_standdown_recorded provider=<p> hours=<N> until=<iso> reason=<reason> task=<sig8>`
— a **distinct** decision verb from `quota_lockout_recorded`, so a stand-down is never later
misread as a quota event when a lane is reconstructed from its journal.

**rc contract:** unchanged, always exit 0. Validation failures (`--hours` non-numeric, ≤0, or no
provider resolvable) log to stderr and exit 0 — the close gate's poll loop must never die here.

**Guard:** `--hours` must be an integer in `1..168`. Reject non-numeric and out-of-range; an
unbounded stand-down is how a provider silently disappears for a week.

### Test — `plugins/leadv2/scripts/tests/test-quota-standdown-duration.sh` (to-create)
| # | Invocation | Assertion |
|---|---|---|
| 1 | `record-quota-lockout --provider codex --hours 3` | `quota-lockout-codex.json` exists, `locked_until_epoch` ≈ now+10800 (±120s), `source` starts `standdown:` |
| 2 | Same, over a **pre-existing expired** lockout file | file is overwritten, epoch is now in the future (the exact reported failure) |
| 3 | Same, then run the quota precheck | codex is refused by the precheck |
| 4 | `--arm codex --handle <h>` with non-quota output, **no duration** | legacy path intact: `arm_postspawn_verdict … quota=no`, no file written |
| 5 | `--provider codex --hours abc` / `--hours 0` / `--hours 999` | rc0, no file written, stderr names the bad value |
| 6 | journal | scenario 1 emits `quota_standdown_recorded`, **not** `quota_lockout_recorded` |

Register in `run-core-offline.sh`.

---

## 4. Constraint checklist

1. **Env vars** — new names `LEADV2_CODEX_FIRST_BYTE_SECS` (§2, deferred) follow the `LEADV2_*`
   convention; no `LEAD_V2_*` drift. `LEADV2_LANE_START_SHA` already exists and is consumed, not
   introduced. No new var is required for §1 or §3.
2. **Paths** — every path in LANE_WRITES exists except the two test files, marked `(to-create)`
   above. `docs/handoff/CODEX-DOOR-DEAD-01/` exists.
3. **`claude -p`** — this lane introduces none. N/A.
4. **Concurrent access** — `run-core-offline.sh` is appended by many lanes; append a single line at
   the end of the review-suite block and re-diff immediately before `git add`. The lockout dir is
   last-write-wins per provider by existing design (`.tmp.$$` + `mv -f`); a stand-down racing a
   quota write is acceptable — both suppress the provider.
5. **Config contradiction** — `--hours` is a new flag name; `grep -n -- '--hours' plugins/leadv2/`
   returns nothing today. `source` values are free text already (`launcher_refusal:*`,
   `postspawn_failure:*`), so `standdown:*` introduces no conflict.

## 5. Non-goals (implementer: ignore these)

- Changing the REVIEW-BODY-PERSIST-01 `review_body_lost` guard. It behaved correctly; it reported
  a real absence. Leave it.
- Changing codex-companion / `resolveReviewTarget` itself. Out of this repo.
- Any edit to `docs/leadv2/open-threads.md`.
- Deleting or unwinding the four dead lanes.
- Retrofitting the first-byte deadline onto the glm/kimi/sonnet arms.
- Any `reset --hard`, `clean`, or `stash` in the shared worktree.

## 6. Sequencing

1. §1 test red against pre-fix → land the `leadv2-review-run.sh` change → test green → commit on
   `main` in `~/Projects/leadv2`.
2. §3 stand-down + its test → commit.
3. §2 reproduction (B2 arm) → verdict.
4. §2 mitigation only if 1–3 are green.
5. `docs/handoff/CODEX-DOOR-DEAD-01/report.md`: mechanism, fix, test, dispatch-door verdict,
   stand-down. (Deliverable, not a LANE_WRITES entry.)

---

```
acceptance:
  - surface: log_line
    observable: "In a lane journal, a committed lane's codex review arm shows a --base that is a
      commit SHA different from that lane's own HEAD; a lane with no resolvable base instead shows
      'review_arm_skipped arm=codex reason=no_base_resolved' and no 'review_body_lost' verdict for
      that arm."
    authored_at: 2026-08-16T00:00:00Z
  - surface: file_artifact
    observable: "After a human runs record-quota-lockout with --provider codex --hours 3, the file
      quota-lockout-codex.json shows a locked_until timestamp about three hours in the future and a
      source field beginning 'standdown:', replacing whatever expired value was there before."
    authored_at: 2026-08-16T00:00:00Z
  - surface: log_line
    observable: "The journal for that stand-down shows the line 'quota_standdown_recorded
      provider=codex hours=3', and the next dispatch's journal shows codex refused by the quota
      precheck instead of being armed."
    authored_at: 2026-08-16T00:00:00Z
  - surface: file_artifact
    observable: "docs/handoff/CODEX-DOOR-DEAD-01/report.md reads as a finished report: the empty-base
      mechanism, the landed fix and its test, and an explicit verdict on the dispatch door naming
      either a second mechanism or stating plainly that it did not reproduce."
    authored_at: 2026-08-16T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-review-codex-base.sh, plugins/leadv2/scripts/tests/test-quota-standdown-duration.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# MISSION — CODEX-DOOR-DEAD-01, finish it (you found the review half; land it and answer the dispatch half)

Resume the same worktree (`3b96b97c`). It holds a 66-line change to
`plugins/leadv2/scripts/leadv2-review-run.sh` and **no report**, so nothing has landed and nobody can
act on what you found.

## What you already established — keep it, it looks right

`REVIEW-CODEX-EMPTY-BASE-01`: codex's `--base HEAD` diffs a committed lane's current HEAD against
itself, because `resolveReviewTarget` treats an explicit `--base` as authoritative and never falls
back to working-tree mode. So an already-committed lane always hands codex an empty branch diff →
short stdout → and the body-persist guard correctly reports `review_body_lost`, because codex writes
its `[codex-task] tier=…` banner to stderr whether or not a real body exists.

That explains **`ee807b33`'s two `review_body_lost` verdicts exactly.** Finish it:

1. A test that a committed lane resolves a base which is not its own HEAD, and that a bare `HEAD`
   base is refused rather than silently reviewing nothing. Red against the pre-fix script.
2. Commit on `main` in `~/Projects/leadv2`.
3. Write `docs/handoff/CODEX-DOOR-DEAD-01/report.md` — the mechanism, the fix, the test.

## The half still unanswered — the dispatch door

Four lanes (`8c576a71`, `3063f046`, `f7f1c2c8`, `b2714233`) were routed to codex as **builders** and
wrote zero bytes: no `developer.stream.jsonl`, no file touched in the lane worktree, while the close
loop polled `waiting_worker` for 20+ minutes. That is a different failure from an empty review diff —
a builder does not diff anything.

Is it the same root cause or a second one? Decide it with a reproduction, not by reading the spawn
path. If it is a second fault, name the mechanism; if you cannot reproduce it, say so plainly and
give the smallest safe mitigation, because codex is currently locked out for 6h and that costs us the
arm on every lane.

## Also owed

`record-quota-lockout` cannot express "this provider is broken, stand it down": given
`--provider codex --hours 3` it recorded `arm_postspawn_verdict … quota=no` and left an **expired**
lockout file untouched, so the router picked codex again minutes later and killed another lane. Add a
supported duration-based stand-down, distinct from "out of quota".

## Hard constraints
- **Never `reset --hard`, `clean`, or `stash`** in this tree — three live repos share it. Re-`git
  diff` immediately before you `git add`.
- Do not touch `docs/leadv2/open-threads.md`.

## Deliverable
The committed fix, its test, the dispatch-door verdict, the lockout duration support, and
`docs/handoff/CODEX-DOOR-DEAD-01/report.md`. End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-28c1c11d" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.