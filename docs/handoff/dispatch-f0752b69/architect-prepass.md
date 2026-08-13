# LANE-PLACEMENT-NOT-ADDRESSABLE-01 — architect prepass

Scope: make a worker's PLACEMENT (which tree it edits) an explicit, validated CLI input to
`leadv2-dispatch-code.sh`, instead of an emergent function of the mission-text hash.

---

## 0. Verified mechanism (read on this main, 2026-08-03)

| Fact | Evidence |
|---|---|
| `WORK_ROOT` is script-scope, seeded from `LEADV2_LANE_WORK_ROOT`, else `PROJECT_ROOT` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:267-269` |
| `LEDGER_REPO_ROOT` is derived FROM `WORK_ROOT` via `git rev-parse --git-common-dir` (LANDED-AT-SPAWN-01) | `:280-281` |
| The only unconditional lane-worktree creation is inside `cmd_resolve`, gated on `WORK_ROOT` being unset/`==PROJECT_ROOT`, keyed `${founder_task_id:-${sig8}}` | `:2126-2140` |
| `record_lane_start_sha` = `git -C "$WORK_ROOT" rev-parse HEAD`, written to `${CACHE_BASE}/dispatch-<sig8>.start-sha`, consumed later by product-close's `_pc_diff_base()` | `:450-470`, `:2144` |
| `WORK_ROOT` reaches workers as `--cwd` (glm `:1599`, kimi `:1638`, codex `:1743`) or `cd` (subsession `:1681`) | as cited |
| `WORK_ROOT` reaches the close gate as `LEADV2_LANE_WORK_ROOT` + `LEADV2_LANE_START_SHA` | `:1517-1518` |
| Lane worktree convention: `$ROOT/.claude/worktrees/<task_id>`, branch `worktree-<task_id>`; `path-of <task_id>` prints it or `""` | `leadv2-lane-worktree.sh` (`lane_dir`, `cmd_path_of`) |
| Liveness probe used by the status surface: `leadv2-lane-liveness.sh --project-root R --lane <tid> [--json] [--no-codex]`, prints a verdict; live == `alive` or `starting:*` | `leadv2-lane-liveness.sh:22-32, 440-495` |
| Arg loop already hard-errors on unknown `--*` before the positional catch-all | `:2076-2078` |

The disease is exactly as stated in the mission: a fix-round mission has different text →
different `sig8` → `ensure` creates a *new, empty* tree. Nothing in the CLI can say "use THIS one".

---

## 1. Design

### 1.1 New CLI surface (both spellings, one code path)

```
--resume-lane <task-sig8-or-founder-id>   resolve the EXISTING lane worktree by lane key
--worktree <abs-path>                     pin the EXISTING tree by explicit absolute path
```

Parsed in `cmd_resolve`'s arg loop (insert before `--task-id`, `:2074`), each guarded with the
existing `[[ $# -ge 2 ]] || { log_err ...; usage; }` idiom. Two new locals:
`placement_lane_ref`, `placement_path`. Both set → `log_err "--resume-lane and --worktree are
mutually exclusive"; usage` (exit 1, the established usage exit code — no ledger row, no spawn,
since the arg loop runs before any state write).

`usage()` (`:1951`) gains the two flags in the synopsis plus a one-line semantics note and the
new exit code.

### 1.2 Resolution + validation — `_resolve_pinned_placement()`

New function, placed next to `record_lane_start_sha`. Called from `cmd_resolve` **immediately
before** the existing `ensure` block (`:2126`) — i.e. after `sig8`/`JOURNAL_TASK` exist (so
refusals are journalable) but **before** `record_lane_start_sha`, before `_dl_note`, before
`dispatch_reserve`, before `architect_prepass` (`:2181`). No ledger row, no terminal row, no
reservation, no spawn can precede it.

Steps (bash 3.2 safe, no `declare -A`, no `<<<`):

1. **Candidate.**
   - `--worktree P`: `P` must be absolute (`[[ "$P" == /* ]]`) → else refuse `not_absolute`.
     candidate = `P`.
   - `--resume-lane REF`: `candidate="$(LEADV2_PROJECT_ROOT="${LEDGER_REPO_ROOT}" bash "${LANE_WORKTREE_BIN}" path-of "${REF}")"`.
     Empty → refuse `no_lane_worktree_for_ref` (message includes the path it looked for:
     `${LEADV2_WORKTREE_DIR:-${LEDGER_REPO_ROOT}/.claude/worktrees}/${REF}`).
     `path-of` is reused verbatim — this is the same resolution `leadv2-lane-worktree.sh`
     and the close gate use, so the two can never drift (mission req 1).
2. **Exists.** `[[ -d "$candidate" ]]` → else refuse `placement_not_found`.
3. **Physical form.** `candidate="$(cd "$candidate" && pwd -P)"` — macOS `/tmp`→`/private/tmp`;
   the same `phys()` reasoning `leadv2-lane-worktree.sh` documents. All later comparisons use
   the physical path.
4. **Same-repo.** Re-run the `LEDGER_REPO_ROOT` derivation (`:280`) *from the candidate*:
   `cand_root="$(cd "$candidate" && cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd -P)"`.
   Refuse `not_a_git_worktree` if empty; refuse `foreign_repo` if
   `cand_root != "$(cd "$LEDGER_REPO_ROOT" && pwd -P)"`. This single check covers *both*
   "is a git worktree" and "of THIS repo", and — crucially — it guarantees the pin cannot move
   `LEDGER_REPO_ROOT`, so **every LANDED-AT-SPAWN-01 keying invariant holds unchanged** (that
   code is not touched; it is proven still-correct by construction). See risk R2.
5. **Not live-claimed.** Lane key = `--resume-lane`'s `REF`, or `basename "$candidate"` for
   `--worktree`. Probe both id spellings the handoff tree uses:
   `dispatch-<key>` and `<key>`:
   ```
   v="$(bash "${LANE_LIVENESS_BIN}" --project-root "${LEDGER_REPO_ROOT}" --lane "<id>" --no-codex 2>/dev/null)"
   ```
   Live iff `v == alive` or `v == starting:*`. Either spelling live → refuse `lane_is_live`.
   `--no-codex` keeps the probe offline/fast (no `codex-task.sh status` shell-out) — the same
   flag the statusline hot path uses. New test seam:
   `LANE_LIVENESS_BIN="${LEADV2_DISPATCH_LANE_LIVENESS_BIN:-${SCRIPT_DIR}/leadv2-lane-liveness.sh}"`
   declared beside `LANE_WORKTREE_BIN` (`:1456`).
   Semantics per mission: this flag **resumes finished/dead lanes; it never hijacks a running one.**
6. **Commit the pin.** `WORK_ROOT="$candidate"; export LEADV2_LANE_WORK_ROOT="$WORK_ROOT";
   PLACEMENT_PINNED=1; WORKTREE_PIN_LINE="WORKTREE PIN: all edits go in ${WORK_ROOT}; do NOT cd
   to the main checkout even if the mission text names it."`
   Journal `emit decision "lane_placement_pinned task=${sig8} mode=<resume-lane|worktree> path=${WORK_ROOT} key=<key>"`.

**Refusal contract (mission req 1/2).** One line to stderr:
`[leadv2-dispatch-code] REFUSE placement: <reason> ref=<ref> path=<candidate>` and
`exit 5` (new code; 1/2/3/4 are taken — usage / duplicate task-sig / arm=opus / spawn failed).
`emit decision "lane_placement_refused ..."` first so the refusal is journaled, then exit.
No ledger row, no terminal row, no reservation, no spawn — guaranteed by call-site ordering.

### 1.3 The `ensure` path stays byte-identical (mission req 4)

The existing block becomes:

```bash
if [[ "${PLACEMENT_PINNED:-0}" != "1" ]]; then
  if [[ -z "${WORK_ROOT}" || ! -d "${WORK_ROOT}" || "${WORK_ROOT}" == "${PROJECT_ROOT}" ]]; then
    ... unchanged body ...
  fi
fi
```

With no flag, `PLACEMENT_PINNED` is `0`, `_resolve_pinned_placement` returns immediately
(both refs empty), and every downstream byte is what it is today. `leadv2-lane-worktree.sh` is
not modified (mission req 6).

### 1.4 Downstream flow (mission req 3) — zero further edits needed

Because the pin is applied to the single `WORK_ROOT` global before any consumer runs, all four
consumers inherit it with **no code change**:

| Consumer | Site | Inherits how |
|---|---|---|
| worker `--cwd` (glm/kimi/codex) | `:1599,:1638,:1743` | reads `${WORK_ROOT}` |
| worker cwd (subsession) | `:1681` | `cd "${WORK_ROOT}"` |
| close gate `LEADV2_LANE_WORK_ROOT` (review-gate diff_root, product-close) | `:1517` | reads `${WORK_ROOT}` |
| `LANE_START_SHA` | `:459` `git -C "${WORK_ROOT}" rev-parse HEAD` | reads `${WORK_ROOT}` |
| EXIT-trap reap `_reap_lane_worktree_if_unused` | `:1097` | reads `${WORK_ROOT}`; only reaps a *clean, unahead* tree with no live worker — a resumed lane with prior commits/dirt is never reaped |

`leadv2-dispatch-product-close.sh` is **not edited** (OFF-LIMITS, mission req 6) — it already
consumes `LEADV2_LANE_WORK_ROOT` + `LEADV2_LANE_START_SHA` as env.

### 1.5 LANE_START_SHA semantics on a pinned resume — decision

**Decision: keep `git -C "$WORK_ROOT" rev-parse HEAD` unchanged; document why in a comment.**

Reasoning (this is the choice the mission asked to be explicit about):

- The close-gate diff is `git diff <start-sha> -- <lane_writes>` inside the pinned tree.
- If the previous round's work is **uncommitted** in the pinned tree, `HEAD` predates it, so
  the diff shows *the carry-over plus the new round*. That is **over-inclusive, never hiding**.
  The mission's stated failure mode ("would hide pre-existing uncommitted work") does not occur
  with HEAD semantics — it would occur with a *later* base, not an earlier one.
- If the previous round **committed** in the lane branch, `HEAD` is that commit and the diff is
  exactly the new round — the mission's stated preference.
- Switching to merge-base-vs-main would re-include every prior committed round, i.e. strictly
  more over-inclusion, for no correctness gain, and would require reasoning about
  `_pc_diff_base` in an off-limits file.

Comment to land at `record_lane_start_sha`:
```
# LANE-PLACEMENT-01: on a --resume-lane/--worktree pin this HEAD is the PINNED tree's HEAD.
# Chosen deliberately: the close-gate diff then covers the new round, plus any uncommitted
# carry-over from the prior round (HEAD predates it). Over-inclusive by construction, and it
# can never HIDE prior uncommitted work -- only a base LATER than HEAD could do that.
```

### 1.6 Prompt pin (mission req 5)

`WORKTREE_PIN_LINE` (empty unless a flag was used) is prepended **once**, at the top of
`_spawn_worker_body` (`:1587`), to that function's local `mission`:

```bash
[[ -z "${WORKTREE_PIN_LINE:-}" ]] || mission="${WORKTREE_PIN_LINE}"$'\n\n'"${mission}"
```

Why there and not in `main`:
- one insertion covers all four arms (glm, kimi, subsession-mfile, codex) — no per-arm drift;
- the `mission` used for `compute_sig`, `classify_product_work`, kimi admission, the router,
  and `architect_prepass` is **untouched**, so the task signature, dedup ledger, and routing
  decisions are byte-identical to today whether or not a flag is used. (Prepending before
  `compute_sig` would change every pinned dispatch's `sig8` and silently defeat the
  anti-double-spend ledger — explicitly rejected.)

`_spawn_worker_body` runs inside a command substitution subshell; reading a script-scope global
is safe (only writes fail to escape — the existing `LAST_ARM_OUTCOME` tempfile comment, `:1493`).

Out of scope: the architect prepass child (`:2181`) is a design-only agent writing to
`docs/handoff/` — it gets no pin line.

---

## 2. Files touched

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | 2 new flags + mutual-exclusion; `LANE_LIVENESS_BIN` seam; `_resolve_pinned_placement()`; `PLACEMENT_PINNED` guard on the `ensure` block; `WORKTREE_PIN_LINE` prepend in `_spawn_worker_body`; `usage()` text; `record_lane_start_sha` comment |
| `plugins/leadv2/scripts/tests/test-lane-placement-pin.sh` | **(to-create)** new suite, 8 assertions |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | one `run_check` registration |

`.claude/scripts/leadv2-dispatch-code.sh` is a **symlink** to the canonical plugin file
(verified `ls -l`) — never edit or list the `.claude/scripts/` path.

---

## 3. Test plan (mission req 7)

New `plugins/leadv2/scripts/tests/test-lane-placement-pin.sh`, modelled 1:1 on
`test-landed-at-spawn.sh` (sandbox `mktemp -d`, `trap cleanup EXIT`, `ok`/`bad` counters,
`LEADV2_STATE_BASE` + `LEADV2_DISPATCH_CACHE_DIR` sandboxed, stub launcher, no network).

**Fixtures**
- `TARGET/` — `git init -b main`, seed commit.
- `TARGET/.claude/worktrees/RESUME-ME-01` — real linked worktree (`git worktree add`), so
  `path-of RESUME-ME-01` resolves and `--git-common-dir` points at `TARGET/.git`.
- `FOREIGN/` + `FOREIGN/.claude/worktrees/OTHER-01` — a linked worktree of a *different* repo.
- `GLM_STUB` — records `--cwd` to `${SANDBOX}/worker-cwd.txt` and the full mission text to
  `${SANDBOX}/worker-mission.txt`, then prints a run-id handle and implements `status` so the
  liveness confirm in `spawn_worker` passes (same shape as the landed-at-spawn stub).
- `LIVENESS_STUB` — wired via `LEADV2_DISPATCH_LANE_LIVENESS_BIN`; prints `dead:exited` by
  default, `alive` when `${SANDBOX}/force-live` exists.
- Journal stubbed via `LEADV2_JOURNAL_BIN`.

**Assertions**

| id | case | assertion |
|---|---|---|
| P-a | `--resume-lane RESUME-ME-01` | rc 0; `worker-cwd.txt` == `TARGET/.claude/worktrees/RESUME-ME-01` (physical compare) |
| P-b | `--worktree <abs path of that tree>` | rc 0; same cwd |
| P-c | `--worktree /nope/nothing` | rc 5; stderr matches `REFUSE placement:`; stub NOT invoked; no reservation line and no terminal line for that sig in the sandbox state dir |
| P-d | `--worktree FOREIGN/.claude/worktrees/OTHER-01` | rc 5; reason `foreign_repo`; no spawn, no ledger row |
| P-e | `--resume-lane RESUME-ME-01` with `force-live` set | rc 5; reason `lane_is_live`; no spawn, no ledger row |
| P-f | `--resume-lane X --worktree Y` together | rc 1 (usage); no spawn, no ledger row |
| P-g | regression, **no flag** | rc 0; `worker-cwd.txt` is a *fresh* tree under `TARGET/.claude/worktrees/`, != the RESUME-ME-01 tree |
| P-h | prompt pin | `worker-mission.txt` first line matches `^WORKTREE PIN: all edits go in ` in P-a/P-b; contains no `WORKTREE PIN` in P-g |

Each spawning case uses a distinct mission text (distinct `sig8`) so the anti-double-spend
ledger never cross-refuses between cases.

**Registration** — append to `run-core-offline.sh` after the landed-at-spawn line:
```
run_check "lane placement pin (--resume-lane/--worktree)" bash "$TEST_DIR/test-lane-placement-pin.sh"
```
Observed `run_check` count on this main **before** the change: **27**. Expected after: **28**.
The builder must re-count on the then-current main before claiming the baseline (it moved twice
on 2026-08-03).

---

## 4. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | A pinned tree that is a *stale* worktree entry (dir exists, `git worktree list` no longer has it) would let a worker edit an orphan dir | Step 4's `--git-common-dir` derivation fails or resolves elsewhere for an orphan → `not_a_git_worktree`/`foreign_repo` refusal. `path-of` additionally cross-checks `git worktree list --porcelain` |
| R2 | Pin silently relocating `LEDGER_REPO_ROOT` → terminals/reservations written into the wrong repo (the exact bug LANDED-AT-SPAWN-01 just fixed) | Validation step 4 *requires* the candidate's common-dir root to equal the already-computed `LEDGER_REPO_ROOT`; a mismatch refuses instead of re-keying. `LEDGER_REPO_ROOT` is never reassigned. LANDED-AT-SPAWN-01 code is untouched |
| R3 | macOS `/tmp`→`/private/tmp` making path equality fail in the fixture suite | Every comparison on `pwd -P` output, both sides; mirrors `leadv2-lane-worktree.sh`'s documented `phys()` |
| R4 | Liveness probe is a shell-out to a script that reads `docs/handoff/**` — slow or noisy in a fixture repo | `--no-codex` (no provider shell-out); probe failure/empty output is treated as **not live** (fail-open to the refusal-free path) — a false "live" would wrongly block a legitimate resume, and the flag's own contract is "resumes finished/dead lanes". Test seam `LEADV2_DISPATCH_LANE_LIVENESS_BIN` |
| R5 | Race: two dispatches pin the *same* tree concurrently, both probe "dead", both spawn | Real but pre-existing in shape and out of scope here: the placement probe is advisory; the existing per-repo dispatch lock + reservation ledger still serialise the *task* dimension. Documented in the code comment; not solved by this task |
| R6 | Prepending the pin line before `compute_sig` would change `sig8` and defeat dedup | Structurally avoided: prepend happens in `_spawn_worker_body`, downstream of every signature/routing consumer (§1.6) |
| R7 | The EXIT-trap reap deleting a resumed lane after a failed spawn | `_reap_lane_worktree_if_unused` already returns early on a dirty tree or `ahead>0`, and calls `cleanup.sh --name` without `--force`. A resumed lane carrying prior work is therefore never reaped. No change; assert nothing — call out in the report |

### Mandatory constraint checklist
1. **Env naming** — new vars `LEADV2_DISPATCH_LANE_LIVENESS_BIN` (matches the existing
   `LEADV2_DISPATCH_*_BIN` launcher-seam family). No `LEAD_V2_*` drift. PASS.
2. **Paths** — all cited paths verified on disk; the one new file is marked `(to-create)`. PASS.
3. **`claude -p`** — this task adds no `claude -p` invocation. N/A.
4. **Concurrent access** — `WORK_ROOT` is per-process; the shared surfaces (reservation ledger,
   terminal ledger, start-sha file) keep their existing locking. New race surface is R5, scoped out.
5. **Config contradiction** — `LEADV2_LANE_WORK_ROOT` keeps its exact current meaning ("the tree
   the lane's code edits land in"); the flags become a *second, explicit* way to set it,
   ranking above `ensure` and below nothing. No semantic contradiction. PASS.

---

## 5. Non-goals (implementer: ignore)

- No change to `leadv2-lane-worktree.sh` `ensure`/`path-of` semantics.
- No ledger/terminal/reservation changes; LANDED-AT-SPAWN-01 code untouched.
- `leadv2-dispatch-product-close.sh` is OFF-LIMITS — not read for edit, not written.
- No fanout / supervisor / launcher changes (`leadv2-fanout*.sh`, `glm-coder.sh`, `kimi-coder.sh`,
  `codex-task.sh`, `claude-subsession.sh`).
- No auto-creation, auto-repair, or auto-cleanup of a pinned tree — the flags *pin*, never *make*.
- No hijack path: there is deliberately no `--force` override of the live-lane refusal.
- No pin line for the architect prepass child.
- No commit (mission: do NOT commit).

---

## acceptance:

```yaml
acceptance:
  authored_at: 2026-08-03T00:00:00Z
  items:
    - surface: file_artifact
      observable: >-
        After a dispatch run with --resume-lane <existing lane id>, the file the stub
        launcher wrote its working directory into names the pre-existing lane worktree
        directory (.claude/worktrees/<lane id>) -- not a newly created directory whose
        name is this round's mission hash.
    - surface: log_line
      observable: >-
        A dispatch pointed at a directory that does not exist, at a worktree belonging to
        a different repository, or at a lane whose worker is still live, prints a single
        stderr line beginning "[leadv2-dispatch-code] REFUSE placement:" naming the reason
        and the path, and no worker starts; the ledger files for that repo show no new
        reservation row and no new terminal row for that dispatch.
    - surface: file_artifact
      observable: >-
        The mission text handed to the worker begins with the line
        "WORKTREE PIN: all edits go in <path>; do NOT cd to the main checkout even if the
        mission text names it." when a placement flag was used, and contains no such line
        when no placement flag was used.
    - surface: log_line
      observable: >-
        The core offline suite run prints "failed=0 missing=0" with a suites-passed count
        exactly one higher than the same run on the unmodified main.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-lane-placement-pin.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
