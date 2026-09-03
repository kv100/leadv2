LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-lane-state.sh, plugins/leadv2/scripts/leadv2-active-registry.sh, plugins/leadv2/scripts/leadv2-helpers.sh, plugins/leadv2/scripts/leadv2-lanes-snapshot.sh, plugins/leadv2/scripts/tests/test-lane-state-single-writer.sh (to-create), plugins/leadv2/tests/test-lane-state.sh, plugins/leadv2/tests/test-lane-state-wiring.sh, tests/run-all.sh, docs/handoff/D1-SINGLE-WRITER-FOR-LANE-STATE/**

# D1 — single writer for lane state: implementation brief

Measured against `main` at `3a4ec991` (the D3 merge). Every count below is re-derivable with the
command printed beside it. **The plan's D1 row is wrong on both numbers — read §1 before §5.**

---

## 0. The one-paragraph verdict

The single-writer *mechanism* exists and its core guarantees are real (§2). The prior research
brief's conclusion — "mechanism exists, only universal adoption is missing" — is **half right and
dangerously so**. Adoption is missing, yes: 14 of 75 measured `active.yaml` mutation sites go
through it. But the mechanism as written also **cannot be adopted universally in its current
shape**, because three of its own behaviours are the exact defects D1 exists to kill: it tolerates
duplicate rows silently, `lane_deregister` returns 0 when it removed nothing, and its root
resolver falls back to `git rev-parse` in the caller's cwd. Adopting it unchanged would spread
those three defects to 75 call sites instead of 14. **Fix the writer first (M1–M3), then adopt
(M4–M6).** That ordering is the whole design.

---

## 1. The census — measured, not asserted

**Counting method.** A *path* is a call site or inline code block in
`plugins/leadv2/{scripts,hooks}` that **mutates** a lane-state store. Excluded: anything under a
`tests/` directory or matching `test-*`, comment-only lines, `declare -F`/`type` existence probes,
and the function definitions themselves. A *store* is a distinct file or directory whose contents
encode lane state. `.claude/scripts/` is excluded from the count and handled separately in §1.4 —
it is a partly-symlinked, partly-stale mirror, not a source tree.

### 1.1 Paths — 75 to `active.yaml` alone, not 24

| # | family | sites | files | goes through `lib/leadv2-lane-state.sh`? |
|---|---|---|---|---|
| P1 | `lane_register` / `lane_transition` / `lane_deregister` / `lane_adopt_pid` / `lane_reconcile` | **14** | 6 | **yes** — this is the single writer |
| P2 | `leadv2_active_*` — 13 mutating verbs (`register`, `unregister`, `update_phase`, `update_pulse`, `heartbeat`, `mark_finished`, `append_provider_receipt`, `set_writes`, `set_attempt`, `set_worker_pid`, `set_worktree`, `set_log_path`, `consolidate_ephemeral_roots`) | **58** | **21** | **no** — own flock + own atomic rename in `leadv2-active-registry.sh` |
| P3 | inline python that mutates `active.yaml` with neither API | **3** | 2 | **no** — see §1.2 |
| | **total against `active.yaml`** | **75** | **24 distinct files** | 14 / 75 = **19% adoption** |
| P4 | terminal-ledger writers (`dispatch_ledger_write_terminal`, `dispatch_ledger_sweep_write_dead`) | **10** | — | n/a — different store, own lock, write-once. **D3's. Not D1's.** |

Re-derive (bash, not zsh — an unquoted array in zsh does not word-split and silently returns 0):

```bash
SC=(plugins/leadv2/scripts plugins/leadv2/hooks)
strip() { grep -vE "/tests?/|/test-" | grep -vE "^[^:]+:[0-9]+:[[:space:]]*#" \
        | grep -v "declare -F" | grep -v "type leadv2_active"; }
# P1
grep -rnE "\b(lane_register|lane_transition|lane_deregister|lane_adopt_pid|lane_reconcile)\b" "${SC[@]}" | strip | wc -l
# P2 (excludes the definitions in the registry and helpers themselves)
grep -rnE "\bleadv2_active_(register|unregister|update_phase|update_pulse|heartbeat|mark_finished|append_provider_receipt|set_writes|set_attempt|set_worker_pid|set_worktree|set_log_path|consolidate_ephemeral_roots)\b" "${SC[@]}" \
  | strip | grep -vE "leadv2-(active-registry|helpers)\.sh:[0-9]+:leadv2_active" | wc -l
```

**The plan says "24 paths".** The number that is actually 24 is the count of **distinct files**
that mutate `active.yaml` — not the count of paths. The path count is 75. The correction matters:
a per-file migration sized for 24 units is sized ~3× too small, and a worker who "converted all
24" will have converted a third of the call sites and left the rest live.

Top files by P2 site count (the migration's real weight):

```
17  leadv2-fanout.sh                6  leadv2-dispatch-code.sh
 8  leadv2-fanout-lane-launcher.sh  3  leadv2-lane-heartbeat.sh
 6  leadv2-helpers.sh               2  leadv2-provider-canary.sh, leadv2-phase-record.sh
                                    1  × 13 other files
```

### 1.2 The three inline writers (P3) — each is its own implementation

| file:line | what it does | lock | why it exists |
|---|---|---|---|
| `leadv2-dispatch-code.sh:4527–4590` (`_release_registered_lane`) | owner-verified compare-and-delete of one row | takes `active.yaml.lock` itself | R9 H1: needed compare **and** delete inside one flock; the registry API has no such verb |
| `leadv2-lanes-snapshot.sh:1027` | adopt: writes an orphan tmux row into `active.yaml` | `:941–944`, self-described as "a direct, independent flock on the identical lockfile path" | needed the tombstone-before-prune ordering the registry API cannot express |
| `leadv2-lanes-snapshot.sh:1281` | tombstone + prune: removes corroborated-dead rows | same | same |

All three take the *same* lock file as both APIs, so this is **not** a byte-level lost-update
race. It is a **semantics divergence**: five implementations disagree about what a row means.

### 1.3 Stores — 10, and one of them is not on the plan's list at all

| # | store | writers | note |
|---|---|---|---|
| S1 | `docs/leadv2/active.yaml` + `active.yaml.lock` | P1, P2, P3 | the main event |
| S2 | **`docs/leadv2/active.md` + `active.md.lock`** | `leadv2-helpers.sh:1441 / 1471 / 1498 / 1516` | **a shadow store nobody names — §3.3** |
| S3 | `docs/leadv2/tombstones.yaml` | `leadv2-lanes-snapshot.sh:981, 1264` | written *before* the prune, by design (R2-4) |
| S4 | dispatch terminal ledger JSONL (`dispatch_terminal_ledger_file()`) | `leadv2-dispatch-ledger.sh:291, 555` | **D3's store. Do not touch.** |
| S5 | `docs/handoff/dispatch-<sig8>/phases.d/` | `leadv2-phase-record.sh`, `leadv2-dispatch-code.sh` | phase receipts |
| S6 | `docs/leadv2/tasks/<id>/journal.md` | `leadv2-journal.sh` (+8 readers) | append-only, no lock |
| S7 | `docs/leadv2/tasks/<id>/STATE.md` | phase skills, `leadv2-state-atomic-write.sh` | |
| S8 | `docs/LEAD_V2_STATE.md` | `leadv2_active_render_index` (`registry:1109`) | derived view, re-rendered on every unregister |
| S9 | lanes snapshot file (`leadv2-lanes-snapshot.sh:1549`), `lib/leadv2-status-cache.sh` | | derived view |
| S10 | active-cache hook file (`hooks/leadv2-active-cache.sh:89`) | | derived view |

**10 stores, not 9.** The missing one is S2. Of the 10, only S1–S3 are *authoritative* lane state;
S4 is D3's; S5–S7 are per-task records; S8–S10 are derived views D5 will collapse.
**D1's scope is S1, S2, S3 — nothing else.**

### 1.4 Off-tree drift found while counting (pre-flight, not a repo edit)

`.claude/scripts/lib/leadv2-lane-state.sh` is an **untracked real copy**
(`git ls-files --error-unmatch` → "did not match any file(s) known to git") and it is **stale**: it
still hardcodes `if not existing and len(live) >= 2` where canonical carries the `LEADV2_LANE_CAP`
/ 64 default from `CONCURRENCY-UNLIMITED-LANES-01`. `.claude/scripts/` is a *mixed* directory —
`leadv2-dispatch-code.sh` there is a symlink to canonical; `leadv2-fanout.sh` and this file are
real copies. Any loader resolving through `.claude/scripts/lib/` gets a lane cap of 2 and does not
know it.

**Worker pre-flight (not a commit):** `rm` the untracked copy, symlink it to
`plugins/leadv2/scripts/lib/leadv2-lane-state.sh`, then re-run the M1 suite to prove the same file
loads from both paths. Do not `git add` anything under `.claude/scripts/`.

---

## 2. What the single writer already is — read against `lib/leadv2-lane-state.sh` (166 lines)

### 2.1 Real guarantees (verified by reading the body, not its header comment)

| guarantee | line | verdict |
|---|---|---|
| `fcntl.flock(LOCK_EX)` around every mutation | `:69–70` | **real** — and the registry (`:182`, `:328`) and lanes-snapshot (`:941–944`) take the *same* lock path |
| atomic rename (`mkstemp` in the target dir → `os.replace`) | `:152–154` | **real** |
| append-only per-row event trail (`lane_events`) | `:66–67` | **real**; no op ever truncates it |
| one `active.yaml`, resolved via `leadv2-state-path.sh --no-link` | `:18–25` | **real path resolution**, conditional on §2.2 A3 |
| PID-reuse-safe liveness (`os.kill(pid,0)` **and** `pid_start_time` equality) | `:57–65` | **real** — a recycled PID does not read as alive |
| the test seam is an observation source only, not a liveness override | `:46–47`, `:61` | **real** — the comment is accurate; `os.kill` still decides |
| `lane_transition` on a missing row fails loudly (`sys.exit(4)`) | `:110` | **real** |

### 2.2 Aspirational — what the docs imply and the code does not give

| # | claim | reality | line |
|---|---|---|---|
| A1 | "one row per task" | `register` / `transition` / `deregister` all use `next((r for r in rows if ...))` — the **first** match. Two live rows for one `task_id` are silently tolerated, and `deregister` tombstones only the first, leaving the second live forever. | `:82`, `:109`, `:114` |
| A2 | "deregister releases the lane" | `if row: ...` with **no else**. Missing row → falls through → rc 0. Indistinguishable from success. | `:112–116` |
| A3 | "resolves one `active.yaml`" | Falls back to `git rev-parse --show-toplevel` in the caller's cwd when `LEADV2_PROJECT_ROOT` and `PROJECT_ROOT` are both unset. This **is** landmine §3.2, inside the single writer. | `:15` |
| A4 | "every mutation is durable" | `import yaml` failure → `sys.exit(1)` before any work. Every op becomes a silent no-op returning 1 — and **12 of the 14 P1 call sites are `>/dev/null 2>&1 \|\| true`**, so rc 1 is discarded. | `:39–42` |
| A5 | "callers see errors" | rc 3 (cap exceeded) and rc 4 (no row) are swallowed at 12 of 14 sites. Only `leadv2-dispatch-code.sh:7085` reads a return value. | P1 grep |
| A6 | "the event trail is bounded" | `lane_events` grows without cap; nothing prunes it. Not a D1 blocker — note it. | `:67` |
| A7 | `reconcile` recovers orphans | `known` is built from **all** rows including tombstoned ones (`:127`), so a restarted worker in a previously-tombstoned worktree is never recovered. | `:127–130` |

**Refutation of the prior brief, stated plainly.** "The mechanism exists and only universal
adoption is missing" is false *as a plan*. A1, A2 and A3 are the same three defects the census
finds scattered across the 61 non-adopting paths. Adopting the writer as-is centralises them
rather than removing them. The prior brief's *factual* claim (flock + atomic rename + event trail
are real) is **confirmed**; its *implied* conclusion (adoption alone is sufficient) is **refuted**.

### 2.3 There is not one legacy writer — there are two, with incompatible signatures

`leadv2-active-registry.sh:872` and `leadv2-helpers.sh:1441` both define `leadv2_active_register`,
and they target **different files**:

- registry → `_leadv2_yaml_file()` (`:87–95`) → `docs/leadv2/active.yaml`
- helpers → `_leadv2_active_file()` (`:1303–1305`) → **`docs/leadv2/active.md`**

Their signatures differ. The registry's `$1` is `task_id`; the helpers' `$1` is `phase`, and it
reads the task id from `$LEADV2_TASK_ID`, returning 0 with a stderr note when that is unset
(`:1450–1453`). helpers sources the registry at `:1568–1577` — i.e. **after** its own definitions
at `:1441+`, so in the normal load order the registry wins. But any script that sources helpers
*after* the registry silently rebinds all four verbs to the `.md` writer, at which point
`leadv2_active_register "$tid" "$cls" ...` records `phase="$tid"` for a different task, or nothing
at all. This is not hypothetical shadowing — it is a live ordering hazard with no guard, and the
"registry not found" branch at `helpers:1577` warns and **falls back to the `.md` stub** by design.

---

## 3. The three landmines the design is built around

### 3.1 `leadv2-dispatch-code.sh:4555` — duplicate rows make release structurally impossible

```python
rows = [row for row in data["sessions"] if isinstance(row, dict) and row.get("task_id") == task_id]
if len(rows) != 1:
    sys.exit(2)
```

Two rows for one lane → rc 2 → the lane is never released, by anyone, forever. Worse: the rc-2
branch at `:4568` emits `reason=not_owner_row_intact`, which is *also* the legitimate "another
dispatcher owns this row" outcome — **duplicate rows and correct refusal are indistinguishable in
the telemetry.**

**Design consequence (this is the load-bearing one).** D1 does **not** fix this by editing
`dispatch-code.sh`. D1 fixes it by making duplicate rows *impossible to create* and *loud when
found*, upstream in the writer (M1). Once `register` refuses to create a second live row and every
op errors on `len(live_rows) > 1`, `:4555` becomes unreachable-by-duplicate and needs no change.
That is what makes D1 landable while `dispatch-code.sh` is locked (§6).

### 3.2 `leadv2_active_unregister` without `LEADV2_PROJECT_ROOT` — success that removes nothing

Confirmed in the code, in **both** implementations:

- `leadv2-active-registry.sh:965` — `[[ -f "$yaml_file" ]] || return 0`
- `leadv2-helpers.sh:1508` — `[[ -f "$active" ]] || return 0`

and the resolvers behind them take `${LEADV2_PROJECT_ROOT}` unguarded (`registry:91/93`,
`helpers:1304`), while the lane-state writer's own resolver falls back to `git rev-parse` in the
caller's cwd (`lane-state:15`). Unset the variable in a persona-engine cwd and every one of these
returns 0 having touched nothing.

**Design rule, non-negotiable for every verb D1 touches:** *a registry helper asserts post-state,
never a return code.* Concretely — after `deregister`, re-read the row and require `dead_at` to be
set; after `register`, require exactly one live row with the expected `pid` + `pid_start_time`. The
assertion lives **inside** the flock, not in the shell caller: a shell-level re-read is a second
lock acquisition and a TOCTOU window.

### 3.3 The shadow store `active.md` (§2.3)

Not on the plan's list, and it is a store D1 must **eliminate** rather than route. The helpers
verbs have no live consumers worth preserving — `leadv2_active_list` there merely `cat`s the file —
but they do have live callers via `leadv2_lock_acquire` / `leadv2_lock_release` (`helpers:628`,
`:650`). Those must resolve to the registry verbs, which is what the comment at `:621` already
claims and the code does not guarantee.

---

## 4. Ordering against D2 and D3

Read `docs/handoff/D3-TERMINAL-FUNNEL-WITH-DEATH-PROOF/brief.md` §5 before starting. Its claim —
"D1 is free to collapse the paths without touching D3; D3 is a *reader* of liveness and a *caller*
of the one existing terminal writer; it introduces no 25th path" — **holds**, with one correction
and three hard edges.

**Correction to D3 §5's own table**, found while verifying: `_dl_reap_one_lane`
(`leadv2-dispatch-ledger.sh:1358`) calls **only** `dispatch_ledger_write_terminal` — it does
**not** call `lane_deregister` directly. The cap release that D3 §5 attributes to `lane_deregister`
happens elsewhere: the dispatcher's EXIT trap (`dispatch-code.sh:3516`) and the session runners'
traps (`session-runner.sh:200`, `codex-session-runner.sh:104`). So D3 is *more* decoupled from S1
than its own brief claims, not less.

**Paths D1 MAY collapse without touching D3 — all of them.** Every P2 site (58) and both
lanes-snapshot P3 sites. None is read or written by `_dl_reap_one_lane`, `_dl_derive_lane_state`,
or `dispatch_ledger_write_terminal`. The ledger (S4) is outside D1's scope entirely.

**Three changes that WOULD break D3. Do not make them.**

1. **Do not change `lane_deregister` from tombstone to row-removal.** It sets `dead_at` and keeps
   the row (`lane-state:116`). D3's funnel and `_dl_derive_lane_state` need the row readable after
   the terminal write in order to prove death, and `stale_registry_row`
   (`dispatch-ledger:1581`) must stay distinguishable from "never existed". Removing rows makes the
   funnel's post-state unverifiable. **The registry's `unregister` semantics (row removal) converge
   on the writer's tombstone semantics — not the other way round.**
2. **Do not change `lane_alive`'s liveness predicate** (`lane-state:57–65`, pid + `pid_start_time`).
   That is D2's deliverable ("one function answers is-this-lane-alive, by worktree write age"). D1
   changes *who writes*; D2 changes *how liveness is judged*. If D1 touches the predicate the two
   lanes collide on the same lines. D1 may **re-route callers to** `lane_alive`; it may not
   redefine it.
3. **Do not make `lane_deregister` fail-hard on a missing row without an adopter audit.** M2 turns
   A2's silent rc 0 into rc 4. Twelve of the fourteen P1 sites `|| true` and are unaffected — but
   the two that do not (`dispatch-code.sh:7085`, `fork-session.sh:206`) sit in files D1 must not or
   should not edit. M2 therefore ships rc 4 **plus** the in-flock post-state assertion and leaves
   every existing `|| true` in place. Converting those to checked calls is D6's work, not D1's.

**Sequencing verdict.** D1 M1–M3 (writer hardening) may land immediately and in parallel with D2.
M4–M6 (adoption) land after M1–M3 and are independent of D2 and D3. Nothing in D1 waits for D2.

---

## 5. Migration shape — six steps, each independently landable and revertible

Live concurrent lanes are writing S1 right now. Every step below is additive to the writer or a
like-for-like adapter swap; none rewrites `active.yaml`'s schema; none needs a quiescent tree.
**Revert of any step is `git revert <sha>` of that step alone** — no step depends on a later step's
data shape, because a tombstoned row is valid input to every op in every version.

### M1 — duplicate rows become an error in themselves

**Change.** In `lib/leadv2-lane-state.sh`, replace the three `next((r for r in rows if ...))`
selections (`:82`, `:109`, `:114`) with a list comprehension plus an explicit arity check. New exit
code **5 = `duplicate_rows`**, distinct from 2/3/4. `register` refuses to append when a live row
already exists for the `task_id`, and errors rather than picking one when the match count is > 1.

**Why first.** It makes `dispatch-code.sh:4555` unreachable-by-duplicate without editing that file,
and it must precede adoption so adoption cannot manufacture duplicates at scale.

**Proof it landed.** `test-lane-state-single-writer.sh`:
- **T1** — seed an `active.yaml` with two live rows sharing a `task_id`; `lane_deregister` returns
  5 and **both rows are still intact** (a partial tombstone is a failure, not a pass).
- **T2** — `lane_register` twice for the same task never yields a second live row.

### M2 — `lane_deregister` asserts post-state

**Change.** The `deregister` op gains `else: sys.exit(4)` for a missing row and, before releasing
the flock, re-reads its own row and exits **6 (`postcondition_failed`)** if `dead_at` is not set.
Same treatment for `register` (exactly one live row, expected `pid` / `pid_start_time`).

**Proof it landed.**
- **T3** — `lane_deregister UNKNOWN-TASK` → rc 4.
- **T4** — with the `yaml` import forced to fail (a `PYTHONPATH` shim), `lane_deregister` on a real
  row returns non-zero **and** the suite asserts the row is unchanged — A4's silent no-op becomes
  observable.

### M3 — the root resolver fails closed

**Change.** `_lv2_lane_state_root` (`:14–17`) keeps its fallback chain but gains a guard: if the
resolved root does not contain `docs/leadv2/`, **or** if `LEADV2_LANE_STATE_REQUIRE_ROOT=1`
(default on) and neither `LEADV2_PROJECT_ROOT` nor `PROJECT_ROOT` is set, return non-zero rather
than a guessed path. Mirror the guard into `_leadv2_yaml_file` (`registry:87`) — that is where
§3.2's live defect actually fires.

**Proof it landed.**
- **T5** — `env -u LEADV2_PROJECT_ROOT -u PROJECT_ROOT`, cwd set to a scratch git repo with no
  `docs/leadv2/`: `lane_deregister` returns non-zero **and writes nothing anywhere**. Assert on the
  *filesystem* (no `active.yaml` created in the scratch repo), never on rc alone — asserting on rc
  is precisely the landmine.

### M4 — the registry becomes an adapter, verb by verb

**Change.** In `leadv2-active-registry.sh`, reimplement `leadv2_active_register`,
`leadv2_active_unregister` and `leadv2_active_update_phase` as thin adapters over `lane_register` /
`lane_deregister` / `lane_transition`, preserving signature **and stdout contract exactly** —
`register` still **prints** the `session_id`, and `dispatch-code.sh:7056` plus the owner
verification documented at `:4489` depend on that string. `unregister` converges on tombstone
semantics per §4 edge 1; keep `leadv2_active_render_index` firing after it. Leave the ten
field-setter verbs on the registry's own path: they patch fields, not lifecycle.

**Why this ordering.** These three verbs carry the lifecycle. Converting them converts the 58 P2
sites **without editing 21 files** — the adapter *is* the migration.

**Proof it landed.**
- **T6** — a `leadv2_active_register` followed by `leadv2_active_unregister` produces `lane_events`
  entries (`registered`, `deregistered`) on the row. Only the lane-state writer emits those, so the
  assertion cannot be satisfied by the old path.
- Regression watch: `test-lane-registry-outlives-dispatcher.sh` is already registered in
  `run-all.sh` and is currently **red** (D0's census). Record its before/after failure count in the
  report; it may not get redder.

### M5 — delete the `active.md` shadow API

**Change.** Remove the four `leadv2_active_*` definitions in `leadv2-helpers.sh` (`:1441`, `:1471`,
`:1498`, `:1516`) and `_leadv2_active_file` / `_leadv2_active_lockfile` (`:1303–1309`). Move the
registry `source` (`:1568–1577`) above any remaining consumer, and make the "registry not found"
branch at `:1577` a **hard failure** instead of a warning that falls back to the `.md` stub.
`leadv2_lock_acquire` / `leadv2_lock_release` (`:628`, `:650`) keep working because they call the
registry verbs, which M4 already routed.

**Proof it landed.**
- **T7** — source `leadv2-active-registry.sh`, then `leadv2-helpers.sh`; assert
  `declare -f leadv2_active_register` contains no reference to `active.md`.
- **T8** — a full register/unregister cycle creates **no** `docs/leadv2/active.md` anywhere under
  the scratch root.

### M6 — fold lanes-snapshot's adopt / tombstone / prune into the writer

**Change.** Extract the inline block at `leadv2-lanes-snapshot.sh:929–1290` into a named shell
function `_lanes_snapshot_apply_mutations()` — extraction is **required**, because an unnamed
heredoc cannot carry a negative control. Then reimplement adopt as `lane_register`, and tombstone
as `lane_deregister` with the reason carried into `lane_events`. Prune keeps writing
`tombstones.yaml` **first** (tombstone-before-prune is a real correctness fix, R2-4 — do not
regress it); only the `active.yaml` row removal becomes the writer's tombstone.

**Proof it landed.**
- **T9** — after a snapshot run that adopts one orphan and tombstones one dead row, every mutated
  row carries `lane_events`, and `tombstones.yaml` still gains its entry **before** the row is
  tombstoned (assert by injecting a failure between the two writes, not by reading mtimes alone).

### Not a step: `leadv2-dispatch-code.sh`

See §6. M1 is what makes its `:4555` release path correct. The file itself is not edited by D1.

---

## 6. `leadv2-dispatch-code.sh` is held — and D1 does not need it. Loudly.

**The worker must not edit `plugins/leadv2/scripts/leadv2-dispatch-code.sh`.** Another session
holds it.

**D1 does not require editing it.** Its six `leadv2_active_*` call sites (`:671`, `:5583`, `:5713`,
`:7056`, `:7106`, `:7230`) are converted by M4's adapter with **no change at the call site**,
because M4 preserves signature and stdout. Its `_release_registered_lane` block (`:4527–4590`) is
left exactly as-is: M1 removes the condition that makes `:4555` fire spuriously.

**If the worker concludes an edit is genuinely required, STOP and split.** The split is:

- **D1a** = M1, M2, M3, M5, M6 + the M4 adapter, with **no** `dispatch-code.sh` edit. Lands now.
- **D1b** = the `dispatch-code.sh` follow-ups: split rc 2 into `duplicate_rows` vs `not_owner` in
  the `emit decision` at `:4568`, and retire the inline compare-and-delete in favour of a writer
  verb. A separate lane, dispatched only after the lock releases.

Do not queue D1b's work into D1a "since we're in the file anyway".

---

## 7. Negative controls — one per changed function, no exceptions

Count changed **functions**, not lanes. Six steps, **eight changed functions**, therefore **eight
controls**. Each is applied with

```
plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <file> <sed-expr-or-patch> <task_dir>
```

which mutates a scratch copy (`mktemp -d` + fresh `git init` — never a worktree, never the lane),
requires `baseline_rc=0` and `mutated_rc=1`, and writes `mutation-control/<run-id>.txt`, the only
artifact `lib/leadv2-dod-gate.sh` check (b) accepts. Exit 1 = `mutant_survived` (the control did
not bite); exit 2 = `control_not_applied` (`baseline_not_green` | `anchor_count` | `noop_edit` |
`no_merge_base`).

**Every mutation must land inside the function body.** A `sed` anchor that matches at top level
reddens every suite for the wrong reason and reads as a pass — that mistake invalidated a whole
measurement on 2026-08-25. Anchor on a line unique to the body and confirm the artifact's
`anchor_count` is 1.

| # | changed function (file) | mutation to apply | assertion it must break |
|---|---|---|---|
| C1 | `_lv2_lane_state_mutate`, `register` op (`lib/leadv2-lane-state.sh`) | restore `existing = next((r for r in rows if ...), None)` in place of the arity-checked list | **T2** — "a second `lane_register` for one task_id never yields two live rows" |
| C2 | `_lv2_lane_state_mutate`, `deregister` op (same file) | delete the `else: sys.exit(4)` line | **T3** — "`lane_deregister UNKNOWN-TASK` → rc 4" |
| C3 | `_lv2_lane_state_mutate`, in-flock post-state re-read (same file) | replace the `dead_at` post-check with `pass` | **T4** — "a `yaml`-import failure is observable: rc non-zero **and** row unchanged" |
| C4 | `_lv2_lane_state_root` (same file) | restore the bare `printf '%s' "$root"` without the guard | **T5** — "unset roots in a foreign cwd write nothing to the filesystem" |
| C5 | `_leadv2_yaml_file` (`leadv2-active-registry.sh`) | restore the unguarded `printf -- '%s/docs/leadv2/active.yaml'` fallback | **T5b** — same assertion, reached through the registry verb |
| C6 | `leadv2_active_unregister` (`leadv2-active-registry.sh`) | restore the pre-adapter `_leadv2_yaml_py_lock ... unregister` body | **T6** — "the row carries a `deregistered` entry in `lane_events`" |
| C7 | `leadv2_active_register` (`leadv2-active-registry.sh`) | restore the pre-adapter `_leadv2_yaml_py_lock ... register` body | **T6** — "the row carries a `registered` entry in `lane_events`" **and** the printed `session_id` is unchanged |
| C8 | `_lanes_snapshot_apply_mutations` (`leadv2-lanes-snapshot.sh`) | swap the ordering back to prune-then-tombstone | **T9** — "`tombstones.yaml` gains its entry before the row is tombstoned" |

`leadv2_active_update_phase` is covered by C7's suite (same adapter code path). If the worker
changes it in a way C7 does not exercise, it needs its own control. **The rule is per changed
function: change a ninth, write a ninth.**

**A green suite proves the suite runs, not that it bites.** Every control's `mutated_rc=1` artifact
goes in `docs/handoff/D1-SINGLE-WRITER-FOR-LANE-STATE/mutation-control/` and is cited by run-id in
the report. A step with a passing suite and no artifact is **not landed**.

---

## 8. Suite registration — prove it, do not claim it

New suite: `plugins/leadv2/scripts/tests/test-lane-state-single-writer.sh`.

The two existing lane-state suites — `plugins/leadv2/tests/test-lane-state.sh` and
`test-lane-state-wiring.sh` — are **not registered**: `grep -n 'lane-state' tests/run-all.sh`
returns nothing, and they live in `plugins/leadv2/tests/`, not `plugins/leadv2/scripts/tests/`, so
the basename-stem convention (`tests/run-all.sh:527–533`) never selects them either. **The single
writer's own suites have never been run by CI.** Register all three.

Add to `EXTRA_SUITE_MAP` (`tests/run-all.sh:134`), format `<changed-stem>:<suite>`, one per line:

```
leadv2-lane-state.sh:plugins/leadv2/scripts/tests/test-lane-state-single-writer.sh
leadv2-active-registry.sh:plugins/leadv2/scripts/tests/test-lane-state-single-writer.sh
leadv2-helpers.sh:plugins/leadv2/scripts/tests/test-lane-state-single-writer.sh
leadv2-lanes-snapshot.sh:plugins/leadv2/scripts/tests/test-lane-state-single-writer.sh
leadv2-lane-state.sh:plugins/leadv2/tests/test-lane-state.sh
leadv2-lane-state.sh:plugins/leadv2/tests/test-lane-state-wiring.sh
```

**Prove the registration** with

```
LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
```

after a **real** edit to each mapped source file. `touch` does not work — git does not see an mtime
change, so `--scope changed` yields an empty set and the proof is vacuous. Paste the selected-suite
list into the report.

---

## 9. Risks and mitigations

| risk | mitigation |
|---|---|
| M4's adapter changes `unregister` from row-removal to tombstone; readers that count `len(sessions)` suddenly see dead rows | **Audit before M4**, not after: `grep -rn "sessions" plugins/leadv2/scripts \| grep -v test-` for length/count reads. The writer already filters `not r.get('dead_at')` in `count` (`:147`) and `alive` (`:150`); readers that do not must be found first. **This is the single largest blast-radius item in D1.** |
| Live lanes are mid-flight during cutover | Every step is additive or signature-preserving; no step rewrites the schema. A revert of any single step leaves rows written by later-reverted code readable, because a tombstoned row is valid input to every op. |
| M1's new rc 5 reaches a caller that treats non-zero as fatal | 12 of 14 P1 sites are `\|\| true`. The other two (`dispatch-code:7085`, `fork-session:206`) call `register`, which returns 5 only when a duplicate already exists — a lane that is already broken. Failing there is correct. |
| The `.claude/scripts/` stale copy silently re-introduces cap = 2 | §1.4 pre-flight, plus: the M1 suite asserts the loaded file's cap behaviour, so the stale copy cannot pass it. |
| The new suite contends with the host's real shared `active.yaml` — D0 measured exactly this (`test-dispatch-ledger-partial-close.sh` hangs on macOS from lock contention against the live registry, fails cleanly on Linux) | Every case sets `LEADV2_PROJECT_ROOT` to a `mktemp -d` scratch root and never falls back to the repo root. That discipline is also what makes C4 and C5 meaningful. |
| `lane_events` grows unbounded (A6); `reconcile`'s `known` set blocks legitimate recovery (A7) | Out of scope. Record both in the report for D5 / D6. |

---

## 10. Out of scope — the implementing worker ignores all of this

- **The ten field-setter verbs** — `set_writes`, `set_attempt`, `set_worker_pid`, `set_worktree`,
  `set_log_path`, `update_pulse`, `heartbeat`, `mark_finished`, `append_provider_receipt`,
  `check_writes_conflict`. They patch fields, not lifecycle. D6.
- **S4 (the terminal ledger), `_dl_reap_one_lane`, `_dl_derive_lane_state`, and every line of
  `leadv2-dispatch-ledger.sh`.** D3 merged tonight at `3a4ec991`. Not D1's file.
- **The liveness predicate.** D2 owns "is this lane alive".
- **S8 / S9 / S10 — `LEAD_V2_STATE.md`, the lanes snapshot, the active-cache hook.** Derived views.
  D5.
- **S5 / S6 / S7 — `phases.d/`, `journal.md`, per-task `STATE.md`.** Per-task records, not lane
  state.
- **`leadv2-dispatch-code.sh`** (§6), **`leadv2-fanout.sh`** and
  **`leadv2-fanout-lane-launcher.sh`** — 25 P2 sites between the latter two, all converted by M4's
  adapter with zero edits. Do not "clean them up".
- **`lane_events` pruning**, **A7's reconcile bug**, and `.claude/scripts/` as a *tracked* concern.
  Record; do not fix here.
- **`tests/known-red-suites.txt`** — nothing is added to it, and no assertion is weakened anywhere.
  A suite that goes red is a finding, not a registration.
- **Shared-tree git operations** — never `reset --hard`, `clean`, or `stash`; never
  `git worktree prune`. Live lanes are running in this tree.

---

## 11. Corrections to the plan's D1 row, for the record

| the plan says | measured | where |
|---|---|---|
| "24 paths" | **75** mutating paths to `active.yaml` — 14 through the writer, 58 registry, 3 inline. **24 is the count of distinct files**, not paths. | §1.1 |
| "9 stores" | **10.** The missing one is `docs/leadv2/active.md` + its own lock, written by four verbs in `leadv2-helpers.sh`. | §1.3, §2.3 |
| "all 24 paths route through it" — i.e. adoption is the work | Adoption is ~60% of the work. The other 40% is that the writer itself carries the three defects being centralised: duplicate-row tolerance (A1), `deregister` rc 0 on a no-op (A2), and a cwd-guessing root resolver (A3). **Harden, then adopt.** | §0, §2.2 |
| implied: one legacy writer | **Four** non-writer implementations — the registry, the helpers `.md` API, `_release_registered_lane`, and lanes-snapshot's inline block. Five schemas for one file. | §1.2, §2.3 |
