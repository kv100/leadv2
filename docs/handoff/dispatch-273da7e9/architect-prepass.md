# LANE-STATE-LEAK-01 — architect prepass (mechanism-closed design)

## 0. Where the mission's framing and the code disagree

The mission is right about the mechanism and right about the fix shape. Three things it says are
narrower than what the tree actually contains. Designing to the mission's list and not to these
would ship a fix that is complete against the findings and incomplete against the mechanism.

**(a) It is eight helpers in `leadv2-dispatch-code.sh`, not three.** Line `:878` is
`_leadv2_codex_credits_stamp_path` → `$PROJECT_ROOT/docs/leadv2/.codex-credits-empty.stamp`,
sitting between `:877` and `:879` in the same four-line helper block, with exactly the same
defect and exactly the same per-repo (never per-lane) semantics. Its consumer is
`:1159`. A codex-credit-exhaustion stamp that is per-worktree means the watchdog re-announces
"codex credits empty" once per worktree instead of once. Leaving it is not a smaller blast
radius, it is the same bug with one fewer line fixed, and it will be re-reported.

**(b) `founder-status.md` has a second, independent reader that the mission's own acceptance
grep cannot see.** `plugins/leadv2/hooks/leadv2-single-lead-beat.sh:132` constructs
`FOUNDER_STATUS_PATH="${LEADV2_FOUNDER_STATUS_PATH:-${PROJECT_ROOT}/docs/leadv2/founder-status.md}"`
— byte-for-byte the same raw construction as `leadv2-broad-status.sh:36`. That hook is the
thing that hashes the body (`:145`) and emits the `BROAD_STATUS_READY` ready-line the founder's
`tail -F | grep URGENT` watcher fires on. Done-criterion 1 greps `plugins/leadv2/scripts/`
only, so the hook passes that grep while still reading the wrong file. If the writer moves to
the control plane and this reader does not, the outcome is: **in any worktree where the
resolver has not yet run, the founder's pulse silently stops — no ready-line, no relay, and
nothing in any log says why.** The hook must be routed in this lane.

**(c) `leadv2-broad-status.sh` has six raw paths, not four**, and the two the mission omits are
omitted for a good reason that should be written down rather than left implicit:
- `:34 SNAPSHOT_PATH` → `status-snapshot.json` is **written by a different script**
  (`leadv2-status-collector.sh:43 OUT_PATH`, also read by `leadv2-status-render.sh:37`). Moving
  it in the reader only would give the founder a permanently empty board. It is a three-script
  atomic change and belongs in its own lane. **Out of scope here — recorded as a follow-up.**
- `:35 PREV_PATH` → `.broad-status-prev.json` is the delta baseline. It is already gitignored,
  so it is not part of the visible-noise symptom, and it is read back by
  `test-broad-status-renderer-truth.sh:392` through the raw repo path. Moving it is correct
  eventually but it is coupled to the snapshot decision above. **Out of scope here.**

Everything below designs to (a) and (b) as in-scope, and states (c) as a named non-goal.

---

## 1. CALLERS / CALLEES

### 1.1 `leadv2-state-path.sh` — the function being changed

Callees it invokes: `git -C "$LINK_ROOT" rev-parse --path-format=absolute --git-common-dir`
(`:81`), `git -C "$MAIN_REPO_ROOT" remote` (`:129`, `:186`), `python3` orphan-absorb (`:207`),
`python3` migration+symlink (`:236`).

Callers (every one of these passes through the migration loop being modified, so every one is a
blast-radius entry):

| Caller | file:line | Mode | Consequence if the loop changes shape |
|---|---|---|---|
| `leadv2-broad-status.sh` | `:33` (`supervise-loop.log`) | linking | already routed; new names now also get migrated on this call |
| `leadv2-resume.sh` | `:27` reads `active.yaml` raw — **pre-existing contract violation**, out of scope, noted | — | unchanged by this lane |
| `leadv2-lane-liveness.sh` | `:41`,`:42` raw `active.yaml`/`tombstones.yaml` — **pre-existing violation**, out of scope, noted | — | unchanged |
| test harnesses | `--no-link` probes | non-linking | must stay side-effect-free after the change |

The resolver is called on essentially every dispatch, beat and hook fire, from ~30 worktrees.
Any new work added inside the migration loop is paid on all of them.

### 1.2 `leadv2-dispatch-code.sh` helpers

| Helper | def | Callers | Callee after change |
|---|---|---|---|
| `_leadv2_glm_deferred_path` | `:876` | `:890` (`_glm_park_deferred` write), `:994` (ladder read) | resolver `glm-deferred.jsonl` |
| `_leadv2_arm_exceptions_path` | `:877` | `:1202` (loud-sonnet-exception dedupe) | resolver `.arm-exceptions-<day>` |
| `_leadv2_codex_credits_stamp_path` | `:878` **(mission-omitted, in scope — §0a)** | `:1159` (credit watchdog) | resolver `.codex-credits-empty.stamp` |
| `_leadv2_glm_deferred_mission_path` | `:879` | `:894` (park-time mission copy) | resolver `glm-deferred.d/<sig8>.md` |

**Test-side caller that will silently keep testing the old shape:**
`plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh:390` does not call the helper — it
**re-defines** it by emitting a stub function body containing the literal
`"%s/docs/leadv2/.arm-exceptions-%s" "${PROJECT_ROOT}"`. After this change that stub still
compiles and still passes, while asserting nothing about the new resolution. A green
`test-glm-deferred-ladder.sh` after the fix is therefore **not evidence**. This stub must be
rewritten in the same lane or the suite is a lying-green. Treat as CRITICAL.

### 1.3 `leadv2-broad-status.sh` variables

`:36 FOUNDER_STATUS_PATH`, `:44 FOUNDER_STATUS_FULL_PATH`, `:61 EMPTY_SINCE_PATH`,
`:62 FOUNDER_STATUS_EPOCH_PATH`. Writers are inside this file (`_stamp_epoch` at `:65-70` and
the render tail). Readers outside this file:

| Reader | file:line | Path it uses |
|---|---|---|
| `hooks/leadv2-single-lead-beat.sh` | `:132`, `:144-146`, `:154`, `:157` | raw `${PROJECT_ROOT}/docs/leadv2/founder-status.md` — **independent copy, §0b** |
| `test-pulse-empty-board.sh` | `:109` | raw `$repo/docs/leadv2/.board-empty-since` |
| `test-pulse-empty-board.sh` | `:467`, `:518` | raw `$repo/docs/leadv2/.founder-status-epoch` |
| the founder / lead relay | the `docs/leadv2/founder-status-full.md` string inside the emitted message text | must stay openable → symlink required, not merely a resolver call |

The three test readers keep working **only because** the resolver plants a symlink at
`docs/leadv2/<name>` in the sandbox repo. That makes the symlink a load-bearing part of the
contract for these five names, not a convenience. Say so in the header comment.

---

## 2. STATES AND RETURN CODES

### 2.1 `leadv2-state-path.sh` exit codes and what each caller does with them

| rc | State that produces it | Where | Caller behaviour today | User-visible consequence |
|---|---|---|---|---|
| 0 | resolved (git or no-git fallback) | `:104`,`:109`,`:307`,`:313` | uses the path | correct |
| 3 | `LINK_ROOT == "/"`, no git repo | `:96` | see below | — |
| 3 | `mkdir -p "$STATE_ROOT"` not writable | `:100` | see below | — |
| 1 | B1 safety net: `LEADV2_STATE_ROOT` set but `LINK_ROOT` is a real checkout | `:189` | see below | — |
| 1 (implicit) | `set -euo pipefail` inside the script on any unguarded failure | — | see below | — |

**What every non-zero rc does at each new call site — this is the part that must be designed,
not inherited:**

- `leadv2-broad-status.sh` runs under `set -uo pipefail` — **no `-e`**. A failed
  `VAR="$(state-path.sh founder-status.md)"` therefore does not abort; it assigns the **empty
  string**. Every later `printf ... > "$FOUNDER_STATUS_PATH"` then writes to `""`, fails, and
  because the script is `-e`-free the beat completes "successfully". Terminal outcome in plain
  words: **the founder's 30-minute status silently stops appearing, forever, and no line
  anywhere says the path failed to resolve.** This is strictly worse than today's bug.
  → **Required:** after each of the four resolutions, `[[ -n "$VAR" ]] || { log + fall back to
  `$PROJECT_ROOT/docs/leadv2/<name>` + emit one stderr line naming the failure }`. Degrade to
  the old behaviour loudly; never to an empty path.

- `leadv2-dispatch-code.sh` helpers are contractually wrapped `|| true` by their callers (R8,
  documented at `:864-869`: "none may ever abort cmd_resolve"). An empty resolve makes
  `mkdir -p "$(dirname "")"` → `mkdir -p .` → the ladder is written into **the process's cwd**,
  i.e. a stray `glm-deferred.jsonl` in whatever directory the dispatcher happened to run from,
  and the real ladder appears empty. Terminal outcome: **a quota-refused GLM task is parked into
  a file nobody reads, so `--retry-all` never re-dispatches it and that task is simply lost.**
  → **Required:** same non-empty guard with fall-back to the current `$PROJECT_ROOT` string.
  The old path is the correct degraded value: it is what ships today.

- `hooks/leadv2-single-lead-beat.sh` — a hook that exits non-zero can block the turn. Resolve
  with `|| true` and the same non-empty fallback. Never let the resolver's rc become the hook's.

### 2.2 Migration-class states (the new logic) and their outcomes

For each managed name, on each invocation, exactly one of:

| State | Condition | Action | Outcome |
|---|---|---|---|
| S1 already-linked, correct | `islink(local) and readlink==target` | none | steady state |
| S2 already-linked, stale target | `islink(local) and readlink!=target` | relink | self-heals a moved state root |
| S3 first migration | real `local`, no `target` | move | **content preserved** |
| S4 collision, mergeable file | real `local`, `target` exists, name in MERGE | line-union append into target, then delete local | both worktrees' ladder entries survive |
| S5 collision, mergeable dir | real dir `local`, `target` dir exists, name in MERGE | per-entry move-if-absent, then rmdir local | `glm-deferred.d/` entries from two worktrees both survive |
| S6 collision, regenerable render | real `local`, `target` exists, name in RENDER | **delete local** (no backup) | stale render discarded; next beat rewrites |
| S7 collision, opaque | real `local`, `target` exists, name in STANDARD | `.pre-controlplane-backup` (existing behaviour) | unchanged |
| S8 absent | neither exists | create target (dir) + symlink | steady state |
| S9 glob class | real `docs/leadv2/.arm-exceptions-*` (+ `.lock` siblings) | move-if-absent into target, **no symlink** | today's exception dedupe survives the upgrade |

**Why S6 is a distinct class and not just S7.** S7 leaves a `<name>.pre-controlplane-backup`
file behind. `.gitignore` currently has `docs/leadv2/founder-status*.md`, which does **not**
match `founder-status.md.pre-controlplane-backup`. Applying S7 to the render set would create
**two new permanently-untracked files in each of ~30 worktrees on the very first run** — the
exact symptom this task exists to remove, reintroduced by the fix's own migration step. There
is nothing in a 30-minute-old status render worth preserving; delete it.
(Belt and braces: also add `docs/leadv2/*.pre-controlplane-backup` to `.gitignore` — the two
existing ones, `active.yaml.pre-controlplane-backup` and `open-threads.md.pre-controlplane-backup`,
are *tracked* today, which is its own small oddity but out of scope.)

### 2.3 Concurrency state — the migration loop has no lock

S4 and S5 are read-modify-write across processes. Two worktrees migrating `glm-deferred.jsonl`
concurrently can both read the target, both append, and one loses its lines — a silently
truncated deferral ladder, which is precisely the content the mission says must not be lost.
S3 is also racy today (both `shutil.move`, second raises, `continue` skips the symlink) but is
self-healing on the next invocation; S4/S5 are not.

→ **Required:** wrap the migration python block in `flock` on
`"$STATE_ROOT/.state-path-migrate.lock"`. **fd choice matters**: `leadv2-dispatch-code.sh`
reserves **fd 9** (dispatch lock, closed before a detached spawn) and **fd 8** (GLM-ladder
sidecar lock) and the resolver is invoked from inside those contexts. `grep -n '7[<>]'
plugins/leadv2/scripts/*.sh` returns nothing, so **use fd 7**, and close it (`7>&-`) before
returning. Non-blocking with a short timeout (`flock -w 5`); on timeout, **skip migration for
this invocation and still print the resolved path** — the resolver must never become a place a
dispatch can hang.

---

## 3. CONFIGURATION BOUNDARIES

For every input the changed mechanism reads.

### 3.1 `PROJECT_ROOT` / `LEADV2_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR`

| Case | Behaviour required |
|---|---|
| absent | `LINK_ROOT` falls back to cwd toplevel (`:75`). Existing. Unchanged. |
| empty string | `${PROJECT_ROOT:-...}` treats empty as absent — correct today; keep `:-` not `-`. |
| `/` | `:94` aborts rc 3 with a diagnostic. Existing, correct. |
| points at a real checkout while `LEADV2_STATE_ROOT` is set | B1 net `:185` aborts rc 1. Existing. **New call sites must not turn this abort into a silent empty path** — see §2.1. |
| points at a non-git dir | degrades to `<root>/docs/leadv2` (`:88`) — i.e. today's behaviour. Acceptable and correct for a sandbox. |

### 3.2 `LEADV2_STATE_ROOT` / `LEADV2_STATE_BASE`

| Case | Behaviour |
|---|---|
| absent (production) | git-common-dir resolution. Required path. |
| set + scratch repo | sandbox; ephemeral redirect logic at `:114-141` does **not** apply when `LEADV2_STATE_ROOT` is set (it short-circuits at `:78`). Fine. |
| set + real repo | rc 1 abort (B1). Fine. |
| set to an unwritable path | `mkdir -p` at `:144` fails under `set -e` → rc 1 with a raw shell error, no diagnostic. Pre-existing; the new non-empty guards at the call sites convert it into a loud degrade instead of a silent stop. |

### 3.3 The five `LEADV2_*_PATH` overrides in `leadv2-broad-status.sh`

`LEADV2_FOUNDER_STATUS_PATH`, `LEADV2_FOUNDER_STATUS_FULL_PATH`, `LEADV2_BOARD_EMPTY_SINCE_PATH`,
`LEADV2_FOUNDER_STATUS_EPOCH_PATH` (+ the hook's `LEADV2_FOUNDER_STATUS_PATH`).

| Case | Required behaviour |
|---|---|
| absent | resolver default (the change) |
| set | **override wins, resolver is not even called.** Mission-mandated; `test-broad-status-duty.sh:337` depends on it. Implement as `${LEADV2_X:-$(resolver …)}` — note bash evaluates the `$( )` only when the var is unset, so this also avoids paying a resolver fork per beat when a test pins the path. |
| set to empty string | `${X:-…}` falls through to the resolver. Correct — an empty override is not a path. |
| set to a path whose parent does not exist | writes fail. Pre-existing behaviour; do not add mkdir (a test pinning a read-only dir at `test-broad-status-duty.sh:337` relies on the failure). |

### 3.4 `glm-deferred.jsonl` content, at migration time

| Case | Required behaviour |
|---|---|
| absent locally | nothing to migrate (S8) |
| present, 0 bytes | move/append is a no-op; must not create a `.pre-controlplane-backup`, must still symlink |
| present, valid JSONL | S3 move or S4 line-union |
| **malformed** (truncated last line, non-JSON garbage) | **line-union must be textual, not JSON-parsed.** A JSON-parsing merge that raises on one bad line would abort the whole migration loop and leave *every* managed name unlinked in that worktree — an over-cap input taking down more than its own operation. Dedupe on exact line equality; never parse. |
| very large (MBs) | textual union is O(n) memory. Cap: if the local file exceeds ~8 MB, skip the merge, leave the local file in place, emit one stderr line. Better a visible un-migrated file than an OOM inside a hook. |

### 3.5 `glm-deferred.d/` directory

| Case | Behaviour |
|---|---|
| absent | create target dir, symlink (S8) |
| empty dir locally | rmdir local, symlink |
| entries colliding by name with target | **keep target's, do not overwrite** — the sig8 name is content-derived, so a same-name entry is the same task |
| contains a nested dir | `shutil.move` handles it; recurse not needed |
| unreadable entry | `except OSError: continue` — one entry skipped, the rest migrate |

### 3.6 `.arm-exceptions-<day>` (glob class)

| Case | Behaviour |
|---|---|
| absent | resolver returns the control-plane path, caller creates it |
| many days accumulated (3 files + 3 `.lock` siblings exist right now in this checkout) | all move-if-absent on first run |
| name from a caller-supplied `$day` that is empty | path becomes `.arm-exceptions-` — a real, single, shared file. Harmless but wrong; guard `[[ -n "$1" ]]` in the helper and fall back to `$(date -u +%Y%m%d)`. |
| `$day` containing `/` or `..` | would escape the state root. `$day` is produced internally by `date`, but the helper is a public-ish function: reject anything not `[0-9]{8}`. |

### 3.7 `.gitignore` (repo-level input to the *symptom*, not the mechanism)

Currently ignored in this repo: `founder-status*.md`, `glm-deferred*`, `.arm-exceptions-*`,
`.codex-credits-empty.stamp`, `.broad-status-prev.json`, `status-snapshot.json`, `*.lock`.
**Not ignored, and not tracked:** `docs/leadv2/.board-empty-since`,
`docs/leadv2/.founder-status-epoch`. Those two are live untracked files in this checkout right
now (`ls` confirms both). Add them, plus `docs/leadv2/*.pre-controlplane-backup`.

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every finding above is fixed

The invariant: *no session-global leadv2 state is stored per-worktree, and no worktree is dirty
because of it.* After all of the above, four things can still violate it.

**(i) The invariant is enforced by nothing but review.** There is a documented contract in the
resolver's header and a `grep` in this task's done-criteria, but no test and no hook asserts
that a *new* `$PROJECT_ROOT/docs/leadv2/<x>` string cannot be added tomorrow. `leadv2-resume.sh:27`,
`leadv2-lane-liveness.sh:41-42` and `leadv2-status-render.sh:37-39` already reference
`active.yaml`, `tombstones.yaml` and `.status-collector-disabled` raw, *after* the header
declared active.yaml resolver-only — the contract is already being violated by three files in
the tree today. The counterexample is therefore concrete, not hypothetical: the same drift that
produced this task will produce the next one. **Mitigation, and I recommend it be built in this
lane:** a guard test that greps `plugins/leadv2/{scripts,hooks}` for
`PROJECT_ROOT}?/docs/leadv2/` against an explicit allow-list of names, failing on any name not
on it. Without it, done-criterion 1 is a one-time observation, not an invariant.

**(ii) `status-snapshot.json` (298 KB, rewritten every beat) is still per-worktree.**
Deliberately deferred (§0c). Until its lane lands, ~30 worktrees can each hold a 300 KB
snapshot and each lane's board view is derived from its own copy. It is gitignored, so it is
invisible in Source Control — which is exactly why it will not be noticed.

**(iii) The two consuming repos.** m3-market and respiro-ios have not done persona-engine's
`ffb0c8c0a` gitignore work. The resolver will plant symlinks at `docs/leadv2/founder-status.md`
etc. in their worktrees too. If any of those five names is *tracked* in either repo, the symlink
becomes a permanent typechange — the same ` T docs/leadv2/active.yaml` that this very checkout
shows in `git status` right now. Mission forbids touching a consuming repo, so this is a
**required follow-up**, and the developer should say in the journal that it is unverified for
those two repos.

**(iv) Per-worktree `docs/leadv2/tasks/` journals.** `leadv2-pulse.sh:35` and
`leadv2-pulse-write.sh:30` write `$PROJECT_ROOT/docs/leadv2/tasks/$TASK_ID/`, and those are
*tracked* (`git ls-files` shows hundreds). Three of them are modified in this checkout right
now. They are per-task, so per-worktree is arguably correct — but a task's journal written in
lane A is invisible to lane B, and the lane's removal takes it. Not this task; naming it so the
next reader does not think it was missed.

Nothing else I checked violates it: the nine names already in `STANDARD` are covered, the
orphan-root absorber at `:204` covers the `.git/leadv2-state` hazard, and the ephemeral redirect
at `:114` keeps test fixtures out of the production base.

---

## 5. Implementation shape (what the developer writes — not the code)

1. `leadv2-state-path.sh`
   - Header: replace the "these five files" sentence with the full managed set, grouped by class
     (STANDARD / RENDER / MERGE / GLOB), and state that the `docs/leadv2/<name>` symlink is a
     **contract for the RENDER set** because a human and two tests open those paths directly.
   - Migration python block: add the RENDER (S6), MERGE (S4/S5) and GLOB (S9) classes described
     in §2.2, with the malformed/large-input rules from §3.4.
   - Wrap that block in `flock -w 5` on fd 7 (§2.3); on timeout, skip migration, still print.
2. `leadv2-dispatch-code.sh` — four helpers (`:876`–`:879`) resolve through the script, memoized
   in four plain scalars (bash 3.2: no associative arrays), each with the non-empty guard and
   old-path fallback from §2.1, and the `$day` validation from §3.6.
3. `leadv2-broad-status.sh` — four vars (`:36`,`:44`,`:61`,`:62`) become
   `${LEADV2_X:-$("$STATE_PATH_SH" <name>)}` plus the non-empty guard. `:34`/`:35` untouched.
4. `hooks/leadv2-single-lead-beat.sh:132` — same shape. **Hook caveat:** per the shared-trees
   policy the plugin *cache* is a separate copy; a hook edit needs the cache copy + a session
   restart or it never loads. The developer must say in the journal whether they did that.
5. `.gitignore` — three additions (§3.7).
6. Tests (`plugins/leadv2/scripts/tests/`):
   - **new** `test-state-path-worktree-identity.sh` — the invariant test: for each managed name,
     resolve from a linked worktree and from the main checkout of the same scratch repo, assert
     byte-identical output. This is the point of the task.
   - **new** `test-state-path-migration.sh` — S3/S4/S5/S6/S9: pre-seed old-path content in two
     different worktrees; assert the ladder's lines from both survive, `glm-deferred.d/` entries
     from both survive, a render collision leaves **no** `.pre-controlplane-backup`, and a
     malformed ladder line does not abort the loop.
   - **new** `test-state-path-no-raw-paths.sh` — the guard from §4(i).
   - **fix** `test-glm-deferred-ladder.sh:390` — the stub re-definition (§1.2), or the suite
     is a lying-green.
   - re-run `run-core-offline.sh` plus the four suites the mission names.

---

## 6. Explicit non-goals

- `SNAPSHOT_PATH` / `status-snapshot.json` and `PREV_PATH` / `.broad-status-prev.json`
  (§0c) — separate lane, three-script atomic change.
- `active.yaml` / `tombstones.yaml` / `.status-collector-disabled` raw references in
  `leadv2-resume.sh`, `leadv2-lane-liveness.sh`, `leadv2-status-render.sh`,
  `leadv2-status-snapshot.sh`, `leadv2-phase-advance.sh`, `leadv2-budget-check.sh` — pre-existing
  violations of the *existing* contract; the §4(i) guard test will surface them as an allow-list
  entry, not fix them.
- `docs/leadv2/tasks/**` journals (§4iv).
- Any change in persona-engine, m3-market, respiro-ios.
- The `SCRIPT-SIZE-AUDIT` work and any restructuring of either dispatcher.
- Removing the two existing tracked `*.pre-controlplane-backup` files.

---

## 7. Acceptance

acceptance:
  - surface: file_artifact
    observable: "In a lane worktree under .claude/worktrees/, `docs/leadv2/founder-status.md`,
      `founder-status-full.md`, `.founder-status-epoch`, `.board-empty-since`,
      `glm-deferred.jsonl`, `glm-deferred.d`, `.codex-credits-empty.stamp` each appear as an
      arrow-pointing symlink into ~/.claude/leadv2-state/<repo>/, and opening
      `docs/leadv2/founder-status-full.md` from the main checkout shows the same text as
      opening it from that lane worktree."
    authored_at: 2026-08-23T07:05:00Z
  - surface: rendered_line
    observable: "The founder's Source Control panel shows zero entries under docs/leadv2/ for
      any lane worktree — no modified rows, no untracked rows, and no
      `*.pre-controlplane-backup` rows — where before it showed 5–13 per worktree."
    authored_at: 2026-08-23T07:05:00Z
  - surface: file_artifact
    observable: "After an upgrade run in a checkout that already held a deferral ladder, the
      GLM deferral list still names every task it named before the upgrade, and a task parked
      from one worktree and a task parked from a second worktree are both present in the same
      list."
    authored_at: 2026-08-23T07:05:00Z
  - surface: log_line
    observable: "When the control-plane root cannot be resolved, the loop log carries one line
      naming the failed path resolution and the status still renders at the old location —
      instead of the founder's 30-minute status simply never appearing again."
    authored_at: 2026-08-23T07:05:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-state-path.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-broad-status.sh, plugins/leadv2/hooks/leadv2-single-lead-beat.sh, .gitignore, plugins/leadv2/scripts/tests/test-state-path-worktree-identity.sh, plugins/leadv2/scripts/tests/test-state-path-migration.sh, plugins/leadv2/scripts/tests/test-state-path-no-raw-paths.sh, plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
