# SWEEPER-LANE-SAFETY-01 — architect prepass (mechanism-closed)

Task: dispatch-53b2ae6c-architect · role: architect · base 8bd1758 · repo ~/Projects/leadv2

## 0. Where the mission's framing is wrong (read this first)

The mission names `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh` as the suspect and asks
that the *sweep candidate check* be hardened there. Discovery says that hook is the **less**
destructive of two unattended lane-eating paths, and cannot by itself produce either reported
incident shape.

| | merged-sweep hook | `leadv2-worktree-cleanup.sh --sweep-dead` |
|---|---|---|
| fires | SessionStart hook, every session | SessionStart, via `leadv2-stale-sweeper.sh:394-401`, unattended, non-interactive |
| removal call | `git worktree remove` **without** `--force` (`hooks/leadv2-merged-worktree-sweep.sh:95`) | `git worktree remove --force` (`scripts/leadv2-worktree-cleanup.sh:136`) |
| branch | left intact (header line 21) | **`git branch -D "$wt_branch"`** (`:137`) — commits become unreachable |
| lane protections | none beyond ahead==0 + dirt | lane-liveness verdict must be `dead:*` (`:96-102`), merge-blocker.flag (`:106`), dirty (`:112`), ahead>0 (`:128`) |
| active.yaml consulted | **no** | **no** |
| handoff/arm state consulted | **no** | only `merge-blocker.flag` |
| grace window | **none** | **none** |

Consequences that match the two incidents:

- **43ae4318 "deleted entirely"** — only `--sweep-dead` deletes a branch as well as a checkout.
  A lane worktree that is freshly created (no commits yet ⇒ `ahead=0`), spotless (no dirt yet),
  and whose worker has not yet written a log ⇒ `leadv2-lane-liveness.sh` returns a `dead:*`
  verdict (see its `LEADV2_LANE_STARTING_MAX_S` / `LEADV2_LANE_ABANDON_MAX_S` inputs at
  `scripts/leadv2-lane-liveness.sh:60`). All four `--sweep-dead` guards pass ⇒ `remove --force`
  + `branch -D`. That is the whole kill.
- **b413968c "gutted to a single docs/ dir"** — that is the *merged-sweep hook's* failure shape,
  not a removal: lines 90-93 `git checkout --` / `rm -f` every path matching `_MW_ORCH_RE`
  **before** attempting removal. If the subsequent `git worktree remove` refuses (line 95→98),
  the hook has already destroyed the lane's `docs/leadv2/` + `docs/handoff/` working state and
  leaves the husk behind. The hook mutates the tree *before* it has decided it may remove it.

So the design must harden **both** paths, and must fix the hook's mutate-before-decide ordering.
Findings in the mission tell me where to look; they do not bound this.

`leadv2-orphan-monitor-sweep.sh` is **not** in this kill-class (audit, deliverable 4): it never
touches the filesystem or git — it `kill -KILL`s `zsh -c … codex-task.sh status` PIDs older than
900s (`:13-34`). It cannot remove a worktree. It *is* capable of killing a live lane's Monitor
loop, but that is a different defect and out of scope here. No change proposed; rationale goes in
the summary.

## 1. CALLERS / CALLEES

### 1a. `hooks/leadv2-merged-worktree-sweep.sh`
- **Callers:** SessionStart hook registration (plugin hooks config; not a script call site — it is
  invoked by the harness with `CLAUDE_PROJECT_DIR` set, line 35). Kill switch
  `LEADV2_MERGED_WORKTREE_SWEEP=0` (line 33).
- **Callees:** `git worktree list --porcelain` (:100), `git rev-list --count BASE..HEAD` (:59),
  `git status --porcelain` (:79, :90), `git checkout --` / `rm -f` (:92), `git worktree remove`
  (:95), `git worktree prune` (:102). No plugin script is called today — it is deliberately
  standalone (header :71-73).
- **Twin it must not drift from:** `_MW_ORCH_RE` is duplicated in
  `scripts/leadv2-dispatch-product-close.sh`; `tests/test-merged-sweep-orchestration-dirt.sh:15-18`
  asserts the two copies match. **Any new protection helper must not break that assertion.**

### 1b. `scripts/leadv2-worktree-cleanup.sh`
Three modes, each its own removal site:
- `--sweep-dead` (:~85-140) — **callers:** `leadv2-stale-sweeper.sh:399` (unattended, every
  SessionStart). Removal at `:136` + `branch -D` at `:137`.
- `--sweep-merged` (:~215-250) — removal at `:242` + `branch -D` at `:243`. **Callers:** none live
  today (`grep` finds only the merged-sweep hook's header comment referencing it,
  `hooks/leadv2-merged-worktree-sweep.sh:10`). Dead-but-loaded gun — harden it anyway, it is one
  `bash … --sweep-merged` away from live.
- `--name <id>` (:~290-350) — removal at `:344`. **Callers:**
  `leadv2-dispatch-code.sh:2807`, `leadv2-fanout-lane-launcher.sh:408`,
  `leadv2-fork-session.sh:573`, `leadv2-phase8-close.sh:608-621`,
  `leadv2-stale-sweeper.sh:332` (interactive `d=discard` only, `--force`),
  `docs/phases.md:462`. These are **legitimate targeted reaps of a lane the caller owns** and must
  keep working — the protection gate is for the *sweep* modes, not for `--name`.
- **Callees:** `leadv2-lane-liveness.sh` (`LIVENESS_BIN_SM`, :~90 and :~215),
  `lv2_default_branch`, `lv2_branch_merged` (sourced helpers).

### 1c. Other `worktree remove` sites on other paths (named so nobody claims a miss)
- `scripts/leadv2-codex-lead.sh:390` — `remove --force` on **its own** just-created codex worktree.
  Owner-scoped, not a sweeper. Out of scope.
- `scripts/leadv2-red-first-gate.sh:155` — `remove --force` on **its own** scratch worktree.
  Owner-scoped. Out of scope. (This is the one standing-memory
  `feedback-remove-scratch-worktree-before-review` refers to; it is correct as written.)

### 1d. New helper (to-create) `scripts/lib/leadv2-worktree-protected.sh`
- **Callers (after this change):** `hooks/leadv2-merged-worktree-sweep.sh`,
  `scripts/leadv2-worktree-cleanup.sh` (`--sweep-dead` and `--sweep-merged` only).
- **Callees:** `leadv2-state-path.sh --no-link active.yaml`, `leadv2-state-path.sh --no-link
  dispatch-ledger.jsonl`, `python3` (one pass), `date`/`stat`.
- **Deliberately NOT a caller:** `--name` mode. A named reap is an owner decision.

## 2. STATES AND RETURN CODES

New contract — `lv2_worktree_protected <repo_root> <worktree_path>`:

| rc | state | who returns it | caller behaviour (both sweepers) | user-visible consequence |
|----|-------|----------------|----------------------------------|--------------------------|
| 0 | NOT protected | all four probes negative | proceed to the existing merged/dirty/liveness gates | worktree may be swept, as today |
| 1 | protected: `active_yaml` — lane id present in `sessions[].task_id` or `sessions[].worktree` matches this path, **any** state | probe A | `continue`, debug-log only | registered lane survives its session; nothing user-visible |
| 2 | protected: `arm_open` — `docs/handoff/dispatch-<id>/arm-registered` exists (in main repo **or** in the worktree) and no TRUE terminal row for `<id>` in the dispatch ledger | probe B | `continue`, debug-log only | a lane between fix rounds, or before its first commit, survives |
| 3 | protected: `live_pid` — a registered pid for `<id>` is alive | probe C | `continue`, debug-log only | a running worker is not decapitated mid-write |
| 4 | protected: `young` — worktree mtime younger than `LEADV2_SWEEP_MIN_AGE_H` (default 48) | probe D | `continue`, debug-log only | a lane created minutes ago is never swept by the session that follows it |
| 5 | **fail-closed** — any read error: state-path resolver failed, active.yaml unreadable/malformed, ledger unreadable, `python3` absent | any probe | `continue` **and** one `stderr` line `[<sweeper>] protected(read-error) <id> — sweeping nothing this pass` | on a broken control plane nothing is ever removed; the founder sees exactly one line, not silence |

Terminal-outcome trace (the part that matters): rc 1-5 all land on `continue` inside the
`while … done < <(git worktree list …)` loop in each sweeper. There is **no retry and no
escalation** — the worktree is simply still there next session, when the probes run again. The
only way a protected worktree is ever removed is that its protection genuinely lapses (session
unregisters, ledger records `landed|dead`, pid dies, 48h elapse) or a human runs
`leadv2-worktree-cleanup.sh --name <id>`, which does not consult this gate. In plain words: **the
worst case of this change is a stale directory the founder must remove by hand; the failure it
removes is a dead worker attempt plus a manual repair and redispatch.**

Existing sweeper rcs are unchanged: both sweepers still `exit 0` unconditionally
(`hooks/…:113`, cleanup `:255`/`:141`) — a hook that exits non-zero at SessionStart is itself an
incident, and the ERR trap at `hooks/…:31` exists for exactly that.

## 3. CONFIGURATION BOUNDARIES

Inputs the mechanism reads, and behaviour at each boundary. All four probes are wrapped so that
"I could not read this" is rc 5 (protected), never rc 0.

| input | absent | empty | minimum | maximum / over-cap | malformed |
|---|---|---|---|---|---|
| `active.yaml` (resolved via `leadv2-state-path.sh --no-link active.yaml` → `~/.claude/leadv2-state/<slug>/active.yaml`) | file missing → **rc 5** (a missing registry is indistinguishable from a broken one) | `sessions: []` → probe A negative, rc 0 (this is the live steady state today) | one row → id compare | thousands of rows → single `python3` pass, whole file read once per sweeper run, not per worktree | non-YAML / truncated → `yaml.safe_load` raises → **rc 5**. `import yaml` missing → **rc 5** (note: `leadv2-stale-sweeper.sh:293-295` prints `'yes'` = keep on ImportError — same fail-closed direction, reuse that stance) |
| `LEADV2_SWEEP_MIN_AGE_H` | unset → 48 | `""` → 48 | `0` → age probe disabled (explicit opt-out, still honoured; probes A-C still apply) | no upper clamp needed, but a value ≥ `2^31` must not break arithmetic — parse with a python `int()` inside `try`, on failure → 48 **and** one stderr line. **A malformed env var must not take down the sweep for every other worktree** — it degrades to the default, it does not abort. | non-numeric (`"48h"`, `"abc"`) → 48 + one stderr line |
| `docs/handoff/dispatch-<id>/arm-registered` | absent in both main repo and worktree → probe B negative | zero-byte file → **still counts as present** (`dispatch-code.sh:658` writes it as a marker; content is `arm=… handle=… epoch=…`, but presence is the signal — never parse it to decide protection) | n/a | n/a | unreadable (perm) → **rc 5** |
| dispatch ledger `~/.claude/leadv2-state/<slug>/dispatch-ledger.jsonl` (`leadv2-dispatch-ledger.sh:118-130`) | absent → no terminal row ⇒ arm-registered lane counts as **open** ⇒ rc 2. Correct direction. | empty file → same as absent | one row | large jsonl → read once per sweeper run into a `sig8 → last terminal` dict, not once per worktree | a line that is not JSON → skip that line, keep going; a file that cannot be opened → **rc 5** |
| worktree path / lane id (`basename "$wt"`) | n/a | n/a | id `SCRIPT-SIZE-AUDIT-20260821` (a real non-sig8 worktree on disk today) — probes must handle a non-hex id without throwing | 255-char basename | id with `/` or shell metachars — impossible from `git worktree list`, but the helper must still quote every expansion |
| `python3` | absent from PATH → **rc 5 for every worktree**, one stderr line, sweep does nothing | — | — | — | — |

**Explicit non-regression:** the age probe reads the worktree directory's mtime, not `git log`.
A lane sitting at base with zero commits has no commit timestamp to read; using `HEAD`'s date
would inherit `main`'s age and defeat the grace window entirely.

## 4. COUNTEREXAMPLE — what still eats a lane after every mission item is fixed

Two things survive, and one of them is the more likely next incident.

**(a) `--name` mode is not gated, by design, and `leadv2-stale-sweeper.sh:332` calls it with
`--force`.** That path is guarded only by `INTERACTIVE=true` and a founder typing `d`. If a future
change flips stale-sweeper to non-interactive-discard — or if a founder types `d` while a lane is
mid-round — `--name … --force` forces past merge-blocker, unmerged commits *and* dirt
(`leadv2-stale-sweeper.sh:383-386` documents exactly this), and this design does not stop it. I am
deliberately not gating `--name`: a targeted reap by an owner is the one removal that must always
work. The residual risk is real and belongs in the summary as a follow-up, not in this diff.

**(b) The window between `git worktree add` and the `active.yaml` register / `arm-registered`
write.** Probes A-C are all *registration* signals, and a lane is unregistered for the first few
hundred milliseconds of its life. During that window only probe D (age) protects it — which is
precisely why the grace window is not optional and must not default to 0. If someone later
"optimises" `LEADV2_SWEEP_MIN_AGE_H=0` into the plugin's env block, incident 43ae4318 reproduces
exactly. **This is why the age probe is listed as a peer of A-C and not as a nicety.**

What I checked and found clean: every `worktree remove` / `rm -rf` site in
`plugins/leadv2/{scripts,hooks,scripts/lib}` (grep over `worktree remove|rm -rf|prune`), which is
the six sites in §1b-§1c; `leadv2-orphan-monitor-sweep.sh` end to end (40 lines, no fs writes);
`git worktree prune` in both sweepers (prunes only *administrative* records for paths already gone
from disk — it cannot delete a live directory).

## 5. Design

### 5.1 New file — `plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh` (to-create)

Sourceable, no side effects on source. Exports one function and one bulk primer:

```
lv2_wt_protect_prime <repo_root>          # reads active.yaml + ledger ONCE per sweeper run
lv2_worktree_protected <repo_root> <path>  # rc per the §2 table; sets LV2_WT_PROTECT_REASON
```

Why a lib and not inline-in-both: `_MW_ORCH_RE` is already the repo's cautionary tale about two
hand-kept copies of one rule (`hooks/leadv2-merged-worktree-sweep.sh:70-73`). One inode, two
callers. The hook may source it because the lib lives inside the plugin tree next to the hook
(`${SCRIPT_DIR}/../scripts/lib/…`) — the "must run standalone at SessionStart" constraint means
*no dependency on repo state*, not *no dependency on plugin files*. Source is guarded: if the lib
is missing, the sweepers define a stub returning rc 5 (protect everything) — a plugin install that
lost the lib sweeps nothing rather than sweeping blind.

### 5.2 `hooks/leadv2-merged-worktree-sweep.sh`

1. After the `*/.claude/worktrees/*` filter and the `-d` check (line 56), **before** the `ahead`
   probe: call `lv2_worktree_protected`. rc≠0 → `continue`.
2. **Move the destructive `checkout --`/`rm -f` block (lines 90-93) to after** a dry decision.
   Correct order: protection → ahead → real-dirt → *then* discard orchestration paths → remove. If
   `git worktree remove` still fails, that is now the only case where the tree was mutated, and it
   is a case where every gate said "removable". This fixes the b413968c gutting shape.
3. Journal every actual removal: `worktree_swept id=<id> reason=merged-clean` via
   `bash "${SCRIPT_DIR}/../scripts/leadv2-journal.sh" append "<id>" note "worktree_swept id=<id> reason=<…>"`
   (`scripts/leadv2-journal.sh:4` usage; type whitelist at `:57` is
   `phase|decision|finding|error|note`, anything else silently becomes `note` — so pass `note`
   explicitly and put `worktree_swept` in the text, as the mission's literal string requires).
   Journal failure must never abort the sweep (`|| true`).
4. Protected skips: **no stderr**. One line to `/tmp/leadv2-sweep.log` (the file
   `leadv2-orphan-monitor-sweep.sh:38` already uses), so a forensic trail exists without per-turn
   noise. This is the "debug level only" the mission asks for.

### 5.3 `scripts/leadv2-worktree-cleanup.sh`

Add the same gate as the **first** check inside both sweep loops (`--sweep-dead` before the
liveness probe at `:96`; `--sweep-merged` before its liveness probe at `:~215`). `--name` mode is
untouched. Add the same `worktree_swept` journal line at `:136` and `:242`.

### 5.4 Docs

- `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh` header: replace the "SAFETY — removed only
  when ALL of these hold" list with the four-probe protection contract + the two incident ids.
- `plugins/leadv2/docs/single-lead-pulse.md` worktree section: one paragraph — a lane worktree is
  untouchable while registered, arm-open, live, or younger than `LEADV2_SWEEP_MIN_AGE_H`; the only
  removal that ignores this is the owner's own `--name` reap.

### 5.5 Tests — `plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh` (to-create)

Convention followed: `test-merged-sweep-orchestration-dirt.sh` — `mktemp -d` fixture repo, `_mk`
builder, `_swept` predicate, pre-fix binary fetched via `git show HEAD:<path>` for the red-first
dual pass, `PASS/FAIL/GREEN_PRE_FIX` counters. Cases, each run against **both** sweepers:

| case | fixture | expect |
|---|---|---|
| P1 registered | lane in `active.yaml` `sessions[].task_id`, clean, ahead=0, old | not swept |
| P2 arm-open | `docs/handoff/dispatch-<id>/arm-registered` present, ledger has **no** row | not swept |
| P3 arm-terminal | same + ledger row `terminal:"landed"` | **swept** (protection correctly lapses) |
| P4 live pid | registered row with `pid` = a live `sleep` process | not swept |
| P5 young | no registration at all, mtime = now, `LEADV2_SWEEP_MIN_AGE_H=48` | not swept |
| P6 true orphan | no row, no handoff, mtime backdated, merged, clean | **swept** |
| P7 unreadable | `active.yaml` = `\x00\x00not: [yaml` | **nothing** swept (P6 fixture present and survives) |
| P8 malformed env | `LEADV2_SWEEP_MIN_AGE_H=abc` + P6 fixture | P6 still swept (degrade to 48, do not abort the pass) |
| P9 gutting | merged lane, orchestration-only dirt, removal made to fail | tree contents intact **or** tree gone — never a husk with `docs/` wiped |
| P10 twin | `_MW_ORCH_RE` in hook == twin in `leadv2-dispatch-product-close.sh` | unchanged (re-assert; do not regress the existing test) |

Sandboxing: `LEADV2_STATE_ROOT` (documented at `scripts/leadv2-state-path.sh:53`) points the
control plane into the fixture; `LEADV2_DISPATCH_TERMINAL_LEDGER_FILE`
(`leadv2-dispatch-ledger.sh:119`) points the ledger there. **No test may touch the real
`~/.claude/leadv2-state/leadv2/`.** No test spawns a worker — P4 uses a plain `sleep` pid.

## 6. Non-goals (implementer: ignore these)

- Changing `--name` mode, or any owner-scoped removal (`codex-lead.sh:390`,
  `red-first-gate.sh:155`).
- Changing `leadv2-orphan-monitor-sweep.sh` (audited, different class — see §0).
- Changing `leadv2-lane-liveness.sh` verdict semantics. The gate wraps it; it does not fix it.
- Changing `leadv2-stale-sweeper.sh`'s interactive `d=discard` path (§4a — follow-up, not this diff).
- Any change to `active.yaml` schema, the ledger schema, or the state-path resolver.
- Deleting or archiving the ~20 worktrees currently on disk.

## 7. Acceptance

```
acceptance:
  - surface: log_line
    observable: >
      At the next SessionStart in ~/Projects/leadv2, the founder sees a line naming a
      number of removed lane worktrees, and every lane id listed in that line is absent
      from the active session registry — no id that a running /leadv2 lane is using
      appears in it.
    authored_at: 2026-08-24T12:30:00Z
  - surface: file_artifact
    observable: >
      A worktree directory whose lane was created less than 48 hours ago is still present
      on disk, with its files intact, after a session has started and finished.
    authored_at: 2026-08-24T12:30:00Z
  - surface: file_artifact
    observable: >
      For each lane worktree that is actually removed, its task journal contains a line
      reading "worktree_swept id=<id> reason=<…>" — a human reading that journal can tell
      why the directory disappeared without doing git forensics.
    authored_at: 2026-08-24T12:30:00Z
  - surface: file_artifact
    observable: >
      With a corrupted session registry in place, every lane worktree that existed before
      the session still exists after it, and one message on screen says the sweep was
      skipped because the registry could not be read.
    authored_at: 2026-08-24T12:30:00Z
```

## 8. Constraint checklist

1. **Env var naming** — `LEADV2_SWEEP_MIN_AGE_H` matches the `LEADV2_*` convention used by every
   sibling (`LEADV2_MERGED_WORKTREE_SWEEP`, `LEADV2_LANE_SILENT_MAX_S`, …). No `LEAD_V2_*` form
   introduced. No existing `LEADV2_SWEEP_*` name collides (grep: none).
2. **File paths** — all cited paths verified on disk this run except three marked `(to-create)`:
   `scripts/lib/leadv2-worktree-protected.sh`, `scripts/tests/test-worktree-lane-safety.sh`, and
   the new `single-lead-pulse.md` paragraph (file exists; section to add).
3. **`claude -p`** — this design introduces no `claude -p` invocation. N/A.
4. **Concurrent access** — the sweepers read `active.yaml` and the ledger while live lanes write
   them. Both are read-only reads here, and both writers hold locks
   (`leadv2-portable-lock.sh`, `leadv2-dispatch-ledger.sh:92`). A torn read is possible and is
   handled: it lands in rc 5 (protect everything), not in rc 0. **The gate must not take the
   writers' locks** — a SessionStart hook blocking on a lane's lock is a worse failure than a
   stale directory.
5. **Config contradiction** — `LEADV2_MERGED_WORKTREE_SWEEP=0` still short-circuits the hook before
   any probe runs; the two flags compose (kill switch wins). No contradiction found.

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh, plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh, plugins/leadv2/scripts/leadv2-worktree-cleanup.sh, plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh, plugins/leadv2/docs/single-lead-pulse.md

DELIVERABLE_COMPLETE
