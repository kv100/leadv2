# SWEEPER-LANE-SAFETY-01 — continuation prepass (mechanism-closed design)

TASK_ID: dispatch-c10b4c4e-architect · ROLE: architect · authored 2026-08-24T12:55:00Z
Lane under design: `.claude/worktrees/53b2ae6c` @ `cc938f4` (parent `8bd1758`).
Main meanwhile at `2e9b9ff` — **not** merged into the lane; lead owns that merge.

---

## 0. What the tree says vs. what the mission assumed

The mission guessed the remaining work is "most likely tests, the journal line, and the
orphan-monitor audit note". Read against `cc938f4`, two of those three are already done and
two items the mission did not name are open. Designing against the code, not the guess:

| Original deliverable | State in `cc938f4` | Remaining |
|---|---|---|
| D1 four-probe protection gate | done — `lib/leadv2-worktree-protected.sh` (278 L), consulted by hook:101 and cleanup:135/261 | age-probe source defect (§3.4) |
| D2 `worktree_swept id=… reason=…` journal on every sweep | done — hook:160-164, cleanup:40 | none |
| D3 tests for each protected state | file written — `tests/test-worktree-lane-safety.sh` P1–P10, both sweepers, red-first | **never registered in `run-core-offline.sh` `SUITE_DEFS` → "suites green" today does not run it at all** |
| D4 audit `leadv2-orphan-monitor-sweep.sh` | not done | **open** — verdict below is *safe, different kill-class*; note must be written |
| D5 docs | half — `docs/single-lead-pulse.md` gained a "Lane worktrees and the sweepers" section | **no hooks-level doc exists**; `plugins/leadv2/docs/` has no sweeper page |

Two corrections to the record `cc938f4`'s own commit message makes:

- Its census says the live callers of `--sweep-dead`/`--sweep-merged` are
  `leadv2-phase8-close.sh:611,618`. There is a **third**:
  `plugins/leadv2/scripts/leadv2-stale-sweeper.sh:399` runs `--sweep-dead` unattended.
  It is transitively protected (the gate lives inside `leadv2-worktree-cleanup.sh`), so this
  is a census error, not a hole — but it must be in the doc, because it is the *unattended*
  path a reader will not guess from phase-8 close.
- `docs/single-lead-mode.md` (D5) does not exist in this tree; the equivalent page is
  `plugins/leadv2/docs/single-lead-pulse.md`, which is where `cc938f4` correctly put it.

---

## 1. CALLERS / CALLEES

### 1.1 Callers of the gate (`lv2_wt_protect_prime` / `lv2_worktree_protected`)

| Caller | file:line | Path class | Notes |
|---|---|---|---|
| merged-sweep hook, prime | `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh:85` | SessionStart, **every** session incl. a freshly spawned lane child | registered `plugins/leadv2/hooks/hooks.json:76` |
| merged-sweep hook, probe | `…leadv2-merged-worktree-sweep.sh:101` | same | first gate, before `ahead`/dirt |
| cleanup `--sweep-dead`, prime | `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh:117` | CLI + unattended | |
| cleanup `--sweep-dead`, probe | `…leadv2-worktree-cleanup.sh:135` | same | before the liveness probe |
| cleanup `--sweep-merged`, prime | `…leadv2-worktree-cleanup.sh:229` | CLI + phase-8 | |
| cleanup `--sweep-merged`, probe | `…leadv2-worktree-cleanup.sh:261` | same | |
| stub fallback (lib absent) | hook:75-76, cleanup:23-24 | both | `lv2_worktree_protected(){ return 5; }` → sweeps nothing |

### 1.2 Callers of the sweepers themselves (independent paths — the "copy nobody named")

| Entry | file:line | Attended? | Gated by the lib? |
|---|---|---|---|
| SessionStart hook | `hooks/hooks.json:76` → hook | no | yes (hook:101) |
| Phase-8 close, merged | `leadv2-phase8-close.sh:611` | no | yes (cleanup:261) |
| Phase-8 close, dead | `leadv2-phase8-close.sh:618` | no | yes (cleanup:135) |
| **Stale sweeper** | `leadv2-stale-sweeper.sh:399` | no | yes (via cleanup) — **absent from `cc938f4`'s census** |
| Targeted reap | `leadv2-worktree-cleanup.sh --name` (phase-8 `--name`) | owner-driven | **no, by design** — an owner's explicit reap must always work |
| Stale sweeper's own orphan scan | `leadv2-stale-sweeper.sh:290-315` | no | **its own inline python re-implementation of "is this id in active.yaml"** — read-only, counts/reports, never removes. Not a kill path; is exactly the duplicated-rule shape `_MW_ORCH_RE` is this repo's cautionary tale about. Flag in the doc, do not refactor in this lane. |

### 1.3 Callees of the gate

`command -v python3` (lib:134) · `leadv2-state-path.sh --no-link active.yaml` (lib:145) and
`--no-link dispatch-ledger.jsonl` (lib:151) · embedded `_LV2_WT_PROTECT_PY` (lib:64-115:
`yaml.safe_load`, `os.kill(pid,0)`, per-line `json.loads` of the ledger) · `realpath`
(lib:179-180) · `stat -f %m` / `stat -c %Y` (lib:264) · `date +%s` (lib:269) · `grep -Fxq`
(lib:210). Sweep-side callees: `git worktree list --porcelain`, `git rev-list --count`,
`git status --porcelain`, `git worktree remove --force`, `git worktree prune`, and
`leadv2-journal.sh append <id> note` (hook:162, cleanup:40).

### 1.4 `leadv2-orphan-monitor-sweep.sh` — D4 audit verdict: **SAFE, different kill-class**

It is registered at `hooks/hooks.json:35` and touches **no worktree, no branch, no file**.
Its whole body (40 L) selects `ps` rows matching `/bin/zsh -c` **and** `codex-task.sh status`
with `etimes > 900`, then `kill -KILL -<pgid>`. It cannot gut or delete a lane worktree, so
the `cc938f4` gate is not applicable and adding it would be dead code.

It does carry a *different* residual hazard, which belongs in the audit note rather than in a
code change here: it kills the whole **process group**, and its only liveness criterion is
age >15 min. A `Monitor` loop legitimately watching a lane that runs longer than 15 minutes is
indistinguishable from an orphan by that rule, and killing the pgroup can reach siblings that
share it. Consequence in plain words: *a long-running lane can lose its watcher and the lead
stops being told when that lane finishes* — annoying, never destructive. Recommendation
recorded as a follow-up thread, **not** implemented in this lane (out of the mission's scope
and it would need its own red-first evidence).

---

## 2. STATES AND RETURN CODES

### 2.1 `lv2_worktree_protected` — every state, every rc, every consumer

| rc | `LV2_WT_PROTECT_REASON` | Entered when | merged-sweep hook does | cleanup `--sweep-*` does | User-visible consequence |
|---|---|---|---|---|---|
| 0 | `not-protected` | no session row, no open arm, no live pid, old enough (or age probe disabled) | falls through to `ahead`/orch-dirt gates (hook:117-167) | falls through to its liveness / merge-blocker / dirty gates | tree *may* be removed; if removed, one `worktree_swept id=… reason=merged-clean` journal line |
| 1 | `active_yaml` | id (bare or `dispatch-`) in `sessions[].task_id`, **or** `sessions[].worktree` realpath-equals this tree, any state | `continue`; one line to `/tmp/leadv2-sweep.log` (hook:105-107); no stderr | `continue`, same log line | lane survives; nothing on the founder's screen — this is steady state, correctly silent |
| 2 | `arm_open` | `docs/handoff/{,dispatch-}<id>/arm-registered` exists in main repo *or* in the tree, and no `landed`/`dead` ledger row for any id form | `continue` + log line | `continue` + log line | lane mid-round survives a merge-then-fix-round dip to `ahead=0` |
| 3 | `live_pid` | registered pid answers `kill -0` | `continue` + log line | `continue` + log line | a running worker's tree survives |
| 4 | `young` | dir mtime newer than `MIN_AGE_H*3600` | `continue` + log line | `continue` + log line | the **only** protection between `git worktree add` and the registration writes |
| 5 | `read-error:<what>` (`python3-absent`, `state-path-resolver-absent\|failed`, `active-yaml-missing`, `control-plane-unreadable`, `arm-registered-unreadable`, `worktree-stat-failed`, `lib-missing`) | any input unreadable | `continue`; **one** stderr line per pass (`_PROTECT_ERR_SHOWN`, hook:108-112) | same, per-mode flag | **nothing at all is swept this pass, repo-wide**; the founder sees exactly one `protected(read-error) … — sweeping nothing this pass` line. Trees accumulate until the control plane is readable again — the deliberate, correct direction |

`lv2_wt_protect_prime` returns 0 unconditionally (lib:137/142/146/149/155/165). It never
aborts a caller; every failure it can have is expressed as `LV2_WT_PROTECT_ERR` and surfaces
later as rc 5. This is why a broken `python3` degrades to "sweep nothing", not to "hook dies".

### 2.2 Terminal-outcome trace

- rc 5 reaching the SessionStart hook: `continue` for every worktree, then
  `git worktree prune`, then the summary `if` at hook:172 sees `REMOVED=KEPT_*=0` and prints
  nothing. Plain words: *the session starts normally, no worktree is touched, and the only
  evidence is one stderr line plus `/tmp/leadv2-sweep.log`.*
- rc 5 reaching `leadv2-stale-sweeper.sh:399`: cleanup prints `sweep-dead: 0 removed / N kept`,
  the sweeper logs it non-blockingly (`|| log "sweep-dead returned non-zero (non-blocking)"`)
  and continues. No loop retries; the next attempt is the next startup. Plain words: *stale
  lanes stay on disk until someone fixes `active.yaml`; nothing is lost.*
- rc 0 → `git worktree remove --force` failing (hook:165): counted as `(dirty)`, tree left
  **byte-identical** (that ordering fix is the b413968c cure) and reported in the advisory line.
- Journal write failure at hook:162 / cleanup:40 (`|| true`): the removal already happened and
  is not undone. Plain words: *a swept lane can, in the worst case, be swept silently again* —
  the exact forensic gap D2 exists to close, so the doc must say the journal is best-effort.

---

## 3. CONFIGURATION BOUNDARIES

### 3.1 `LEADV2_SWEEP_MIN_AGE_H` (lib:126-132)

| Input | Behaviour | Verdict |
|---|---|---|
| absent / empty | `48` | correct |
| `0` | age probe skipped entirely (lib:263) — probes A/B/C still run | intended kill-switch; see §5 |
| `1` … `2147483647` | honoured, hours | ok |
| non-numeric (`abc`, `-1`, `4.5`), or ≥2³¹ | degrades to `48` + **one** stderr line, pass continues | correct shape: a malformed env var must not take down every other worktree |
| whitespace / `48 ` | fails `^[0-9]+$` → degrades to 48 + warning | acceptable, noisy-but-safe |

### 3.2 `LEADV2_SWEEP_MIN_AGE_S` — main's `2e9b9ff`, **config contradiction**

`2e9b9ff` added an *independent* newborn guard inside the hook: `LEADV2_SWEEP_MIN_AGE_S`
(seconds, default `1800`), aged from `<common-git-dir>/worktrees/<name>/gitdir`. After the
lead's merge the hook will hold **two** age guards with two names, two units, two defaults and
two age sources. Boundary consequences of leaving both:

- `LEADV2_SWEEP_MIN_AGE_H=0` (which `cc938f4` sets in
  `tests/test-leadv2-worktree-sweep.sh` and `tests/test-lane-worktree-isolation.sh` to
  de-protect their fixtures) no longer disables all age protection — the 1800 s guard still
  fires. **Those two suites will go red on the merge commit unless they also set
  `LEADV2_SWEEP_MIN_AGE_S=0`.** This is the single most likely merge breakage and the lead
  should be told before, not after, the merge.
- Conversely `LEADV2_SWEEP_MIN_AGE_S=0` alone does not de-protect: the 48 h lib guard remains.
- Two names for one concept is the `_MW_ORCH_RE` failure shape at the config layer.

**Design decision (lane-side, non-conflicting):** the *lib* becomes the single owner of the age
probe. Precedence, documented at the top of the lib and in the new doc page:
`LEADV2_SWEEP_MIN_AGE_S` (seconds) wins if set and numeric; else `LEADV2_SWEEP_MIN_AGE_H*3600`;
else `48*3600`. Both accepted forever — no rename, no breakage. The lane does **not** touch the
hook file (merge-owned); removing the hook's now-redundant inline block is the lead's merge
step, spelled out in §6.

### 3.3 `active.yaml` (via `leadv2-state-path.sh --no-link`)

| State | Behaviour | Verdict |
|---|---|---|
| resolver missing / fails | `state-path-resolver-*` → rc 5 everywhere | fail-closed, correct |
| path empty or file absent | `active-yaml-missing` → rc 5 | correct — "a missing registry is indistinguishable from a broken one" |
| empty file (`yaml.safe_load` → `None`) | not a dict → py exit 3 → rc 5 | fail-closed. Note the cost: an **empty** registry (legitimate: no lanes) protects everything, so a genuinely idle repo never GCs. Acceptable; must be stated in the doc so nobody "fixes" it |
| `sessions:` absent or `null` | `.get("sessions") or []` → zero rows → rc 0 path | ok |
| row without `task_id` | skipped (lib:82) | ok |
| malformed YAML | `yaml.safe_load` raises → non-zero → `control-plane-unreadable` → rc 5 | correct |
| **torn write** that still parses (truncated `sessions` list) | parses clean, registered lane missing → **rc 0** | residual risk, §4 |
| very large (10⁴ rows) | read once per pass (`prime`), then a bash `while read` per worktree → O(worktrees × rows) in-process, no re-read, no I/O | acceptable; no per-worktree file read |
| `pid` `null`/`""`/`"None"`/non-int | `alive=0`, row still counts for probe A | correct |

### 3.4 Worktree age source — **defect, lane-side fix**

`lib:264` stats the **worktree directory itself**. That mtime is not creation-stamped: it moves
whenever a top-level entry is created or removed in the tree. `2e9b9ff` documents the
empirically-verified alternative — `<common-git-dir>/worktrees/<name>/gitdir`, written once by
`git worktree add` and never rewritten (`git status`/`git commit` inside the tree leave it
untouched). Consequences of the current source: a lane can look *younger* than it is (any
top-level churn resets the window, so a long-dead tree stays protected — safe direction), and,
where the directory was created by a copy/restore rather than by `git worktree add`, the mtime
can be *older* than the lane (unsafe direction). Fix: prefer `gitdir` mtime, fall back to the
directory mtime, and only then rc 5. Same rc contract, one probe.

### 3.5 Ledger (`dispatch-ledger.jsonl`)

Absent → not an error, no terminal rows → an arm-registered lane counts open (correct
direction, lib:94). Present but unopenable → py exit 3 → rc 5. Non-JSON line → skipped, pass
survives (lib:107). `terminal` other than `landed`/`dead` (e.g. `arm_produced_nothing`) → not a
terminal → lane stays protected — deliberately the same two-word set as
`leadv2-dispatch-ledger.sh`'s `dispatch_terminal_exists`. Huge ledger → one sequential read per
pass.

### 3.6 `arm-registered` marker

Absent → probe B says "no open arm". Present-and-readable → open unless a terminal exists.
Present-but-unreadable → rc 5 (fail closed). Present as a **directory** → `-e` true, `-r` true
→ treated as a marker; content never parsed, so this is harmless by construction. Empty file →
still a marker: presence is the signal (lib:218-220).

### 3.7 `LEADV2_MERGED_WORKTREE_SWEEP`

`0` → hook exits 0 at line 49 before anything, including before the gate. Any other value
(incl. malformed) → enabled. One-step rollback, correct.

---

## 4. COUNTEREXAMPLE — what still violates "a registered or in-flight lane is never destroyed"

Four things survive every fix in this design, and the honest answer is *not* "nothing".

**(a) The `docs/handoff/` force-discard.** `_MW_ORCH_RE` (hook:132) classifies
`docs/handoff/**` as the plugin's own regenerated bookkeeping, and hook:155 then runs
`git worktree remove --force`, which discards it. But `docs/handoff/<task>/` is precisely where
every subagent writes its `*.full.md` deliverable. A lane that merged, is `ahead=0`, whose
protection has lapsed (terminal recorded, no session row, older than the window), and which
holds an **uncommitted** deliverable, loses that deliverable — no journal of the content, only
`worktree_swept … reason=merged-clean`. This is a genuine remaining data-loss path, unrelated
to the four probes, and it is in a file this lane must not touch (merge-owned). Escalated as a
follow-up thread, not fixed here.

**(b) The registration window.** Between `git worktree add` and the `active.yaml` /
`arm-registered` writes, probes A/B/C are all blind; only the age probe stands. Anything that
sets the age threshold to `0` — a test fixture leaking its env, an operator export — reopens
the exact 43ae4318 hole. §5 turns this into an assertion rather than a comment.

**(c) A torn-but-parseable `active.yaml`.** The gate reads without taking the writers' lock
(deliberately — blocking SessionStart on a lane's write lock is worse). A truncation that still
yields valid YAML loses rows silently and returns rc 0 for a registered lane. Mitigated in
practice by probes B/C/D, unmitigated in principle; the honest fix is an atomic
write-and-rename on the writer side, which is out of this mission's scope.

**(d) `--name` mode is ungated by design.** Correct for an owner's explicit reap, and it means
any caller that computes the wrong lane id destroys a live lane with every guard bypassed.

Checked and found clean: the branch is never deleted by either sweeper (`worktree remove`
only), so even a wrong call costs a `git worktree add`, never a commit; `leadv2-stale-sweeper`
never removes anything itself; `leadv2-orphan-monitor-sweep.sh` touches no filesystem path.

---

## 5. Changes to implement

**C1 — register the test suite (highest value; without it D3 is inert).**
`plugins/leadv2/scripts/tests/run-core-offline.sh` `SUITE_DEFS`: add
`"lane worktrees survive the sweepers (SWEEPER-LANE-SAFETY-01)|||bash $TEST_DIR/test-worktree-lane-safety.sh|||SERIAL"`.
`SERIAL` because the suite reads pre-fix binaries out of the real repo's git history and creates
worktrees; it must not race a sharded parallel run.

**C2 — age source, in the lib only.** `lib/leadv2-worktree-protected.sh`: probe D stats
`$(git -C "$wt" rev-parse --git-dir)/gitdir` first, falls back to the worktree dir mtime, and
only then returns rc 5 `worktree-stat-failed`. Same rc, same reason strings.

**C3 — age precedence, in the lib only.** `lv2_wt_protect_prime` accepts
`LEADV2_SWEEP_MIN_AGE_S` (seconds) in preference to `LEADV2_SWEEP_MIN_AGE_H` (hours); same
degrade-with-one-warning treatment for a malformed value; internal threshold becomes seconds.
Document both names in the lib header.

**C4 — two new cases in `tests/test-worktree-lane-safety.sh`:**
`P11-age-from-gitdir-not-dirmtime` — back-date `gitdir`, touch the worktree dir now, assert the
lane is **swept** (the dir mtime must not resurrect a dead lane); and
`P12-min-age-s-precedence` — `LEADV2_SWEEP_MIN_AGE_H=0 LEADV2_SWEEP_MIN_AGE_S=3600` on a
5-minute-old orphan asserts **kept**. Both against both sweepers, following the existing
`run_case`/`kind` harness.

**C5 — D4 audit note.** A comment block at the head of
`plugins/leadv2/hooks/leadv2-orphan-monitor-sweep.sh` recording: audited under
SWEEPER-LANE-SAFETY-01 on 2026-08-24; touches no worktree/branch/file, therefore the
protection gate is not applicable; the residual pgroup-kill hazard and that it is tracked
separately. No behaviour change.

**C6 — D5 hooks doc.** New `plugins/leadv2/docs/worktree-sweepers.md` (~40 lines): the three
sweeper entry points *including* `leadv2-stale-sweeper.sh:399`, the four probes and their rc
contract, fail-closed semantics, both env var names with units and defaults, the "empty
registry protects everything" consequence, the best-effort journal line, and the two known
residual risks (a) and (d) from §4. Link it from `docs/single-lead-pulse.md`'s existing
"Lane worktrees and the sweepers" section (one line).

**Then:** `bash -n` over every touched `.sh`, `bash run-core-offline.sh` green, commit on the
lane branch.

---

## 6. Merge contract for the lead (NOT done in this lane)

1. Take **main's** hook body for the newborn guard, then delete its inline
   `LEADV2_SWEEP_MIN_AGE_S` block (hook lines added by `2e9b9ff`) — after C2/C3 the lib's probe
   D covers it with the same source and the same env var, and keeping both means two rules in
   two hand-edited files.
2. Keep main's `KEPT_YOUNG` counter and its distinct advisory reason; feed it from the gate's
   rc 4 instead of from the deleted inline block.
3. Re-run `tests/test-merged-sweep-orchestration-dirt.sh` (touched by both sides) and the two
   suites `cc938f4` gave `LEADV2_SWEEP_MIN_AGE_H=0` — see §3.2, they are the expected red.

---

## 7. Non-goals

- No rebase/merge of `2e9b9ff` in this lane; no edit to
  `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh` at all (merge-owned).
- No behaviour change to `leadv2-orphan-monitor-sweep.sh` (comment only) and no fix for its
  pgroup-kill hazard.
- No narrowing of `_MW_ORCH_RE` / no fix for counterexample (a) — separate thread.
- No atomic-write change to the `active.yaml` writer — counterexample (c) stays open.
- No gate on `--name` mode — deliberate.
- No refactor of `leadv2-stale-sweeper.sh`'s inline active.yaml reader.
- No new lock acquisition in the gate.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: "In a repo whose active.yaml lists lane X, a new session starts and the
      lane directory .claude/worktrees/X is still on disk afterwards, with a line naming X
      as protected in /tmp/leadv2-sweep.log and nothing about X in the session's startup
      output."
    authored_at: 2026-08-24T12:55:00Z
  - surface: log_line
    observable: "After a genuinely abandoned lane is removed, its task journal contains a
      worktree_swept entry naming that lane id and the reason it was swept — a human
      reading the journal can say which lane disappeared and why, without git forensics."
    authored_at: 2026-08-24T12:55:00Z
  - surface: log_line
    observable: "With the registry file corrupted, the session start prints exactly one
      line saying nothing is being swept this pass, and every worktree present before the
      session is still present after it."
    authored_at: 2026-08-24T12:55:00Z
  - surface: file_artifact
    observable: "plugins/leadv2/docs/worktree-sweepers.md exists and names all three
      unattended entry points, both age env vars with their units and defaults, and the
      two known residual risks; the single-lead-pulse worktree section points at it."
    authored_at: 2026-08-24T12:55:00Z
  - surface: file_artifact
    observable: "The head of leadv2-orphan-monitor-sweep.sh carries a dated audit note
      stating it touches no worktree and why the lane-protection gate does not apply."
    authored_at: 2026-08-24T12:55:00Z
  - surface: log_line
    observable: "A full offline test run lists a lane-worktree-safety suite among the
      suites it executed and reports it passing — today that suite is absent from the run."
    authored_at: 2026-08-24T12:55:00Z
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh, plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/hooks/leadv2-orphan-monitor-sweep.sh, plugins/leadv2/docs/worktree-sweepers.md, plugins/leadv2/docs/single-lead-pulse.md

DELIVERABLE_COMPLETE
