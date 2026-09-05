# DISPATCH-PIN-CLUSTER-01 — CONCERN pass (pre-code). How the obvious fix breaks.

Paths relative to `/Users/kostiantyn.vlasenko/Projects/leadv2`. Dispatcher = `plugins/leadv2/scripts/leadv2-dispatch-code.sh`.

## 1. D1 — legitimate writes OUTSIDE the lane root (a prefix fence kills all of these)

**Critical.** `dispatch-code.sh:406-414` states the design outright: "PROJECT_ROOT stays the control-plane root (journal, docs/handoff, active.yaml, cache, ledger) everywhere below; only worker `--cwd` and the review-gate's `diff_root` use WORK_ROOT." Real exceptions:

1. **git's own object store.** `.claude/worktrees/05d28614/.git` is a FILE containing `gitdir: /Users/.../leadv2/.git/worktrees/05d28614` (read live). Every lane `git add`/`commit` writes to `<main>/.git/objects` + `.git/worktrees/<n>/{HEAD,index,logs}` — outside the lane. A prefix fence blocks the very commit D2 demands.
2. `${PROJECT_ROOT}/docs/handoff/dispatch-<sig8>/` — developer.stream.jsonl (`:2761`, `:4828`), architect-prepass.md (`:4236`), **lane-mission.md (`:7007`)**, admission-receipt.yaml (`lib/leadv2-admission-class.sh:110`), phases.d/*.yaml.
3. `${PROJECT_ROOT}/docs/leadv2/` — journal (`leadv2-journal.sh:23`), `active.yaml` registry (`:6127-6157`), `.bus-offsets/` (`:592`).
4. `${HOME}/.claude/cache/` — dispatch-ledger (`:567`), code-review-ledger (`:572`), dispatch-fence/denies.jsonl (`:575`), dispatch-close-owner/<sig8>.pid (`:697`).
5. `${HOME}/.claude/state/leadv2/<id>.touched-files` — turncap manifest.
6. Question store: `leadv2-ask.sh:181` `QDIR=$(leadv2-state-path.sh questions)`, written from `:6254-6265`.
7. `docs/tasks.yaml` unclaim (`:294`).

The fence must be an **allowlist of these seams**, and must separate DISPATCHER writes (all legitimate, all outside) from WORKER edits (must be inside). Note the dispatcher **cannot** enforce this: the worker is a separate process given `--cwd`. Enforcement belongs at the worker's tool layer — and `FENCE_LOG` (`:575`) is documented as "the fence hook itself, not this script, is the consumer", i.e. **not wired here**.

**Second-order:** `WORK_ROOT` fails OPEN to `PROJECT_ROOT` (`:412-413`) when `LEADV2_LANE_WORK_ROOT` is unset or the dir vanished. Under a fence, fail-open makes lane root == main checkout and the guard silently permits the exact 2026-08-29 failure.

## 2. D2 — auto-commit sweeps wrong; failing the round loops

**High.** Two existing autocommitters, both already broken as the brief describes:

- `leadv2-turncap-checkpoint-commit.sh:54` — `[[ -d "$PROJECT_ROOT/.git" ]] || exit 0`. In a lane worktree `.git` is a FILE (proven above), so **this checkpointer is a silent no-op in every lane worktree.** Any fix reusing it inherits a dead path.
- `pc_stop_gate_autocommit` (`leadv2-dispatch-product-close.sh:1878-1975`) handles `-d || -f` correctly but stages **only paths inside `_PC_SCOPE_WRITES_CSV`** (`:1904,1919,1959`). That IS the 3-of-5 bug: the H1 guard was not in the declared write set, so it was excluded *by design*, not by accident.

So "commits it itself, atomically and completely" is self-contradictory with the writeset gate: committing everything violates `REQUIRE_LANE_WRITES` (`:596-601`) → `unscopable_diff` park; committing only declared writes is incomplete by construction. The fix must pick one and say which — not claim both.

**What a blind `git add -A` sweeps:** untracked scratch/editor swap in the lane, any `.env` the lane copied, and — because **1892 files under `docs/handoff/*/` are TRACKED despite `.gitignore:40 docs/handoff/*/*`** — every stream jsonl, prepass, review artifact and phases.d yaml the control plane wrote mid-round. Other lanes' files are safe inside a real worktree but NOT on the fail-open shared-tree path (§1), which is exactly the observed shape.

**If it FAILS the round instead:** `_dl_note <sig8> failed` → the close gate's silent-arm probe calls `advance-arm` (`leadv2-dispatch-product-close.sh:1695`), re-spawning the NEXT chain arm on the SAME `lane-mission.md` (`:7002-7009`). Every arm redoes the work — the freepool 9.3M-token round repeated N times. And the reservation frees only when `_dispatch_evidence_exists` (`:2720`) or `_dispatch_checkpointed_cutoff` (`:2836`) agrees; a failed round that still left a handoff artifact returns rc0 "evidence", so the row stays confirmed for `CONFIRMED_TTL=7200` (`:585`) and the same sig8 is refused as busy for 2h. Loop and deadlock are both new failure modes.

## 3. D3 — the plan is gitignored; copy and commit each break something

**High.** `.gitignore:40` = `docs/handoff/*/*`, so `docs/handoff/<task>/context.yaml` is IGNORED.

- **Commit** needs `git add -f`. It then rides the ff-only land (`leadv2-lane-worktree.sh:325-326`) into main permanently, and lands OUTSIDE `LANE_WRITES` → `pc_scope_diff` reports `unscopable_diff` and product-close PARKS the lane (`:596-601`). Committing the plan can BLOCK the landing it was meant to unblock.
- **Copy** (untracked) is ff-only-safe but is swept by `leadv2-worktree-cleanup.sh` on reap and leaves no proof of which plan the worker read.
- **Resume / round 2:** the lane already holds round-1's context.yaml. Blind overwrite destroys `decisions:` the worker appended (append-only per protocol §1a); blind skip pins the lane to a stale plan. This needs an explicit digest compare + loud journal line — never `cp -n` or `cp -f`.
- **Fork hazard:** the admission receipt lives under `<root>/docs/handoff/dispatch-<sig8>/`, read with `PROJECT_ROOT` (`:3496`) but written by `leadv2-backlog-pump.sh:721` with `CANONICAL_ROOT`. Materialising `docs/handoff/` inside the lane forks the receipt — which is D4's only carrier.

## 4. D4 — where task_class comes from; the carrier exists and is discarded

**High.** Chain today: `--task-class` (`:5910`, sets `task_class_flagged=1`) → `_admission_classify` (`:6082`) → `leadv2_admission_class` over `leadv2-task-judge.sh`'s estimate of the MISSION TEXT (`:3515-3524`) → `ADMISSION_CLASS` **overwrites** `task_class` at `:6083`. The router separately reads `DC_TASK_CLASS` (`:2056`, exported `:6455`), and `resolve_v2_dispatch` re-derives its own from a SECOND judge call (`:2556`).

**A carrier record exists and the dispatcher throws it away.** At `:5977-5983`, `leadv2_admission_find_receipt_for_task` returns `sig8 class route source work_kind digest task_id` into `intake_cls/intake_route/intake_src/intake_wk` — and **only `sig` and `sig8` are assigned.** The class survives only indirectly (rewriting sig8 makes `_admission_classify` hit the digest-match early return at `:3499-3507`), and only when `founder_task_id` is non-empty. **A resume mission dispatched without `--task-id` re-hashes the short mission → new sig8 → no receipt → full re-classification → Light.** That is the D4 mechanism: a lookup bug on the founder-task path.

**Where a new field IS needed — say it plainly.** `leadv2_admission_find_receipt_for_task` requires **exactly one** row (`if len(rows) != 1: sys.exit(1)`, `lib/leadv2-admission-class.sh:161`) and returns empty otherwise; two receipts sharing a task_id (pump under `CANONICAL_ROOT`, dispatcher under `PROJECT_ROOT`) make it fail closed into re-derivation. So the receipt is not *reliable*. And `advance-arm` has a third source: it `sed`-scrapes `"task_class":"…"` from the confirmed dispatch-ledger row (`:7345`) and **defaults to `Standard`** when absent (`:7348-7351`, `phase_class_defaulted`) — itself a downgrade for Heavy. Either the ledger row's `task_class`, written at reserve time, becomes the single authoritative carrier read by all three sites, or a new lane-record field is added. Do not add a fourth derivation.

Also verify before claiming `--task-class` is "HONOURED": `:6083` unconditionally overwrites `task_class` with `ADMISSION_CLASS`, so the explicit flag may already be inert.

## 5. Where the four fixes CONFLICT

- **D1 × D2 (Critical).** `_dispatch_evidence_exists` (`:2720`, comment `:2888`) counts files under `${PROJECT_ROOT}/docs/handoff/dispatch-<sig8>/` as evidence. Fence writes to the lane root and those artifacts stop landing where the check looks → every round reads evidence-free → D2's "no evidence ⇒ FAILED" fails 100% of rounds. Agree on ONE evidence root before either lands.
- **D1 × D2 (git).** The fence must whitelist `<main>/.git/**` or D2's own commit is denied.
- **D2 × D3 (High).** If D3 copies untracked, a widened D2 commits the plan; if D3 force-commits, D2's declared-writes scope excludes it and the "complete" commit is incomplete again.
- **D3 × writeset gate (High).** The plan path must join `LANE_WRITES` or product-close parks the lane. Turning BLOCKED into PARKED is not progress.
- **D3 × D4 (Medium).** Both key off `docs/handoff/dispatch-<sig8>/`; moving it into the lane forks the receipt.
- **D2 × D4 (Medium).** D2 failing rounds routes traffic into `advance-arm`, the site with the WEAKEST class resolution (`:7345-7351`). Fix D4's advance-arm branch BEFORE D2 lands.

## 6. Test coverage demanded (each absent = Critical)

Existing coverage is `plugins/leadv2/scripts/tests/test-admission-class.sh` (receipt store only). Required negative controls:

1. **D1:** mutate the `WORK_ROOT="$PROJECT_ROOT"` fail-open (`:412-413`) to unconditional → suite red. Plus a test proving the fence still permits `git commit` inside a real linked worktree.
2. **D2:** lane with 5 dirty files, 3 declared — assert round outcome and committed file count agree, and `advance-arm` fires at most once. Mutate `_sg_paths` scoping (`product-close:1919`).
3. **D3:** lane branched from origin/main with `docs/handoff/*/*` ignored — assert the plan resolves inside the lane AND `git merge --ff-only` still succeeds. Round-2 differing-context.yaml case asserted explicitly.
4. **D4:** dispatch the same founder task twice, second time with a 40-line mission and no `--task-id`; assert the journal `task_class=` line is identical. Mutate `:5981-5982` to drop the sig8 rewrite → red.
5. `run-all.sh` must SELECT them: add the `EXTRA_SUITE_MAP` row, prove with `--scope changed`.

## 7. Pre-finalize contradiction scan

- `WORK_ROOT` vs `PROJECT_ROOT` as "lane root": `:412-413` makes them EQUAL on fail-open. Any D1/D2 fix must name which it fences on. **FINDING.**
- `.gitignore:40 docs/handoff/*/*` vs 1892 tracked files matching it — mixed tracked/ignored state, so "the plan is untracked" holds for new task dirs and is false for pre-existing ones. **FINDING.**
- `leadv2-turncap-checkpoint-commit.sh:54` `-d .git` vs linked worktrees (`.git` is a file) — the checkpointer never runs in a lane. **FINDING.**
- Receipt root: `PROJECT_ROOT` (`:3496`) vs `CANONICAL_ROOT` (`leadv2-backlog-pump.sh:692,721`). **FINDING.**
- Env-var names cross-checked and consistent: `LEADV2_LANE_WORK_ROOT`, `LEADV2_DISPATCH_CACHE_DIR`, `LEADV2_TURNCAP_CHECKPOINT`, `LEADV2_REQUIRE_LANE_WRITES`, `LEADV2_DISPATCH_CHECKPOINT_CUTOFF`.
- All cited paths verified to exist; `.claude/worktrees/05d28614/.git` read live.
- No `mypy`/`tsc`: this write set is pure bash — no Python or TypeScript changed.

## Verdict

**BLOCK** — do not write code against the brief as stated. D1 as written ("refuse any write outside lane root") is unimplementable without breaking git and the whole control plane, and cannot be enforced from inside the dispatcher at all. D2 as written is self-contradictory with the writeset gate and opens a retry loop plus a 2h reservation deadlock. D3 as written can convert BLOCKED into PARKED. D4's premise is only half true: the receipt carrier exists and is discarded at `:5981-5983`, while `advance-arm` genuinely has none. Re-scope the brief on those four points before dispatching a build lane.

DELIVERABLE_COMPLETE
