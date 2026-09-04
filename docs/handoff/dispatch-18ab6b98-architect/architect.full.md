# SWEEPER-LANE-SAFETY-01 — architect prepass (mechanism-closed design)

Base: `eb39d6f`. Repo: `~/Projects/leadv2`. All line references are from the tree at that base.

---

## §0. Where the mission's framing is wrong (read this first)

The mission names one suspect — `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh` — and one
wrong criterion ("no unmerged commits"). Code discovery says the criterion critique is right but
the **blast surface is three removers, not one**, and the hook is not the most destructive of them.

| # | Remover | Path | Trigger | Guards it HAS | Destroys |
|---|---------|------|---------|---------------|----------|
| R1 | SessionStart hook | `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh:95` | every SessionStart (`hooks/hooks.json:76`, timeout 20) | merged-check only (`:59`), orch-dirt-filtered dirty check (`:79`) | checkout dir; **also mutates the tree at `:90-93` before deciding** |
| R2 | `--sweep-merged` | `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh:242-244` | every Phase-8 close (`leadv2-phase8-close.sh:611`) | cwd (`:184`), liveness (`:209`), merge-blocker.flag (`:227`), raw dirty (`:236`) | `worktree remove --force` **+ `branch -D`** |
| R3 | `--sweep-dead` | `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh:137-138` | Phase-8 close (`:618`) and `leadv2-stale-sweeper.sh:394-402` at startup | cwd, liveness, merge-blocker, raw dirty, ahead>0 | `worktree remove --force` **+ `branch -D`** |

Three findings that the mission does not contain and that change the design:

**F1 — R1 has no CWD guard, R2/R3 do.** R1 iterates `git worktree list` (`:100`) with no
equivalent of R2's `KEPT (cwd)` branch at `:184`. `git worktree list` from *inside* a lane
enumerates the whole repo's worktrees including that lane. `ROOT` is `CLAUDE_PROJECT_DIR` (`:35`),
which for a session started in a lane **is the lane**. So a SessionStart inside lane A can select
lane A itself and every sibling lane.

**F2 — R1 mutates before it decides.** Lines `:90-93` run
`git checkout -- "$f" || rm -f "${wt}/${f}"` over every orchestration-dirt path *before*
`git worktree remove` at `:95` is even attempted. If the removal is then refused — and git refuses
to remove the current working tree, which by F1 is reachable — the loop has already deleted that
lane's untracked `docs/leadv2/` and `docs/handoff/` bookkeeping and left the tree standing. This
is the best code-grounded explanation for incident `b413968c` ("gutted to a single `docs/` dir"):
a partial destructive pre-step followed by a refused removal, exiting 0 under the trap at `:31`
with nothing logged. **Confidence: high on the mechanism (lines are unambiguous), medium on it
being the exact cause of that specific incident** — no forensic log survives, which is deliverable
#2's whole point.

**F3 — R1's own header comment is false about R2/R3.** `:21-22` promises "The branch itself is NOT
deleted … even a misjudgement costs a `git worktree add`, never a commit." True for R1. False for
R2 (`:244`) and R3 (`:138`), which both run `git branch -D` after `--force`. A `-D` on a lane
branch whose commits are *believed* merged is unrecoverable through the plugin's own tooling
(reflog only). Incident `43ae4318` ("deleted entirely") fits R2/R3, not R1. **The mission's
"suspect: the hook" framing would have shipped a fix that leaves the harsher remover untouched.**

Design consequence: the protection predicate must be **one shared implementation called by all
three**, and it must be evaluated **before any tree mutation**, not before `worktree remove`.

Repo precedent supports this: `leadv2-merged-worktree-sweep.sh:65-73` documents that the
orchestration-dirt regex is *deliberately duplicated* and is *asserted to be identical* by
`tests/test-merged-sweep-orchestration-dirt.sh` because "two hand-kept copies of one pattern is
the exact defect that produced a false lane refusal earlier the same day." A fourth hand-kept copy
of a *safety* predicate would repeat that. The hook must run standalone at SessionStart, so the
shared unit is a **sibling script invoked as a subprocess** (the pattern
`leadv2-dispatch-ledger.sh:69-80` mandates after sourcing broke an unrelated caller path), not a
sourced library.

---

## §1. CALLERS / CALLEES

### New unit: `plugins/leadv2/scripts/leadv2-worktree-protected.sh` (to-create)

```
leadv2-worktree-protected.sh is-protected --project-root <main-checkout> --worktree <abs-path>
```

**Callees** (all optional; absence is handled in §3):
- `plugins/leadv2/scripts/leadv2-lane-liveness.sh` — invoked `--lane <id> --json --project-root <root>`,
  verdict extracted exactly as `leadv2-worktree-cleanup.sh:92-98` already does (`python3 -c json.load`).
- `plugins/leadv2/scripts/leadv2-state-path.sh` — resolves `active.yaml`, mirroring
  `leadv2-lane-liveness.sh:41-47`. Fallback `<root>/docs/leadv2/active.yaml`.
- `python3` — active.yaml parse (see §3 for the no-python3 path).
- filesystem only for handoff markers and mtime.
- `plugins/leadv2/scripts/leadv2-journal.sh append` — only from the *callers*, not from here; this
  unit is a pure predicate and writes nothing.

**Callers to add** (three, and they are on genuinely different paths — the independent copy that
"nobody named" is R2/R3, which run at Phase-8 close, not at SessionStart):

| Caller | File:line to insert at | Path it is on |
|---|---|---|
| R1 | `hooks/leadv2-merged-worktree-sweep.sh` — new guard between `:56` (`[[ -d ]]`) and `:59` (ahead-check) | SessionStart, every session, every repo |
| R2 | `scripts/leadv2-worktree-cleanup.sh` — new guard after the cwd check at `:190`, before `lv2_branch_merged` at `:205` | Phase-8 close |
| R3 | `scripts/leadv2-worktree-cleanup.sh` — new guard after the cwd check at `:85`, before the liveness call at `:91` | Phase-8 close + `leadv2-stale-sweeper.sh:394` startup GC |

**Existing callers of each function being touched** (nothing else calls into them):
- R1 is called only from `hooks/hooks.json:76`. No other invocation anywhere in `plugins/`.
- `--sweep-merged`: `leadv2-phase8-close.sh:611`; also documented in `plugins/leadv2/docs/phases.md`
  and `scripts/tests/test-leadv2-worktree-sweep.sh` (which asserts cases 1–5 and must keep passing).
- `--sweep-dead`: `leadv2-phase8-close.sh:618`, `leadv2-stale-sweeper.sh:394-402`.
- `--name --force`: `leadv2-stale-sweeper.sh:332` (interactive, founder-confirmed) and
  `leadv2-worktree-cleanup.sh:344`. **Explicitly out of scope** — `--force` by name is a human
  saying "yes, this one". Not guarded.

**Not touched, verified present, and NOT the same kill-class:**
`leadv2-codex-lead.sh:390` and `leadv2-red-first-gate.sh:155` each `worktree remove --force` a
worktree **they themselves created moments earlier and hold the only handle to** (a codex-lead
scratch tree, a red-first-gate probe tree). They do not enumerate `git worktree list`, so they
cannot select a lane they did not create. No guard needed; stated here so review does not re-find them.

### Deliverable #4 — `leadv2-orphan-monitor-sweep.sh` audit: **SAFE, do not change**

Read in full (40 lines). Its candidate set is `ps -eo pid,etimes,command` filtered to
`/bin/zsh -c` processes whose command line contains `codex-task.sh status`, older than 900s
(`:13-19`). It never enumerates worktrees, never touches the filesystem except appending to
`/tmp/leadv2-sweep.log` (`:38`), and `kill -KILL -$pgid` (`:28`) targets a zsh polling loop, not a
worker. **Different kill-class entirely: it kills stale pollers, not lanes.** One residual risk is
noted and deliberately not fixed here: `:28` kills the whole *process group*, and if a Monitor loop
were ever spawned sharing a pgid with a worker, the worker would die with it. That is speculative
(no evidence of a shared pgid in this repo) and out of scope for a minimal diff; recorded in §4.

---

## §2. STATES AND RETURN CODES

### `leadv2-worktree-protected.sh is-protected` contract

| rc | Meaning | stdout | Caller behaviour |
|----|---------|--------|------------------|
| 0 | PROTECTED — a positive signal fired | `<reason-token>` (one of `active-yaml`, `arm-live`, `lane-live`, `too-young`, `cwd`) | skip this worktree, log at debug only |
| 1 | NOT protected — every check ran and none fired | (empty) | proceed to the caller's own merged/dirty checks |
| 2 | UNKNOWN — a required input could not be read | `read-error:<what>` | **treat exactly as rc0** (fail-closed) and log one visible line |
| ≥3 / any other | usage error, crash, binary missing | any | **treat exactly as rc0** (fail-closed) |

Callers implement this as `if ! guard …; then rc=$?; [[ $rc -eq 1 ]] || skip; fi` — i.e. **only rc1
permits sweeping**. This is the same shape as `leadv2-worktree-cleanup.sh:99` ("any verdict NOT
prefixed `dead:` … means KEEP"), so it reads as native to the file.

### Protection predicate — the five signals, evaluated in this order (cheapest first, short-circuit)

| # | Signal | Source of truth | Fires when |
|---|--------|-----------------|------------|
| P0 | `cwd` | `git -C <wt> rev-parse --show-toplevel` vs the sweeper's own cwd toplevel | the worktree IS the running session's tree (closes **F1**) |
| P1 | `too-young` | `stat` mtime of `<wt>/.git` (the worktree's gitfile, written at `worktree add`) | age < `LEADV2_SWEEP_MIN_AGE_H` (default 48) |
| P2 | `active-yaml` | `sessions[].task_id` in the resolved `active.yaml` | basename(wt) matches any `task_id`, **in any state** |
| P3 | `arm-live` | `docs/handoff/dispatch-<id>/arm-registered` exists AND no terminal row for `<id>` | see terminal-signal resolution below |
| P4 | `lane-live` | `leadv2-lane-liveness.sh --lane <id> --json` verdict | verdict is absent, unparseable, or NOT `dead:*` |

**Worktree-id resolution is dual, and this matters.** `leadv2-dispatch-code.sh:2462-2467` records
that a lane worktree lives at `.claude/worktrees/<founder_task_id>` *or* `.claude/worktrees/<sig8>`
— a function that resolved only by sig8 "silently" missed `14bd0c10`, which held a STOP-GATE
checkpoint commit. So P2/P3/P4 must each be tried against **both** `basename(wt)` and, when
basename is a founder task id, any sig8 whose `active.yaml` row or handoff dir names it. Concretely:
P2 matches `task_id == basename` **or** `basename` appearing as a substring-delimited field of the
row; P3 globs `docs/handoff/dispatch-*<basename>*/arm-registered` in addition to the exact
`docs/handoff/dispatch-<basename>/arm-registered`. Over-matching here costs a kept directory;
under-matching costs a lane. **Bias to over-match, always.**

**Terminal-signal resolution for P3** (deliverable #1's "reuse how product_close stamps terminal"):
`leadv2-dispatch-product-close.sh:129` calls
`leadv2-dispatch-ledger.sh write-terminal <sig8> …`, and that ledger exposes exactly the query we
need — `leadv2-dispatch-ledger.sh:60`: `exists <sig8>` → **rc0 iff a TRUE terminal (`landed`|`dead`)
row exists; a refused/parked-only history returns rc1 (retryable)**. That semantic is precisely
"terminal state recorded" vs "not terminal", so P3 is:
`arm-registered` present AND `leadv2-dispatch-ledger.sh exists <sig8>` returns non-zero → PROTECTED.
Do **not** re-implement the ledger scan; call `exists`. If the ledger binary is missing or errors,
that is rc2 → fail-closed (§3).

### Terminal outcomes traced to user-visible consequence

| Situation | rc chain | What a human sees |
|---|---|---|
| Live lane, guard fires | guard rc0 → R1 `continue` at the new guard | the lane directory is still there next session; the worker's commits land normally; **nothing in chat** (debug-level only) |
| Genuinely orphaned lane | guard rc1 → R1 falls through to `:59` ahead-check → `:95` remove succeeds | one stderr line at SessionStart naming the removal, plus a journal row; **the founder can later answer "what happened to `<id>`?" from disk** — today he cannot, which is exactly why both incidents were diagnosed forensically |
| `active.yaml` unreadable/corrupt | guard rc2 → fail-closed for **every** worktree in that repo | **no worktree is swept this session in this repo**; one stderr line says so. Worktrees accumulate until the file is fixed. This is the intended trade: a stale directory is free, a destroyed lane costs a dead worker attempt plus a manual repair/redispatch (twice on 2026-08-24) |
| `LEADV2_MERGED_WORKTREE_SWEEP=0` | R1 exits 0 at `:33` before anything | unchanged; R2/R3 still run at Phase-8 close and are still guarded |
| Guard script itself absent (old install / partial update) | `[[ -x ]]` false → treated as rc2 | nothing swept, one line. **Never "guard missing therefore proceed."** |

Note on R1's ERR trap (`:31`): it prints and `exit 0`. Any `set -e`-fatal inside the new guard call
must not be allowed to make the hook exit *before* the journal write. Invoke the guard as
`bash "$GUARD" … ; rc=$?` — never bare, never inside a `&&` chain, so `pipefail`/ERR cannot fire on
the non-zero-is-normal rc1.

---

## §3. CONFIGURATION BOUNDARIES

| Input | Absent | Empty | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|
| `LEADV2_SWEEP_MIN_AGE_H` | default `48` | default `48` | `0` = grace disabled (P1 never fires); legal, documented | no cap needed, but a huge value (e.g. `999999`) simply means **nothing is ever swept** — degradation is "directories accumulate", never "a lane dies". Do **not** clamp; clamping a safety knob toward *less* safety is the wrong failure direction | non-numeric (`abc`, `4 8`, `-1`) → **use the default 48 and log one line**. Never `0`, never unset-behaviour. Validate with `[[ "$v" =~ ^[0-9]+$ ]]` |
| `active.yaml` | file missing → `sessions` treated as empty, P2 cannot fire → **rc2 fail-closed**, because "missing" is indistinguishable from "not yet written" | `sessions: []` (the current live value) → P2 does not fire, rc continues to P3. This is the normal idle case and must **not** be rc2 | one row | many rows → linear scan, no cap. `meta.hard_limit: 3` bounds it in practice | unparseable YAML → **rc2 fail-closed for the whole run** (deliverable #1's explicit requirement). A single bad file must not selectively protect some lanes and expose others |
| `docs/handoff/dispatch-<id>/` | absent → P3 does not fire | dir exists, no `arm-registered` → P3 does not fire (the lane never registered an arm) | — | thousands of handoff dirs (this repo already has many) → the exact-path check is O(1); the glob fallback is O(dirs) once per worktree. Worktrees are ≤ tens, so ≤ tens of globs. Acceptable inside the 20s hook timeout; if it ever isn't, the glob is the thing to drop, not the exact check | `arm-registered` present but unreadable (perm) → rc2 |
| `leadv2-lane-liveness.sh` | not executable → P4 cannot run → **rc2** (matches `leadv2-worktree-cleanup.sh:99`'s existing "missing binary means KEEP") | verdict empty → protected | — | liveness itself shells out to `codex-task.sh`; pass **`--no-codex`** (flag exists, `leadv2-lane-liveness.sh:29`) from the SessionStart hook to keep it inside the 20s budget | non-JSON stdout → verdict `""` → protected |
| `leadv2-dispatch-ledger.sh` | missing → rc2 | — | — | — | any rc other than 0/1 → rc2 |
| `<wt>/.git` mtime | file missing (broken worktree) → P1 cannot evaluate → **rc2**; `git worktree prune` is the right tool for that, not this sweeper | — | mtime in the future (clock skew) → age computed negative → treat as `0` hours → **protected** | very old → P1 does not fire, other signals decide | `stat` unavailable/differs BSD vs GNU → try `stat -f %m` then `stat -c %Y`; both fail → rc2 |
| `python3` | absent → active.yaml cannot be parsed → **rc2**. Do not fall back to a grep over YAML; a regex that mis-parses a nested key would silently under-protect | — | — | — | — |

**Over-cap must not take down more than its own operation** — the one place it could: R1 runs at
SessionStart with `timeout: 20` (`hooks/hooks.json:79`). If the guard is slow (many worktrees ×
liveness subprocess), the *hook* is killed mid-loop. Because the destructive step now happens only
after rc1, a mid-loop kill leaves worktrees intact — a timeout degrades to "swept fewer", never to
"gutted one". This property is why the guard call must precede the `:90-93` mutation loop; it is
the single most important ordering constraint in this design.

---

## §4. COUNTEREXAMPLE — what still violates the invariant after every listed fix

Invariant: *a worktree belonging to a lane that is registered, running, or not yet terminal is
never removed or mutated by an automatic sweep.*

Four things still can, honestly:

1. **`branch -D` at `leadv2-worktree-cleanup.sh:244` and `:138` survives this design.** The guard
   gates whether R2/R3 *reach* the removal, but a lane that passes every one of P0–P4 (dead,
   old, unregistered, no arm, no terminal row) still gets its branch deleted, not just its
   checkout. If the merge-detection is ever wrong — and `lv2_branch_merged` uses
   `merge-base --is-ancestor`, which is correct for a *merged* branch but says nothing about a
   branch merged into a *different* base than `lv2_default_branch` resolved — the commits are gone
   from every path the plugin knows. Reflog only. **I am deliberately not changing `branch -D` in
   this task** (minimal diff, and it is load-bearing for the accumulation problem R2 was written
   to solve) but it is the largest residual and belongs in a follow-up.
2. **A lane that never registers anywhere.** A worktree created by hand, or by a dispatch that died
   between `worktree add` and `active.yaml` registration, has no `active.yaml` row, no handoff dir,
   and a dead liveness verdict. Only P1 (the 48h grace) protects it, and only for 48h. After that
   it is swept, correctly by this design's rules and possibly wrongly in fact. The grace window is
   the entire mitigation; that is why it defaults to 48 and not 6.
3. **Time-of-check / time-of-use.** The guard reads `active.yaml` and then the caller removes the
   worktree. A dispatch that registers a lane in that window (milliseconds, but SessionStart
   contends with `leadv2-active-cache.sh` and the dispatcher) is unprotected. `active.yaml` writes
   are lock-protected in `leadv2-active-registry.sh`, but the sweep does not hold that lock across
   its decision, and taking it would put a SessionStart hook in the dispatcher's critical path.
   Accepted; P1's grace window covers the realistic case (a *just*-created lane is by definition
   young).
4. **The orphan-monitor pgroup kill** (`leadv2-orphan-monitor-sweep.sh:28`), noted in §1. Not a
   worktree, so strictly outside the invariant, but the same "kill by inferred identity" shape.

What I checked to say that: every `worktree remove` / `worktree prune` / `rm -rf` on a worktree
path under `plugins/leadv2/` (grep, §1 table), every caller of both cleanup modes, `hooks.json`
registration, and the full body of the orphan-monitor hook.

---

## §5. Implementation shape (for the developer — no code here)

**New file** `plugins/leadv2/scripts/leadv2-worktree-protected.sh` — the §2 predicate. Standalone,
`set -uo pipefail`, no ERR-trap `exit 0` (this script's rc *is* its output). ~120 lines.

**`hooks/leadv2-merged-worktree-sweep.sh`:**
- insert the guard call after `:56`, before `:59`;
- on rc≠1: `continue`, and emit to stderr only when `LEADV2_SWEEP_DEBUG=1`;
- on rc1 and a successful `worktree remove` at `:95`: append
  `worktree_swept id=<basename> reason=merged-unregistered` via
  `leadv2-journal.sh append <id> note …`, guarded by `[[ -x ]]`;
- update the header block: `:16-22`'s safety claims are now stale, and `:21-22` is factually wrong
  about the sibling removers (F3) — correct it rather than leave a comment that will be believed.

**`scripts/leadv2-worktree-cleanup.sh`:** two guard insertions (§1 table) and a
`worktree_swept id=… reason=sweep-merged|sweep-dead` journal line beside each existing
`log_info "REMOVED …"` at `:137` and `:241`. `--name --force` untouched.

**Tests** — new `plugins/leadv2/scripts/tests/test-worktree-sweep-lane-safety.sh`, following
`test-merged-sweep-orchestration-dirt.sh`'s conventions exactly (mktemp scratch repo, `_mk` helper,
`PASS`/`FAIL` counters, `bash -n` case, `trap rm -rf`). Cases:
1. worktree id present in `active.yaml` (any state) → not swept;
2. `arm-registered` present, no terminal ledger row → not swept;
3. liveness verdict `live:*` → not swept;
4. mtime 1h old, `LEADV2_SWEEP_MIN_AGE_H=48` → not swept;
5. no `active.yaml` row, no handoff, mtime 100h, branch merged → **swept**, and the journal
   contains `worktree_swept id=<id>`;
6. `active.yaml` is corrupt YAML → **nothing swept**, and the truly-orphaned fixture from case 5
   also survives (proves fail-closed is repo-wide, not per-worktree);
7. sweeper run with cwd inside lane A → lane A survives **and its `docs/` files are still there**
   (the F2 regression: assert file content, not just directory existence);
8. `bash -n` on all three touched files.
Cases 5 and 7 are the ones that fail on the pre-fix tree; the others must be shown red-first by
pointing them at the `HEAD:` copy of the hook the way `test-merged-sweep-orchestration-dirt.sh:33-37`
already does.

**Docs:** `plugins/leadv2/docs/worktree-sweep-safety.md` (to-create) — one short section:
the three removers, the five protection signals, the fail-closed rule, and the
`LEADV2_SWEEP_MIN_AGE_H` knob. `single-lead-mode.md` **does not exist** in
`plugins/leadv2/docs/` (verified: the file there is `single-lead-pulse.md`, which has no worktree
section) — deliverable #5's conditional therefore resolves to "no such section", and the new doc
file plus the corrected hook header is the whole docs change.

### Constraint checklist
1. **Env naming** — `LEADV2_SWEEP_MIN_AGE_H`, `LEADV2_SWEEP_DEBUG`. `LEADV2_*`, consistent with
   `LEADV2_MERGED_WORKTREE_SWEEP`, `LEADV2_WORKTREE_DIR`. No `LEAD_V2_*` drift.
2. **Paths** — every path above verified on disk at `eb39d6f` except the three marked `(to-create)`.
   `plugins/leadv2/docs/single-lead-mode.md` verified **absent**.
3. **`claude -p`** — none introduced. N/A.
4. **Concurrent access** — `active.yaml` is read by the guard while
   `leadv2-active-registry.sh` may write it under its own lock. The guard is read-only and takes no
   lock (justification and residual in §4.3). The journal is append-only single-writer by design
   (`leadv2-journal.sh:8`) — safe.
5. **Config contradiction** — `LEADV2_SWEEP_MIN_AGE_H` and `LEADV2_SWEEP_DEBUG` grep clean across
   `plugins/leadv2/`; no existing usage to contradict.

---

## §6. Out of scope (implementer: ignore these)

- `leadv2-worktree-cleanup.sh --name --force` and its caller `leadv2-stale-sweeper.sh:332`.
- Removing or softening `branch -D` (§4.1) — follow-up task.
- `leadv2-orphan-monitor-sweep.sh` (§1, audited safe) and its pgroup-kill residual (§4.4).
- `leadv2-codex-lead.sh:390`, `leadv2-red-first-gate.sh:155` — self-created scratch trees.
- Any change to `hooks/hooks.json` ordering or timeout.
- The nested-lane-worktree problem (`leadv2-lane-worktree.sh:80-83`) — already fixed upstream.
- Anything outside `~/Projects/leadv2`.

---

```
acceptance:
  - surface: log_line
    observable: >
      At the start of a Claude session in ~/Projects/leadv2 that has a lane worktree
      belonging to a task listed in active.yaml, the session-start messages contain no
      line saying that lane was removed, and the lane's directory is still listed by
      `git worktree list` with its docs/ files intact afterwards.
    authored_at: 2026-08-24T09:30:00Z
  - surface: file_artifact
    observable: >
      After a genuinely abandoned lane worktree is swept, its task journal under
      docs/leadv2/tasks/<id>/journal.md contains a line reading
      "worktree_swept id=<id> reason=..." — so a founder asking "what happened to that
      worktree?" can read the answer instead of reconstructing it forensically.
    authored_at: 2026-08-24T09:30:00Z
  - surface: log_line
    observable: >
      With docs/leadv2/active.yaml deliberately corrupted, a session start reports that
      the worktree sweep was skipped, and every worktree that existed before the session
      still exists after it — including ones that would otherwise have been removed.
    authored_at: 2026-08-24T09:30:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-worktree-protected.sh, plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh, plugins/leadv2/scripts/leadv2-worktree-cleanup.sh, plugins/leadv2/scripts/tests/test-worktree-sweep-lane-safety.sh, plugins/leadv2/docs/worktree-sweep-safety.md

DELIVERABLE_COMPLETE
