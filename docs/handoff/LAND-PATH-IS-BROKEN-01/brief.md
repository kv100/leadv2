# LAND-PATH-IS-BROKEN-01 — the land path is not broken, it is unreachable: build the runner that reaches it

LANE_WRITES: plugins/leadv2/scripts/leadv2-land.sh,plugins/leadv2/scripts/tests/test-leadv2-land.sh,docs/handoff/LAND-PATH-IS-BROKEN-01/worker-report.md,docs/handoff/LAND-PATH-IS-BROKEN-01/run-all-registration.patch

All four paths are `(to-create)`. Nothing else may be written. `tests/run-all.sh`,
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` and `plugins/leadv2/scripts/leadv2-active-registry.sh`
are **held by another session — read them, never edit them** (see §8).
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`. Merge `main` into the lane FIRST.
Never commit `docs/leadv2/`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-*`.
Commit by LANE_WRITES pathspecs; an uncommitted exit is a failed round. Review-facing text in ENGLISH.

---

## 0. What the prior draft (2026-09-02) got right, and what it got wrong

**Confirmed by this investigation:**
- `leadv2-deploy-merge.sh` rebases, and rebase is the wrong operation for these lanes.
  Confirmed at `leadv2-deploy-merge.sh:98-118` — it runs `git rebase origin/main` against the task
  branch, in-place inside the lane worktree when one exists.
- The `deploy.sh not found` hard stop is real and still on the path: `leadv2-deploy-merge.sh:172-175`
  exits 1 when `.claude/leadv2-overrides/deploy.sh` is absent, **after** main has already been
  fast-forwarded and pushed at `:141-145`. So rc=1 genuinely can coexist with a landed main. The
  prior draft's item 4 (exit-code truth) stands.
- Landing from a throwaway worktree on the lane tip is right, for a reason the draft did not give:
  see §2, every lane worktree is dirty right now (0–20 modified tracked files each).

**Wrong, or materially incomplete:**
1. **`LANE_WRITES` named three files that do not exist and did not mark them `(to-create)`:**
   `plugins/leadv2/scripts/lib/leadv2-land.sh`, `plugins/leadv2/scripts/leadv2-worker-epilogue.sh`,
   `plugins/leadv2/scripts/tests/test-land-path.sh`. Verified absent on `main` today. A declaration
   that silently invents files is how a lane's write set stops meaning anything.
2. **It named `tests/run-all.sh` in `LANE_WRITES`.** That file is held. A lane that declares it will
   collide with the holding session. §8 gives the split.
3. **It diagnosed the wrong layer.** The draft's three causes are all *inside* `deploy-merge.sh`.
   But `deploy-merge.sh` has not been invoked since **2026-09-01T22:55:33Z** (last row of
   `docs/leadv2/merge-queue.jsonl`, 74 rows). Fixing its rebase step would have changed nothing for
   any of the lanes measured here, because none of them reached it. The real stop is two layers
   earlier — at the review gate (§2).
4. **It treated `deploy-merge.sh` as *the* landing path.** There are two, with different rules
   (§1). The one that actually fires in the automated flow is the T11 block inside
   `leadv2-dispatch-product-close.sh`, and it uses `merge --no-ff`, not rebase-then-ff.
5. **It assumed rebase-vs-merge is the blocker for behind-main lanes.** For a branch 1086 behind,
   neither works (§3). The draft's step 1 (`git merge origin/main` INSIDE the lane, then ff) is
   directionally right but is exactly the operation the merge-safety gate at `be1f6ce2` now exists
   to police, and the draft predates that gate.
6. **It said "9 lands tonight, 0 through the script".** The terminal ledger
   (`~/.claude/cache/dispatch-terminal-ledger/leadv2.jsonl`) contains **one row, all time**:
   `terminal=landed cause=review_gate_disabled`. Whatever landed by hand left no ledger trace at
   all. That is the observability hole in §4, and it is worse than the draft implies.

---

## 1. Census of the landing path — every step, by file:line

The path exists **twice**, with different rules, and the two do not share a line of code.

| # | Step | Path A — automated (`leadv2-dispatch-product-close.sh`) | Path B — Phase 6 (`leadv2-deploy-merge.sh`) | Status |
|---|---|---|---|---|
| 1 | Worker believes it is finished | worker commits in its own worktree; no epilogue script exists | same | **MISSING as code** — no `leadv2-worker-epilogue.sh` on disk. The commit is a mission-text obligation, not a mechanism. |
| 2 | Terminal state written | `_dl_note()` at `:168-193` → `leadv2-dispatch-ledger.sh` → `~/.claude/cache/dispatch-terminal-ledger/leadv2.jsonl` (`leadv2-dispatch-ledger.sh:160`) | n/a | **EXISTS, effectively dead** — 1 row all time. |
| 3 | Human/lead-readable verdict | `docs/handoff/dispatch-<sig8>/review-gate.md`, written at `:3403-3419` — note `HANDOFF="${ROOT}/docs/handoff/dispatch-${TASK}"` (`:210`), i.e. the **main checkout**, keyed by sig8, not by founder id | n/a | EXISTS and is the only working surface (63 rows since 09-01). |
| 4 | Decide the branch is mergeable | `leadv2-merge-safety-gate.sh` invoked at `:3447` | same gate invoked at `leadv2-deploy-merge.sh:127-139` | EXISTS (landed `be1f6ce2`), wired in both. |
| 5 | Perform the merge | `git merge --no-edit --no-ff "${_t11_branch}"` at `:3451`, serialized by `leadv2-merge-queue.sh acquire/release` at `:3441`/`:3457` | `git rebase origin/main` (`:98-118`) → `git merge --ff-only` (`:141`) → `git push origin main` (`:144`) | **EXISTS TWICE, DIFFERENT RULES.** A lands a merge commit locally and never pushes; B rebases then ff's then pushes. |
| 6 | Verify it actually landed | `lv2_branch_merged` (`leadv2-branch-merged.sh`) at `:3451` — merge-base --is-ancestor | `COMMIT=$(git rev-parse HEAD)` at `:145`, no ancestry re-check | A verifies, B assumes. |
| 7 | Record that it landed | `_dl_note landed review_verdict_pass …` at `:3453` | `deploy-verify.yaml` (control plane + handoff mirror) at `:180-300` | Both exist; A's ledger is dead (step 2), B's artifact requires the deploy override. |
| 8 | Record that it FAILED to land | A: `_dl_note pass_unlanded …` with cause `root_dirty` / `merge_would_revert_main` / `merge_conflict` (`:3437`, `:3459`, `:3494`). B: `write_blocker()` → `docs/handoff/<task>/merge-blocker.flag` (`:53-59`) | | **EXISTS, but only on the `pass` path.** A `blocked` or `fail` gate writes NO land-failure record at all — because it never attempted a land. See §4. |
| 9 | Push to origin | **ABSENT in A** (`:3451` merges locally only; nothing pushes) | `:144` | **A never pushes.** A lane "landed" by Path A is on local main only. |
| 10 | Clean up | `lane_deregister` + `leadv2-worktree-cleanup.sh --name` at `:3463-3487` | none | EXISTS in A only. |
| 11 | A runner that drives 1→10 on a schedule | none | none | **MISSING.** `leadv2-merge-queue.sh` has subcommands `enqueue`/`acquire`/`release`/`status` (`:284,289,317,322`) and **no `dequeue`/`next`/`process`**. It is a mutex, not a work queue. Nothing consumes it. The only cron entry on this machine is `leadv2-status-collector-guard.sh`. |

### 1a. The merge-queue, specifically

- **Who enqueues:** only two call sites, both `acquire` (which enqueues as a side effect):
  `leadv2-dispatch-product-close.sh:3441` and `leadv2-deploy-merge.sh:69`. `leadv2-bus.sh:40` and
  `leadv2-plugin-sync.sh` only reference it in comments / for lock-path resolution — they are not
  producers. So the "five callers" is really **two**.
- **Is the enqueue unreachable, guarded, failing, or never invoked?** Never invoked. `:3441` sits
  inside the `status: pass` branch of the review gate (§2 shows that branch is taken 4 times in 63),
  and `deploy-merge.sh` is a Phase-6 step a lead runs by hand. Both call sites are
  `[[ -x … ]] && … >/dev/null 2>&1` — so a failure to acquire is also silently swallowed.
- **Does the writer validate its row?** No. 24 of 25 `enqueued` rows carry `branch: "unknown"`; the
  `acquired` rows carry no `branch` key at all and the `released` rows carry neither branch nor pid.
  `branch` is never read, because there is no consumer. A row that cannot name its branch is
  accepted. **Recommendation: the queue is not the landing path and must not be turned into one in
  this lane.** It is a mutex; leave it a mutex. The runner in §5 acquires it, exactly as both
  existing paths do.
- **Is consumption scheduled?** No. There is no consumer of any kind. "The land path has no runner"
  is the accurate sentence, and it is the smaller fix — but it is not the whole fix, because a runner
  with nothing in `pass` state to run is still a no-op (§2).

---

## 2. Where the commits actually stop — measured, not theorised

### 2a. The debt is larger than the row says

| Scope | Lanes with ≥1 non-empty commit | Non-empty commits |
|---|---|---|
| Tips committed in the last 7 days | **38** | **75** |
| All local branches, all history | **110** | **178** |

Method: for every `refs/heads/*` except `main`, `git rev-list main..<b>`, and a commit counts only if
`git diff-tree --no-commit-id --name-only -r <c>` is non-empty. The row's "39 lanes / 91 commits" is
close to the 7-day figure and is a fair headline; the worker should know the true backlog is 110/178.
Empty anchor commits are real and dominant: ~179 branches are ahead of main by exactly 1 empty commit.

### 2b. The stop is one step, and it is the review gate — not the merge

Every automated land in this repo lives inside one `else` branch:
`leadv2-dispatch-product-close.sh:3419-3496`, entered only when the review verdict is `pass`.

63 `review-gate.md` files were written since 2026-09-01. Their statuses:

| status | count | share | reaches the merge code at `:3451`? |
|---|---|---|---|
| `blocked` | 42 | 67% | no |
| `fail` | 17 | 27% | no |
| `pass` | **4** | **6%** | yes |

Blocked reasons, ranked:

| reason | count | what it means |
|---|---|---|
| `selfcheck_failed` | 19 | the worker's own falsification/negative-control step went red; gate stops, no fix round is dispatched |
| `no_work` | 7 | terminal says nothing was produced — **and the branch has commits anyway** (the known lying-verdict shape) |
| `worker_timeout` | 4 | worker never returned |
| `arm_produced_nothing` | 4 | provider produced no diff |
| `review_roundcap` | 3 | review rounds exhausted |
| `empty_response` | 2 | provider returned nothing |
| `undiffable_write_set` / `suite_falsifiability_undetermined` / `review_body_lost` | 1 each | |

**So: this is ONE dominant cause, not several unrelated ones.** 94% of close attempts terminate in a
state that has no landing path *by construction* — `blocked` and `fail` do not merge, do not enqueue,
do not write a land-failure record, and do not schedule a fix round. The lane's commits then sit on a
branch nobody will look at again. The row's title asserts "the landing path is broken"; the measured
answer is **"the landing path is unreachable"**, which is a different and cheaper fix.

Secondary causes, real but far smaller:
- **Path A never pushes** (§1 step 9). Even a `pass` lane lands only on local `main`.
- **Path B has been idle since 2026-09-01T22:55:33Z.** Its rebase defects — the prior draft's entire
  content — are real but currently academic.
- **Every lane worktree is dirty.** 33 of 38 measured lanes have 1–20 modified tracked files right
  now; `:3435` fails the whole land to `pass_unlanded cause=root_dirty` on a dirty *main*, and
  Path B's rebase dies on a dirty *lane*. This is a genuine third cause and the prior draft found it.

### 2c. A false-uniform answer produced during this investigation — do not repeat it

Two plausible heuristics for "which handoff dir belongs to lane X" both returned a perfectly uniform
answer that was wrong. Picking the first `docs/handoff/dispatch-*` in a lane worktree alphabetically
returned `status: no_reviewer author: glm` for 38/38 lanes; picking the newest by mtime returned
`NO-GATE` for 38/38. Both are artifacts: a lane worktree inherits all ~840 tracked handoff dirs from
main, and the suites create fixture dirs (`dispatch-nwcm0012`, `dispatch-sgbsig001`) inside it while
running. The authoritative mapping is **sig8 → `${ROOT}/docs/handoff/dispatch-<sig8>` in the main
checkout** (`:210`), and there is no committed lane→sig8 index. **The worker must not infer a lane's
terminal state from files inside its own worktree.**

---

## 3. Behind-main branches, and the split with LANE-SALVAGE-TOOL-01

Measured `git rev-list --count <lane>..main` for the 38 recent lanes: 17, 21, 22, 29, 41, 75, 99,
116, 122, 131, 146×4, 147, 149, 153, 158, 161, 237, 248, 391, 419, 613, 618, 720, 737, 878×6, 959,
961, 1068×2. Only 5 lanes carry a merge commit at all.

| Option | Cost | Risk | Verdict |
|---|---|---|---|
| `git merge <lane>` into main | free | **Reverts main across hundreds of files.** This is the incident `be1f6ce2` was written for. The safety gate now refuses the full-file-deletion shape, but it deliberately scopes to full-file absence only — a lane 1068 behind that *modifies* a file main has since changed still merges cleanly and silently reverts the content. | **Never.** |
| `git rebase origin/main` (today's Path B) | O(commits × conflicts) | On a 1068-behind lane with merge commits, conflicts on every merged hunk. Rewrites the lane's history in place; on a shared tree that is unrecoverable without reflog surgery. | **Never**, except the prior draft's narrow case: zero merge commits AND an explicit founder flag. |
| `git merge origin/main` INSIDE the lane, then `--ff-only` into main | conflicts once, in the lane, recoverable via `merge --abort` | Safe, and it makes the safety gate pass by construction (the lane now contains main's tip). Requires a throwaway worktree because every lane worktree is dirty (§2b). | **Default for lanes ≤ ~150 behind.** |
| Cherry-pick the lane's own non-empty commits onto a fresh branch off current main | O(lane's own commits) — 1 to 10, never 1068 | Conflicts scoped to the lane's own files. Loses the lane's original SHAs (acceptable: nothing references them). | **Default for lanes > ~150 behind — and this is exactly what the salvage tool already does.** |

**Split with `LANE-SALVAGE-TOOL-01`.** That lane already has a working tool on its branch:
`plugins/leadv2/scripts/leadv2-lane-salvage.sh` (433 lines) + `plugins/leadv2/scripts/tests/test-lane-salvage.sh`
(496 lines), commit subject *"lane-salvage tool — carry stale lane commits onto salvage/<lane> from
current main"*. Do not rebuild it. The division is:

- **Salvage owns REBASING THE PAST.** It converts a stale lane into a fresh `salvage/<lane>` branch
  based on current main. Its output is a branch that is 0 behind. It is a bulk, one-shot backlog tool.
- **This lane owns LANDING THE PRESENT.** `leadv2-land.sh` takes **one** branch that is already a
  descendant of current main and lands it: hygiene → safety gate → ff → push → ledger row. It must
  **refuse, with `reason=behind_main n=<N>`, and name `leadv2-lane-salvage.sh` in the refusal text**,
  any branch that is not.
- Contract between them: salvage's output branch is land's input. `leadv2-land.sh` must not import,
  source, or duplicate a single line of `leadv2-lane-salvage.sh`. If salvage has not landed on main
  when this worker starts, the refusal message still names it — a dangling reference to a tool that
  is one merge away is correct; re-implementing it is not.

---

## 4. Make landing observable

The three candidate proof surfaces and their measured state today:

- `~/.claude/cache/dispatch-terminal-ledger/leadv2.jsonl` — **1 row, all time.** Not a proof surface.
- `docs/handoff/dispatch-<sig8>/merge-blocker.flag` — written by Path B only, and Path B has not run
  since 09-01. Zero flags exist for the 38 lanes.
- `docs/leadv2/merge-queue.jsonl` — a mutex log; 24 of 25 rows cannot name their branch.

**Required artifact — one append-only JSONL, written on EVERY land ATTEMPT, success or failure.**
Place it in the control plane via `leadv2-state-path.sh --no-link "land-ledger/<repo-slug>.jsonl"`,
never in `docs/leadv2/` (that directory is un-committable per the header and is symlinked to /tmp
mid-run).

One row per attempt, all fields mandatory, no nulls:

```json
{"ts":"2026-09-04T01:02:03Z","lane":"worktree-FOO-01","lane_tip":"<40hex>",
 "main_before":"<40hex>","main_after":"<40hex|same>","behind":0,"ahead":3,
 "mode":"ff|merge|refused","outcome":"landed|refused|failed",
 "reason":"ok|behind_main|lane_dirty|main_dirty|safety_gate_refused|ff_failed|push_failed",
 "files":12,"pushed":true}
```

- **Proof it LANDED:** `outcome=landed` AND `main_after != main_before` AND
  `git merge-base --is-ancestor <lane_tip> origin/main` exits 0 AND `pushed=true`. All four, checked
  by the script itself after the push, not asserted from a return code.
- **Proof it FAILED:** a row with `outcome=refused|failed` and a named `reason`. **The absence of a
  row is itself a defect** — the runner writes the row from an `EXIT` trap before it can exit for any
  reason, so a crash still produces `outcome=failed reason=<trap>`. A landing path whose failure is
  silent is the same disease as a verdict derived from a measurement that never happened.
- Additionally: on refusal, mirror the reason to `docs/handoff/dispatch-<sig8>/merge-blocker.flag`
  using the existing `write_blocker` shape, so Phase 8's A6 assert keeps working unchanged.

---

## 5. What the worker builds

**`plugins/leadv2/scripts/leadv2-land.sh <lane-branch> [--dry-run]`** — the single landing runner.
Ordered steps, each independently testable:

1. Resolve repo root and default branch (`lv2_default_branch`, from `leadv2-branch-merged.sh`).
2. **Refuse early, with a named reason and a ledger row**, if: the lane is behind main by more than
   `LEADV2_LAND_MAX_BEHIND` (default 0 — see §3, salvage owns the rest); main's checkout is dirty;
   the lane branch does not exist.
3. `leadv2-merge-queue.sh acquire <id>`; release in the EXIT trap. **Check its rc** — both existing
   call sites swallow it.
4. Create a **throwaway worktree on the lane tip** (`git worktree add <tmp> --detach <lane-tip>`).
   Never touch the lane's own worktree. Never `git worktree prune`. Remove the throwaway in the EXIT
   trap by explicit path.
5. Pre-land hygiene inside the throwaway, from ONE list defined at the top of the script:
   `docs/leadv2`, `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*` — `git checkout --` those.
   Derive (never hard-code) any file tracked in the lane but ignored on main and `git rm --cached`
   it — test ignore status with `git add --dry-run`, **never `git check-ignore`, which exits 0 on a
   negation match** and will silently mislabel every file. Refuse with a named reason if anything
   else is dirty.
6. Run `leadv2-merge-safety-gate.sh <root> <lane> <default>`. rc=1 → refuse with
   `reason=safety_gate_refused`; rc≥2 → refuse with `reason=safety_gate_error`.
7. `git merge --ff-only <lane-tip>` in main, then `git push origin main`.
8. Verify all four landing conditions from §4. Write the ledger row. rc=0 only if all four hold.
9. **Deploy is not this script's job.** `deploy-merge.sh`'s conflation of merge and deploy is exactly
   why its rc=1 means two different things. `leadv2-land.sh` ends at the push.

Explicitly out of scope for the implementing worker:
- Any edit to `leadv2-deploy-merge.sh`, `leadv2-dispatch-product-close.sh`,
  `leadv2-merge-safety-gate.sh`, `leadv2-merge-queue.sh`, or `leadv2-lane-salvage.sh`.
- Any change to the review gate, the selfcheck, or the reasons in §2b. Making `blocked` lanes reach
  `pass` is a separate, larger row — this lane builds the runner that a `pass` (or a lead) can call.
- Rebasing, salvaging, or landing any of the 110 backlog lanes. Building the tool ≠ using it.
- Merging anything to `main`. The worker leaves a green branch and a report (§8).

---

## 6. The two gates — no code change needed to either

**Gate 1: `--force` does not defeat `duplicate_task_signature`.** Deliberate and documented:
`leadv2-dispatch-code.sh:7485-7488` — *"R1 FIX (Finding 3): --force NEVER bypasses the
duplicate-task_sig refusal in the automated path… --force is still accepted so callers don't
hard-fail on an unknown arg, but it is a documented no-op for dedup purposes."* The refusal fires at
`:7501` and `:7953`. The signature is `sha256` of the **normalized mission text** (`:2012-2016`), so
a genuinely rewritten mission already yields a new sig; the four measured refusals are the
unchanged-text case, where the previous attempt's ledger row is still pending/confirmed.

**The sanctioned escape already exists and nobody used it:** `leadv2-dispatch-code.sh retry-dead
<sig8>` (`cmd_retry_dead` at `:8534`, dispatched at `:8618`). Its own header names this exact
incident: *"the founder hand-deleted a ledger row by exact sig 4x in one night before this existed."*
It clears only a row proven dead-with-no-evidence and refuses loudly otherwise.

> **Smallest change that unblocks re-dispatch without weakening dedup: none to the code.** The fix is
> a doctrine line — *a fix round is `retry-dead <sig8>` then re-dispatch with `--resume-lane`, never
> `--force`, never a new founder id.* Inventing a new id per round is what fragments a lane's history
> and it is unnecessary. If a measurement shows `retry-dead` itself refusing a row it should clear,
> that is a separate row against a held file — report it, do not patch it here.

**Gate 2: a declared write set loses to an undeclared one.** Confirmed, and it lives in a held file:
`leadv2-active-registry.sh:29-38` — exit 5 `writeset_conflict` (real intersection with an alive
lane), exit 6 `writeset_unknown` (*"an alive incumbent has no writes/write_set"*), and the check
*"fires only when a non-empty `writes`"* is supplied. So an undeclared lane is never checked and
conflicts with nothing, while a declaring lane is refused by every incumbent that stayed silent — the
mechanism penalises the only behaviour that makes it useful. Separately,
`leadv2-dispatch-code.sh:3766-3800` (`_lane_writes_guard`) accepts *an existing lane worktree* as a
substitute for a declaration, which is how the silent incumbents get created in the first place.

> Real defect, **out of scope for this lane** — both files are held. Minimal proposal for whoever
> owns them: make `writeset_unknown` (exit 6) **admit** rather than refuse once the incumbent's row
> has been silent past its own prepass window, logging `writeset_unknown_admitted incumbent=<id>`;
> keep exit 5 (a real intersection) refusing. That inverts the penalty without weakening the only
> check that measures something.

---

## 7. Acceptance rules — non-negotiable

1. **A negative control for EVERY changed function body, not one per lane.** Apply it with
   `plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <file> <sed-or-patch> [task_dir]`
   (usage at `:13`). The mutation goes **inside the function body** — a line-number insert that lands
   at top level makes every suite red for the wrong reason and reads as a pass. The proof is the
   `baseline_rc=0` / `mutated_rc=1` pair, pasted. **A `diff_hash` is not proof.** Minimum bodies to
   control: the behind-main refusal, the hygiene list, the safety-gate rc dispatch, the
   four-condition landing verification, and the EXIT-trap ledger row.
2. **Ten consecutive suite runs, not one.** Paste all ten rc values. A defect in this repo appeared
   twice in thirteen runs and only under machine load; five clean runs prove nothing.
3. **Fixtures assert filesystem post-state, never a return code**, and verify their own setup — a
   fixture that does not first assert its scratch repo is in the state it thinks it is, is a
   tautology. Every fixture runs in a **scratch repo under `$TMPDIR`**, never in the shared tree.
4. **The suite is registered AND the registration is proven with the runner's own selection seam
   after a REAL edit** — `touch` does not work, git does not see it. Make a one-character real edit
   to `leadv2-land.sh`, then paste `tests/run-all.sh --scope changed` selecting
   `test-leadv2-land.sh`. See §8 for how to register without editing the held file.
5. **`git check-ignore` exits 0 on a negation match** — it must never be used as an
   ignored/not-ignored proof anywhere in the script or the suite. Use `git add --dry-run`.
6. Minimum fixture set: (a) a lane exactly at main's tip lands ff and pushes; (b) a lane 1 behind is
   **refused** with `reason=behind_main`, ledger row present, main unmoved; (c) dirty state files in
   the lane are restored and the land proceeds, with the ledger row naming them; (d) a
   tracked-in-lane / ignored-on-main file is dropped before the ff, proven by `git add --dry-run`;
   (e) a non-state dirty file refuses with a named reason; (f) safety-gate rc=1 refuses and writes
   `merge-blocker.flag`; (g) a `kill -9` mid-run still leaves an `outcome=failed` ledger row.

---

## 8. Held files, and the split

`tests/run-all.sh`, `leadv2-dispatch-code.sh` and `leadv2-active-registry.sh` are **held by another
session. Do not edit them.** Registration of the new suite normally needs a `run-all.sh` row.

**Try the stem rule first.** `run-all.sh` maps a changed script to `test-<stem>.sh` automatically;
`EXTRA_SUITE_MAP` (`tests/run-all.sh:129-134`, consumed at `:481`) exists only for non-stem mappings.
Naming the script `leadv2-land.sh` and the suite
`plugins/leadv2/scripts/tests/test-leadv2-land.sh` should be selected by the stem rule with **no edit
to the held file at all**. **Prove it, do not assume it**: real-edit `leadv2-land.sh`, run
`tests/run-all.sh --scope changed`, paste the selection line.

**If and only if the stem rule does not select it:** write the one-line row to
`docs/handoff/LAND-PATH-IS-BROKEN-01/run-all-registration.patch` as a `git apply`-able diff against
`tests/run-all.sh`, state loudly in the report that registration is **NOT DONE** and requires the
holding session to apply it, and paste the `--scope changed` run with the patch applied in a
throwaway worktree as evidence that the row is correct. **Never edit the held file, not even
"temporarily".**

---

## 9. Do NOT

- Never `reset --hard`, `clean`, `stash`, or `push --force` anywhere in this shared tree.
- **Never `git worktree prune`** — it killed two live lanes here once. Remove only the throwaway
  worktree this script created, by explicit path.
- Do not delete or rename any lane worktree or lane branch.
- Do not merge anything to `main`. The worker leaves a green branch and
  `docs/handoff/LAND-PATH-IS-BROKEN-01/worker-report.md`; the other lead merges.
- Do not edit the three held files (§8), nor any of the five scripts listed as out of scope in §5.
- Do not "fix" the review gate, the selfcheck, or the 42 blocked lanes. That is the next row, and it
  is the bigger one.
