# CORE-OFFLINE-WORKTREE-GAP-01 — architect prepass (mechanism-closed)

Repo: `~/Projects/leadv2` @ b82b208. Design only; no implementation here.

## 0. Discovery vs mission framing — three corrections

**C-1 (partially-done work already in the tree).** The mission is written as if
nothing is fixed. `git diff` shows a prior arm already landed the sibling-first
resolution in **both** `leadv2-fanout.sh:49-59` and
`leadv2-fanout-lane-launcher.sh:82-92`, plus the fixture staging + a new Test 5 in
`tests/test-fanout-classify-guard.sh`. The implementing lane must **review and keep**
that WIP, not re-derive it. What is NOT done: the ladder test, and cleanup of debug
scaffolding.

**C-2 (debug scaffolding is in the tree and must be removed).** Three uncommitted
debug prints exist and would ship if the lane commits blind:
- `leadv2-dispatch-code.sh:5420` — `printf 'DEBUG-LOOP candidate=… arc=…'` to stderr,
  **inside the per-candidate dispatch loop of the production dispatcher**.
- `leadv2-dispatch-code.sh:5486` — `printf 'DEBUG-LADDER …'` to stderr.
- `tests/test-glm-deferred-ladder.sh:148,150` — `DEBUG-OUT-AB` / `DEBUG-EXC-DIR` dumps.
These are not part of the fix. Removing them is in scope.

**C-3 (there is an unresolved merge conflict).**
`git status` reports `UU plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh`.
A file with conflict markers is `bash -n`-red; if that test is in any suite the lane runs,
the run is red for a reason unrelated to this task. Resolve or `git checkout --theirs/--ours`
it before proof, and say which in the summary.

**C-4 (the mission's ladder hypothesis is right but under-specified).** The mission asks
"if it has the same env leak (reads live quota/burn state)". It does — but the leak is
narrower and more dangerous than "reads state": see §1/§3 below. `LEADV2_BURN_GOVERNOR=0`
is already set at line 27, so burn is *not* the leak. The leak is the **GLM quota gate +
un-stubbed GLM binary on the `glm-deferred --retry-all` legs**.

---

## 1. CALLERS / CALLEES

### 1a. The registry-resolution mechanism (deliverable 1)

`leadv2-active-registry.sh` is `source`d — a *sourced* dependency, so a miss is a hard
`set -e` abort of the sourcing script, not a recoverable error. Two independent copies of
the two-step resolution idiom existed; both are on the fanout path but only one is named
in the mission.

| Site | file:line | Reached from | Named in mission? |
|---|---|---|---|
| fanout dispatcher | `plugins/leadv2/scripts/leadv2-fanout.sh:53-59` | founder `/leadv2 fanout`, `test-fanout-classify-guard.sh` | yes |
| **lane launcher** | `plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:82-92` | spawned per-lane by fanout's tmux/window/headless backends — a **different process, different cwd, inside the lane worktree** | **no — this is the independent copy** |
| dispatcher (registry consumer) | `leadv2-dispatch-code.sh:4876` (`source "${SCRIPT_DIR}/leadv2-active-registry.sh"`) | every dispatch | already sibling-only; **safe, no change** |

Callees of the resolved helper: `leadv2_active_update_phase`, and the registry's own
`leadv2-state-path.sh` lookup. Neither changes.

Prereq check: both files define `SCRIPT_DIR` **before** the new block
(`leadv2-fanout.sh:41`, `leadv2-fanout-lane-launcher.sh:42`) and
`leadv2-fanout-lane-launcher.sh` defines `log_error` before line 82. Verified.

### 1b. The ladder mechanism (deliverable 2)

`tests/test-glm-deferred-ladder.sh` invokes `leadv2-dispatch-code.sh` at
lines 147, 172, 181, 224, 348, 448, 462, 463, 495, 496, 535, 536, and
`leadv2-broad-status.sh` at 294, 314.

Callee chain that leaks:
`leadv2-dispatch-code.sh` → `leadv2-router-v2.sh:68` →
`GLM_QUOTA_GATE="${LEADV2_GLM_QUOTA_GATE:-${SCRIPT_DIR}/leadv2-glm-quota-gate.sh}"` →
`leadv2-glm-quota-gate.sh:37` `LIVE="${LEADV2_QUOTA_LIVE:-${SCRIPT_DIR}/leadv2-quota-live.sh}"`
→ live provider HTTP + `${HOME}/.claude/state/leadv2/quota-cache`
(`leadv2-provider-quota-gate.sh:47`).

The test stubs `LEADV2_ROUTER_V2_BIN` on the legs at 144/219/345/493/533 — those legs are
hermetic. It does **not** stub it on the `glm-deferred --retry-all` / `--list` legs at
**448, 450, 462, 463** (and 172/181). Those legs therefore reach the real router-v2, the
real GLM quota gate, and the real network. Same legs also omit
`LEADV2_DISPATCH_GLM_BIN`, so a *successful* gate can spawn a **real GLM worker** —
the `duplicate-caller-race` escape already recorded in
`docs/leadv2/open-threads.md` and `plugins/leadv2/docs/test-escape-duplicate-caller-race.md`.

**Consequence in plain words:** on a host whose GLM quota happens to be healthy, running
the core-offline suite dispatches a real paid GLM coding worker against a fixture mission,
and that worker can commit to `main`. On a host whose quota is exhausted or whose network
is slow, the same legs behave differently and the test is red — which is what lane
`6321b955` saw. Same root cause, two symptoms.

---

## 2. STATES AND RETURN CODES

### 2a. Registry resolution (both fanout sites, post-fix)

| # | State | Resolved path | rc | What the caller does | User-visible consequence |
|---|---|---|---|---|---|
| S1 | sibling present (canonical checkout, lane worktree, plugin cache) | `${SCRIPT_DIR}/leadv2-active-registry.sh` | source ok | proceeds | fanout/lane launches normally |
| S2 | sibling absent, repo-vendored symlink farm present (legacy main checkout) | `${PROJECT_ROOT}/.claude/scripts/…` | source ok | proceeds | unchanged legacy behaviour |
| S3 | S1+S2 absent, `LEADV2_CANONICAL_ROOT` (or `~/Projects/leadv2`) has it | canonical | source ok | proceeds | works from a foreign repo |
| S4 | S1–S3 absent, shared tree present | `~/.claude/leadv2-shared/scripts/…` | source ok | proceeds | pre-existing fallback preserved |
| S5 | **all four absent** | — | **exit 1** with `[fanout] ERROR: … refusing to launch` | fanout aborts before any lane spawns; lane launcher aborts that one lane | founder sees one explicit error line instead of `source: No such file or directory` and a `set -e` abort with no explanation. **No lane is launched** — fail-closed, matching fanout's stated "any doubt about session accounting refuses to launch". |
| S6 | path exists but is **empty** (0 bytes — a broken/truncated symlink target) | — | `[[ -s ]]` is false → falls through to the next tier | as S2–S5 | a truncated vendored copy no longer silently sources to a no-op registry. This is why the fix uses `-s`, not the old `-f`. |
| S7 | path exists, non-empty, **malformed bash** | that path | `source` aborts under `set -e`, rc=2-ish | uncaught | bare bash syntax error. **Accepted, out of scope** — identical to pre-fix behaviour, and a syntax-checking wrapper around a `source` is not worth the complexity. Stated so a reviewer does not re-raise it. |

Ordering rationale (why sibling FIRST, not last): `SCRIPT_DIR` is the only root that is
correct for *the script actually executing*. Putting the vendored copy first — the old
order — means a stale `.claude/scripts/` symlink in the main checkout shadows the copy
being tested. Sibling-first also makes the plugin-cache copy self-consistent.

### 2b. `leadv2-glm-quota-gate.sh` return codes (the ladder leak surface)

| rc | Meaning (file:line) | What `leadv2-router-v2.sh` / `leadv2-session-route.sh:382-388` does | Terminal user-visible consequence |
|---|---|---|---|
| 0 | quota healthy / gate short-circuited (`:65,71,94,113,117,123,138,142,184`) | glm stays eligible | dispatch proceeds on GLM. **In the ladder test's un-stubbed legs this spawns a real GLM worker.** |
| 1 | `LEADV2_DISPATCH_REFUSED: quota_gate` (`:161`) | `GLM_GATE_TRIPPED=1`, glm dropped from the ladder | dispatch falls to sonnet; a park row is written to `glm-deferred.jsonl`. Test legs that expect a specific ordered ladder go red. |
| 2 | `LEADV2_DISPATCH_REFUSED: peak_hours` (`:177`) | same drop path, different reason string | same; **time-of-day dependent** — the suite's colour depends on the wall clock. This alone makes the test non-hermetic even with a healthy network. |

There is no retry on any of these. An rc that reaches the ladder loop is final for that
dispatch.

---

## 3. CONFIGURATION BOUNDARIES

Inputs the two mechanisms read, and behaviour at each boundary.

### 3a. `LEADV2_CANONICAL_ROOT` (new consumer in both fanout sites)

| Boundary | Behaviour | Verdict |
|---|---|---|
| absent | defaults to `${HOME}/Projects/leadv2` | fine — tier 3 only, tiers 1/2 normally win |
| empty string | `${LEADV2_CANONICAL_ROOT:-…}` uses the default (`:-` covers empty) | correct by construction |
| set to a non-existent dir | `[[ -s ]]` false → falls to tier 4 | fine |
| set to a path with spaces | all expansions are quoted in the landed diff | fine |
| set to a *wrong but populated* leadv2 checkout | sources a foreign registry | acceptable: tiers 1/2 already won in every real topology; tier 3 is a rescue |

Cross-check per constraint-checklist item 1: prefix is `LEADV2_*`, consistent with
`LEADV2_PROJECT_ROOT`/`LEADV2_STATE_ROOT`. No `LEAD_V2_*` drift. Item 5: no other
consumer of `LEADV2_CANONICAL_ROOT` assigns it conflicting semantics.

### 3b. `${PROJECT_ROOT}/.claude/scripts/` (tier 2)

absent (the lane-worktree case — **this is the bug**) → falls through, previously aborted ·
present-but-empty-dir → falls through · present as a dangling symlink → `-s` false, falls
through · present and valid → sourced.

### 3c. `SCRIPTS_ROOT` in `test-fanout-classify-guard.sh` (fixture staging)

Defined at line 33 as `$(cd "${SCRIPT_DIR}/.." && pwd)` — always the real scripts dir,
never host-dependent. `cp` of a missing source would fail the sandbox builder loudly; the
file is tracked, so absent is not a reachable state in a checkout.

### 3d. Ladder-test env knobs — the boundary table that matters

| Input | absent (today) | required behaviour after fix |
|---|---|---|
| `LEADV2_ROUTER_V2_BIN` | real router-v2 on legs 172/181/448/450/462/463 → live gate | stub on **every** dispatch invocation, or export once at the top |
| `LEADV2_DISPATCH_GLM_BIN` | **real GLM worker spawn** on the same legs | poison-stub globally, like `LEADV2_DISPATCH_CODEX_BIN`/`KIMI_BIN` already are at lines 54-55 |
| `LEADV2_GLM_QUOTA_GATE` | real gate → network + `~/.claude/state/leadv2/quota-cache` | point at a fixed-rc stub |
| `LEADV2_QUOTA_CACHE_DIR` | `${HOME}/.claude/state/leadv2/quota-cache` — **writes host state from a test** | redirect into `${TMP_ROOT}` |
| `LEADV2_PROVIDER_QUOTA_GATE` | defaults `1` (`leadv2-provider-quota-gate.sh:16`) | set `0` |
| `LEADV2_BURN_GOVERNOR` | already `0` at line 27 | keep |
| `HOME` | host `$HOME` | leave as-is only if every `$HOME`-reading callee is overridden above; otherwise pin to a fixture dir |

**Over-cap principle applied:** the poison-stub for GLM must be a *poison* (exit 99, loud
on stderr) and not a silent success, so a future leg that forgets an override fails the
suite instead of quietly spawning. That is exactly the fence pattern already used at
lines 49-55 for kimi/codex; GLM was simply omitted from that loop. The minimal, honest fix
is **add `glm` to the existing `for _arm in kimi codex` loop** and then re-point it to the
behaving stub per leg — one line changed, uniform with what is there.

### 3e. Census — other core-offline tests, same class

Grepped `plugins/leadv2/scripts/tests/` for `.claude/scripts/` and `leadv2-shared`.

| Test | Uses the path how | Safe? |
|---|---|---|
| `test-core-offline-root-arith.sh:44-54` | `mkdir -p`s + `ln -s`s its own `$fixture_a/.claude/scripts/tests/` | **safe** — creates it |
| `test-e2e-gate-lane-root.sh:325-344` | `mkdir -p "${CG}/.claude/scripts/tests"` then writes stubs | **safe** — creates it |
| `test-pump-junk-in-lane.sh:41-42` | `ln -s "$SCRIPTS_DIR/…"` into its own `$main_repo` | **safe** — creates it, sources from `SCRIPTS_DIR` |
| `test-no-work-terminal.sh:126-131` | symlinks into its own temp repo | **safe** |
| `test-drift-guard-safety-fixes.sh`, `test-drift-guard-quarantine-perimeter.sh`, `test-one-copy-drift.sh` | build `$DG_HOME/.claude/leadv2-shared` fixtures and pass them via `LEADV2_ONE_COPY_*_ROOT` / a fixture `HOME` | **safe** — fixture-scoped |
| `test-codex-quota-guardrails.sh:363` | `~/.claude/scripts/codex-task.sh` appears **inside a JSON string** fed to a hook, never executed | **safe** |
| `test-broad-status-lanes-blind.sh:77` | a host path inside an expected-failure **string literal** | **safe** |
| `test-plugin-sync-claude-scripts.sh` | the subject under test is the vendoring itself; all under `$proj` | **safe** |
| **`test-glm-deferred-ladder.sh`** | reaches host `$HOME` quota cache + live network + real GLM spawn | **NOT safe — fix per §3d** |

No other same-class instance. The fanout guard was the only *source-a-host-path*
instance; the ladder is the only *live-external-state* instance.

---

## 4. COUNTEREXAMPLE — what can still violate the invariant

Invariant: *the core-offline suite's colour is a function of the committed tree alone —
never of the host's untracked symlink farms, `$HOME`, wall clock, network, or provider
quota.*

After every finding above is fixed, three things can still violate it, and the lane should
say so rather than claim hermeticity. **(i) The other 10 sibling tests named in
`plugins/leadv2/docs/test-escape-duplicate-caller-race.md` are unaudited** — the ladder is
one confirmed instance of a real-worker escape; the document asserts more, and this task's
scope only closes the ladder. **(ii) `leadv2-glm-quota-gate.sh` rc=2 is `peak_hours`, a
wall-clock function** — any *future* test that reaches the real gate is time-dependent
even with the network up, and nothing structurally prevents a new test from doing so; the
poison-fence in §3d makes that failure loud rather than silent, but only for the arms in
the fence loop. **(iii) `$HOME` itself is still the ambient default** for every callee not
explicitly overridden — the ladder fix enumerates the knobs known today
(`LEADV2_QUOTA_CACHE_DIR`, `LEADV2_GLM_QUOTA_GATE`, …), and a new `$HOME`-reading callee
added to `leadv2-dispatch-code.sh` tomorrow would re-open the leak with no test to catch
it. The structural fix for (iii) — running the whole suite under a pinned fixture `HOME` —
is **explicitly out of scope here**; it is a suite-wide change, and I checked that
`run-core-offline.sh` currently sets no `HOME` at all, so doing it now would change the
blast radius of all ~60 tests in a task whose remit is two of them.

What I checked to say this: `run-core-offline.sh:263-323` (suite list, no HOME pinning),
`leadv2-glm-quota-gate.sh:37,65-184` (rc ladder + `LIVE` default),
`leadv2-provider-quota-gate.sh:9,16,47` (gate/cache defaults),
`leadv2-router-v2.sh:62,68,158`, `leadv2-session-route.sh:382-388`,
and a full grep of `tests/` for `.claude/scripts` and `leadv2-shared`.

---

## 5. Change set (exact files, for the implementer)

1. **`plugins/leadv2/scripts/leadv2-fanout.sh:49-59`** — KEEP the WIP four-tier
   sibling-first block as landed. No further edit.
2. **`plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:82-92`** — KEEP the WIP block.
   This is the copy the mission never named; it is required for a lane launched *inside* a
   worktree.
3. **`plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh`** — KEEP fixture staging
   (`_new_sandbox` cp) + Test 5. Test 5 is the regression guard: empty `$HOME`, no vendored
   dir, must still classify.
4. **`plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh`** — (a) delete the two
   DEBUG printfs at 148/150; (b) add `glm` to the poison-fence loop at line 49; (c) export
   `LEADV2_GLM_QUOTA_GATE` (rc-0 stub under `TMP_ROOT`), `LEADV2_PROVIDER_QUOTA_GATE=0`,
   `LEADV2_QUOTA_CACHE_DIR="${TMP_ROOT}/quota-cache"` once near line 27 beside the existing
   `LEADV2_BURN_GOVERNOR=0`; (d) add `LEADV2_ROUTER_V2_BIN` + `LEADV2_DISPATCH_GLM_BIN` to
   the `glm-deferred --retry-all/--list` legs at 172, 181, 448, 450, 462, 463.
5. **`plugins/leadv2/scripts/leadv2-dispatch-code.sh`** — delete the two DEBUG printfs
   (5420, 5486). Nothing else in this file changes.
6. **`plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh`** — resolve the
   `UU` conflict; state the resolution in the summary.
7. `bash -n` every touched `.sh`.

## 6. Non-goals (do not do these)

- Pinning a fixture `HOME` for the whole suite (see §4 iii).
- Auditing/fixing the other 10 tests in `test-escape-duplicate-caller-race.md`.
- The founder decision on reverting `73e6aca` — that is an open thread, not this task.
- Creating or repairing any `.claude/scripts/` symlink farm; the fix is to stop *depending*
  on it, not to make it exist in worktrees.
- Touching `leadv2-glm-quota-gate.sh` / `leadv2-provider-quota-gate.sh` production logic.
- Any change to `leadv2-dispatch-code.sh` beyond removing the two DEBUG lines.
- `docs/leadv2/burn-deferred.jsonl` + `burn-deferred.d/` (untracked, at repo root) are test
  spill from an earlier un-hermetic run. Do not commit them; do not delete them either
  without saying so — flag in the summary.

## 7. Acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >-
      Running tests/run-core-offline.sh from inside a lane worktree, the line for
      "fanout classifier/runner guard" reads PASS, and the run's final Results line
      reports zero failures — the same as it does from the main checkout.
    authored_at: 2026-08-24T16:26:21Z
  - surface: log_line
    observable: >-
      The line for "deferred-GLM ladder (V3-GLM-LADDER-01)" reads PASS on a host whose
      GLM quota is exhausted and again on a host whose GLM quota is healthy, and no
      "POISON: real provider spawn attempted" text appears anywhere in the run output.
    authored_at: 2026-08-24T16:26:21Z
  - surface: file_artifact
    observable: >-
      After the suite has run, ~/.claude/state/leadv2/quota-cache contains no entry
      whose timestamp falls inside the run window, and no new untracked file has
      appeared under docs/leadv2/ in the repo the suite was launched from.
    authored_at: 2026-08-24T16:26:21Z
  - surface: log_line
    observable: >-
      With the registry helper absent from all four locations, fanout prints exactly one
      line naming the missing helper and refusing to launch, and no lane window opens —
      instead of a bare "No such file or directory" from the shell.
    authored_at: 2026-08-24T16:26:21Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-fanout.sh, plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh, plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh

DELIVERABLE_COMPLETE
