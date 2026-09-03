# PLUGIN-CORE-OFFLINE-4RED-01 — ROUND 3 FINISHER — implementation design

Role: architect prepass. No implementation performed.
Lane: `e2e9d9b2` → worktree `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e2e9d9b2`
(branch `worktree-e2e9d9b2`, base `85ae886`).

---

## 0. Ground truth established (facts, not assumptions)

| Fact | Evidence |
|---|---|
| Lane work is **uncommitted in the lane worktree**, not in the main checkout | `git -C .claude/worktrees/e2e9d9b2 status --short` → 7 modified files under `plugins/leadv2/scripts/tests/**`, +463/−91 |
| Main checkout `plugins/` is **clean** | `git status --short -- plugins/` → empty |
| The r2 hermetization (env scrub, per-suite `TMPDIR`, `SUITE_DEFS`, `LEADV2_CORE_OFFLINE_HERMETIC_GATE`, `_CORE_OFFLINE_OWNED_SUITES`) exists **only in the worktree copy** of `run-core-offline.sh` (12187 B) — main `HEAD` copy (7831 B) has none of it | `diff <(git show HEAD:…) <worktree file>` |
| `"supervisor reconciliation"` is **already listed in `_CORE_OFFLINE_OWNED_SUITES`** | worktree `run-core-offline.sh` ~L92 |
| Lane base for this file is `a8964fd`; **main has since moved to `6b79c2c`**, which also edits `run-core-offline.sh` | `git log --oneline -- run-core-offline.sh` in both trees |
| `test-supervise-v2.sh` (898 lines) **already** isolates via `lv2_mktemp_dir` + `LEADV2_PROJECT_ROOT` / `LEADV2_STATE_ROOT` / `PROJECT_ROOT` / `CLAUDE_PROJECT_DIR` / `LEADV2_SUPERVISE_TMUX_SOCKET` | grep of the suite |
| Reported RUN1 = **49 pass / 1 fail = 50 counted**, RUN2 = 50/0 | mission, lead-run |

**Arithmetic consequence (do not skip this).** `run_check` increments `FAIL` in *two* independent
places: the suite's own non-zero exit, **and** the hermetic post-condition when a lane-owned suite
dirties `docs/leadv2`. A hermetic violation on a *passing* owned suite would have produced
`PASS=50, FAIL=1` (51 counted). The lead observed `49/1` (50 counted). Therefore RUN1's failure was
the **suite's own non-zero exit**, not the hermetic gate. That narrows the hunt — but see Risk R4:
the double-count is still a latent defect that will misreport a future run.

---

## 1. Scope

**In scope (exactly two deliverables):**
- A. Make `"supervisor reconciliation"` (`test-supervise-v2.sh`) order- and state-independent inside
  the full runner, without weakening any assertion; falsify the fix.
- B. Commit r1+r2+r3 on `worktree-e2e9d9b2` with a diff containing **only**
  `plugins/leadv2/scripts/tests/**`.

**Explicit non-goals — the implementing agent ignores these:**
- Any edit under `plugins/leadv2/scripts/*.sh` outside `tests/` (engine code: `supervise.sh`,
  `supervise-loop.sh`, `state-path.sh`). If the flake's true cause is an engine bug, the fix is a
  **test-side isolation of the surface it touches**, not an engine edit; if that is impossible,
  STOP and report — do not edit engine code.
- Re-hermetizing the 4 suites already fixed in r2. They are green; leave them alone.
- Merging `worktree-e2e9d9b2` into `main`, or rebasing onto `6b79c2c`. Commit only. (See R1.)
- Any `docs/leadv2/**` or `docs/handoff/**` content in the commit.
- Suite-count changes: 50 suites in, 50 suites out.

---

## 2. Part A — hermetizing the reconciliation suite

### 2.1 Diagnosis before edit (mandatory, ~5 min, cheap)

The suite passes standalone twice and fails on the *first* full-runner pass. Three surfaces can
carry state across suites inside one runner invocation; r2's scrub covers only the first.

| # | Shared surface | Covered by r2? | Why it can flip RUN1→RUN2 |
|---|---|---|---|
| S1 | Inherited env (`LEADV2_*`, `CLAUDE_*`, `GIT_*`, `DRY_RUN`) | **yes** (`_CORE_OFFLINE_SCRUB_ARGS`) | — |
| S2 | Real `$HOME` state tree — `~/.claude/cache/**`, and the **repo-relative `.claude/cache/`** dir (untracked, present as `??` in both trees today) | **no** | First full run *creates* the dir as a side effect of an earlier suite; a suite that reads-before-create is red on run 1, green on run 2. This is the single best match for "fails first pass, passes second". |
| S3 | The live **tmux server** and its sockets | **no** | `test-supervise-v2.sh` reconciliation asserts on prune/`would_prune` decisions derived from live panes. Suites earlier in `SUITE_DEFS` (`autonomous session spawner`, `supervisor/lead PID isolation`, `Codex full-cycle runner`) can leave a tmux server or `leadv2-*` sessions alive on a socket that outlives them. Run 1 sees them; by run 2 they are reaped. `LEADV2_SUPERVISE_TMUX_SOCKET` is set per-*test-case* inside the suite, but a **default-socket** server started by an earlier suite is still reachable by any code path that does not pass `-S`. |
| S4 | Wall-clock cadence | n/a | Cases seed `last_pulse_at: "2020-01-01…"` (deliberately stale) and one uses `now`. A cadence/ceiling assertion evaluated near a second boundary can flip. Lowest prior — a fresh run and a repeat run are equally exposed, which does not match "first pass only". |

**Protocol (do this, in order, before touching a line):**
1. Re-run the full runner from a clean shell and **capture the failing suite's stderr verbatim** —
   `bash plugins/leadv2/scripts/tests/run-core-offline.sh 2>&1 | tee /tmp/run1.log`. Name the
   failing test case number/message. Do not theorize past the actual message.
2. Confirm the failure is reproducible as a *prefix* problem, not a whole-run problem, with the
   cheapest bisect available: `LEADV2_CORE_OFFLINE_REVERSE=1` (r2 already built this in). If the
   suite is green in reverse order, the poisoning suite is one that runs *before* it forward and
   *after* it reversed — that is your candidate set, already halved.
3. Narrow to one predecessor by running `SUITE_DEFS[0..k]` + the target, bisecting on `k`. If the
   runner has no such flag, drive it with a temporary local loop — **do not add a new permanent
   flag to `run-core-offline.sh` for this**; delete the scaffold before commit.
4. Only then classify the leak as S2 / S3 / S4 and fix it.

### 2.2 Fix pattern (match r2's shape — do not invent a new one)

Whatever surface it turns out to be, isolate it the way the other four fixes do: **give the suite
its own root and point every consumer of that surface at it**, inside `test-supervise-v2.sh`
(preferred) rather than in the runner.

- **S2 →** at suite top, allocate `TMP_ROOT="$(lv2_mktemp_dir "sv2-root")"`, export
  `HOME="$TMP_ROOT/home"`, `XDG_CACHE_HOME="$TMP_ROOT/cache"`, and **pre-create** every directory
  the suite's subject reads before writing (`$HOME/.claude/cache`, the `$repo/.claude/cache`
  equivalent, state root). Pre-creating a directory is not an assertion weakening — it is stating a
  precondition the suite was silently inheriting from a predecessor.
- **S3 →** give the suite a private tmux socket for its *entire* lifetime, not per-case:
  `LEADV2_SUPERVISE_TMUX_SOCKET="$TMP_ROOT/tmux.sock"` exported at suite top (per-case sockets
  still override it), plus an `EXIT` trap that runs `tmux -S "$sock" kill-server 2>/dev/null || true`
  for every socket the suite created. Leaving a server alive is how *this* suite poisons the next
  one.
- **S4 →** pin the clock input the assertion depends on through the existing env override if one
  exists; if it does not, **do not** widen the tolerance — report as blocked instead.

### 2.3 Non-negotiables for the fix

- **Never weaken an assertion.** Forbidden: raising a tolerance, deleting a case, converting `fail`
  to a warning, `|| true` on a subject invocation, shrinking an expected set. Adding a
  precondition (`mkdir -p`) or redirecting a path to a private root is allowed and is the whole point.
- **Falsify.** After the fix, break the guarded path (e.g. flip one prune decision in the subject,
  or seed the private root with the state the suite must reject) and show the suite goes **RED**;
  restore, show GREEN. Paste both in the deliverable. A fix that cannot be made to fail did not
  test anything.
- `bash -n` + `shellcheck` on every touched file.

---

## 3. Part B — the commit

Lane branch: `worktree-e2e9d9b2`. Work happens in the worktree, not the main checkout.

**Allowed paths in the commit — nothing else:**
```
plugins/leadv2/scripts/tests/run-core-offline.sh
plugins/leadv2/scripts/tests/test-supervise-v2.sh
plugins/leadv2/scripts/tests/test-codex-session-runner.sh
plugins/leadv2/scripts/tests/test-drift-guard-quarantine-perimeter.sh
plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh
plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh
plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh
plugins/leadv2/scripts/tests/fixtures/pe_run_cache_sync.sh
```

**Staging discipline:**
1. `git -C <worktree> add -- plugins/leadv2/scripts/tests/` — **path-scoped add only**. Never
   `git add -A`, never `git add .`; both would sweep in the 19 dirtied `docs/leadv2` +
   `docs/handoff` entries the r1 review flagged as MEDIUM-1.
2. `git -C <worktree> diff --cached --name-only` and **eyeball it against the list above**. Any
   path outside `plugins/leadv2/scripts/tests/` → `git restore --staged` it.
3. Per global rule: **re-diff immediately before staging** — a parallel session in a shared tree
   can revert an edit between your write and your `add`.
4. Commit. Report the sha.
5. `git status --short` after the two acceptance runs must show **nothing modified under
   `plugins/**`**. Modified/untracked `docs/leadv2/**` and `docs/handoff/**` may remain — they are
   pre-existing lane residue and are explicitly out of the commit; say so rather than cleaning them.

Suggested message shape (repo convention):
`fix(tests): PLUGIN-CORE-OFFLINE-4RED-01 — hermetize core-offline runner (env scrub, per-suite TMPDIR, hermetic post-condition) + reconciliation suite isolation; 50/0 twice`

---

## 4. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **Divergence from `main`.** Lane base for `run-core-offline.sh` is `a8964fd`; `main` is at `6b79c2c`, which independently edited the same file (registering the REVIEW-ROUND1-EXHAUSTIVE suite). The lane *restructured* the flat `run_check` list into `SUITE_DEFS`, so the eventual merge is a **structural conflict**, and the naive resolution silently **drops the suite `main` added**. | HIGH | Do **not** rebase in this task (out of scope, and it would invalidate the two acceptance runs). Instead: (a) commit as-is; (b) in the deliverable, state explicitly that `main@6b79c2c` added a suite to this file which is absent from the lane's `SUITE_DEFS`, and that whoever merges must re-add it and expect 51, not 50. Do not let this be discovered at merge time. |
| R2 | **Fixing the symptom, not the cause.** Adding `mkdir -p` / a private socket may make RUN1 green while the real leak (an engine path writing outside its state root) survives and re-emerges elsewhere. | HIGH | The §2.1 bisect names the *predecessor* suite. If the predecessor is leaking because the engine writes outside `LEADV2_STATE_ROOT`, record that as a follow-up thread with the exact path — engine edits are off_limits here, but the finding must not evaporate. |
| R3 | **Assertion drift under time pressure.** Two failed rounds create pressure to relax a check to reach 50/0. | HIGH | The falsification step in §2.3 is the guard: a weakened assertion cannot be made RED by breaking the guarded path. Reviewer checks the RED transcript, not the GREEN one. |
| R4 | **`run_check` double-counts.** A lane-owned suite that both passes and dirties `docs/leadv2` yields `PASS+1, FAIL+1` → 51 counted, and "50/0" becomes unreachable for reasons unrelated to any assertion. | MEDIUM | Not the cause of RUN1 (see §0 arithmetic), so **do not fix it in this lane** — but note it in the deliverable as a follow-up: the hermetic violation should replace the pass, not add a fail. |
| R5 | **Concurrent sessions dirty `docs/leadv2` mid-run.** The hermetic post-condition reads `git status --porcelain -- docs/leadv2` from `REPO_ROOT`. In a machine running many `/leadv2` sessions against sibling worktrees, another session writing `bus.jsonl`/`active.yaml` during the target suite's window trips a **FAIL on an owned suite with no defect present** — a genuine, unrelated flake source for the acceptance runs themselves. | MEDIUM | Run both acceptance runs from a quiet shell. If a `HERMETIC-VIOLATION (FAIL, lane-owned)` line appears in either run's output, do **not** silently re-run — quote it and state which suite and which paths, then re-run. |
| R6 | **`SUITE_DEFS` space-splitting.** Records are space-split (`"name\|\|\|cmd..."`), so any path containing a space silently mis-executes. `RUN_TMP`/per-suite `TMPDIR` derive from `${TMPDIR:-/tmp}`, which on macOS is `/var/folders/…` (space-free) but is operator-settable. | LOW | Out of scope to fix. Mention in the deliverable only if a run actually trips it. |
| R7 | **`RUN_TMP` trap vs `set -e`.** `trap 'rm -rf "$RUN_TMP"' EXIT` fires on every exit path including the falsification RED run — expected, but confirm the trap does not remove a directory the falsification evidence points at. | LOW | Copy any evidence out of `$RUN_TMP` before the run exits. |

## 5. Mandatory constraint checklist

1. **Env var naming** — every var this lane introduces or reads is `LEADV2_*`
   (`LEADV2_CORE_OFFLINE_HERMETIC_GATE`, `LEADV2_CORE_OFFLINE_NO_SCRUB`,
   `LEADV2_CORE_OFFLINE_REVERSE`, `LEADV2_SUPERVISE_*`). No `LEAD_V2_*` drift observed. Any new
   var in §2.2 **must** keep the `LEADV2_` prefix. PASS.
2. **File paths** — all eight commit paths verified present in the lane worktree. PASS.
3. **`claude -p`** — no `claude -p` invocation in scope. N/A.
4. **Concurrent access** — recorded as R5 (hermetic gate reads a repo-wide `git status` that
   parallel sessions mutate) and in the staging discipline (re-diff before `git add`). PASS.
5. **Config contradiction** — no new env semantics introduced by this design; §2.2 additions
   (`HOME`, `XDG_CACHE_HOME`, `LEADV2_SUPERVISE_TMUX_SOCKET`) reuse existing, already-honoured
   overrides rather than defining new contracts. PASS.

---

## 6. acceptance

```yaml
acceptance:
  authored_at: 2026-08-19T00:00:00Z
  items:
    - surface: log_line
      observable: >
        Two consecutive full runs of run-core-offline.sh, launched back-to-back from a clean
        shell, each end with a summary line reading 50 passed / 0 failed / 0 missing, and neither
        run's output contains a line beginning "[CORE-OFFLINE] FAILED:" or
        "HERMETIC-VIOLATION (FAIL, lane-owned)". Both runs' raw tails are pasted in the deliverable.
    - surface: log_line
      observable: >
        A falsification transcript in the deliverable shows the "supervisor reconciliation" suite
        printing a FAIL line for the reconciliation case when the guarded path is deliberately
        broken, and the same suite printing its pass lines with the break reverted.
    - surface: file_artifact
      observable: >
        `git status --short` run after both acceptance runs lists no modified or untracked path
        under plugins/ — a human reading it sees only pre-existing docs/leadv2 and docs/handoff
        entries.
    - surface: log_line
      observable: >
        A commit sha on branch worktree-e2e9d9b2 appears in the deliverable, and
        `git show --stat <sha>` lists only paths under plugins/leadv2/scripts/tests/ — no
        docs/leadv2 and no docs/handoff file appears in that stat.
```

LANE_WRITES: plugins/leadv2/scripts/tests/test-supervise-v2.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/fixtures/**

DELIVERABLE_COMPLETE
