# CONTROL-PLANE-HAS-NO-OWNER-01 — D0 baseline + census correction

Measured 2026-09-03, worktree `CONTROL-PLANE-HAS-NO-OWNER-01` @ `b925a5ad` (branch
`worktree-CONTROL-PLANE-HAS-NO-OWNER-01`). D0 only — measurement, no behaviour change. No
production file touched; no suite fixture edited; no known-red-suites.txt edit.

**Headline correction:** of the 23 suites D0's row names (22 that exist + 1 that doesn't), only
**9 are reachable by `tests/run-all.sh` at all** (`--scope changed` or the always-on set). The
other 14 are dark: they exist, several are red, and CI will never see it. This is the audit-1
shape (§3 of the brief) recurring one layer down — not in "a standalone script nobody calls" but
in "a test suite nobody runs." `tests/known-red-suites.txt` confirms this independently: none of
the 23 named suites appear in it, because none of them ever reached a CI baseline to be marked
red at.

Second headline: a real, code-confirmed regression in test isolation (`FOREIGN-PROJECT-ROOT-GUARD-01`,
`leadv2-dispatch-code.sh:299-323`) causes at least 4 of the D0 suites to run against this
machine's **real, shared** control-plane state (`~/.claude/leadv2-state/leadv2/`, resolved by
`leadv2-state-path.sh` — see U-finding below) instead of their own throwaway fixture, because they
`git init` a temp repo in a subshell but never `cd` the test process into it before invoking
`leadv2-dispatch-code.sh`. This is exactly the failure mode §5's risk table names ("Tests that
touch the LIVE registry kill live lanes... every suite sets `LEADV2_PROJECT_ROOT` to a temp dir")
— except the mitigation is not universally true today; some suites do not honor it, and the guard
added for a different incident (leaked `CLAUDE_PROJECT_DIR`) makes the failure silent rather than
loud.

## 1. Suite existence + registration table (D0 row correction)

Legend: **Reg** = does `tests/run-all.sh --scope changed` ever select this suite (EXTRA_SUITE_MAP
literal match, checked against `tests/run-all.sh` verbatim, or the basename-stem self-select
convention `test-<script-basename>.sh`)? **macOS** / **Linux** = exit code, this run.

| suite | exists | Reg | macOS exit | Linux exit | note |
|---|---|---|---|---|---|
| `test-worker-outlives-terminal-state.sh` | **NO** | — | — | — | Named in D0's row and in D3 ("keep ... re-point it at the funnel"). Does not exist anywhere in the tree (`find`, `grep -r`, both empty). `WORKER-OUTLIVES-ITS-TERMINAL-STATE-01`'s own handoff dir has only `brief.md`, no suite. **D3 cannot "keep" a suite that was never created.** |
| `test-lane-liveness-authoritative.sh` | yes | **no** | 1 | 1 | Real failure, identical both OSes. Not in EXTRA_SUITE_MAP; stem for `leadv2-lane-liveness.sh` is `test-leadv2-lane-liveness.sh`, which is not this file's name — self-select never fires. |
| `test-lane-liveness-lies.sh` | yes | **no** | 0 | 0 | Passes; orphaned from `--scope changed` for the same stem-mismatch reason. |
| `test-lane-liveness-sentinel.sh` | yes | **no** | 0 | 0 | Passes; orphaned, same reason. |
| `test-lane-registry-self-deadlock.sh` | yes | **no** | 1 | 1 | Real failure, identical both OSes. `leadv2-active-registry.sh`'s stem (`test-leadv2-active-registry.sh`) doesn't match; no EXTRA_SUITE_MAP row. |
| `test-lane-registry-outlives-dispatcher.sh` | yes | **yes** | 1 | 1 | `tests/run-all.sh:150-151`: two EXTRA_SUITE_MAP rows (`leadv2-dispatch-code.sh`, `leadv2-active-registry.sh`). Still fails on both OSes — a **registered, currently-red** suite. |
| `test-dispatch-terminal-deregisters-lane.sh` | yes | **no** | 0 | 0 | Passes; not in EXTRA_SUITE_MAP, no stem match. |
| `test-dispatch-ledger-partial-close.sh` | yes | **no** | timeout(90s) | 1 (rc=3, "setup — first dispatch or process-death wait failed") | Root cause below (§2). Hangs on macOS (lock contention against the real shared registry), fails cleanly on Linux (no contention, same isolation bug still fires). |
| `test-dispatch-ledger-task-id.sh` | yes | **no** | timeout(90s) | 1 (`route_resolved arm=refuse reason=all_arms_capped`, rows come back empty) | Same isolation bug. |
| `test-t-core-dispatch-ledger.sh` | yes | **no** | 0 | 0 | Passes both OSes; not registered. |
| `test-lane-placement-pin.sh` | yes | **yes** | timeout(90s), passes partial (P-a/P-h before hang) | timeout(90s), same | `tests/run-all.sh:268` (`leadv2-dispatch-code` stem). **Registered AND hangs on both OSes** — a real, non-environmental hang; the container has no shared state to contend on, so this is not the FOREIGN-PROJECT-ROOT-GUARD-01 pattern. Root cause not traced further inside D0's budget — flagged, not fixed. |
| `test-status-surface.sh` | yes | **yes** | 0 (92 passed, 26s — see §3 on my first `timeout 25` false-hang) | 1 (89 passed, 3 failed) | `tests/run-all.sh:281` (`leadv2-status-surface.sh` stem). **Registered, and a genuine cross-OS divergence**: Linux fails a width/budget rendering assertion and a hermeticity check (`docs/leadv2/questions` path differs — `/tmp/leadv2-lpp-.../questions` expected, `/tmp/ss-surface.../.claude/leadv2-state/leadv2/questions` observed). Spot-checked under real Apple `/bin/bash` 3.2 too (see §3): still 92/0 there, so the divergence is OS/path-resolution, not the bash-version axis. |
| `test-status-surface-close-phase.sh` | yes | **no** | 0 | 0 | Passes both; not registered. |
| `test-status-surface-cwd.sh` | yes | **no** | 1 | 1 | Real failure, identical both OSes; not registered. |
| `test-status-surface-handle-identity.sh` | yes | **no** | 0 | 0 | Passes both; not registered. |
| `test-broad-status-duty.sh` | yes | **yes** | timeout(60-90s), "T3b: no ready-line with dispatched=2 after loop cycle" | timeout(90s), same | `tests/run-all.sh` (`leadv2-broad-status.sh` stem row). **Registered and hangs on both OSes** — same category as lane-placement-pin: a real hang, not host contention. |
| `test-broad-status-foreign-lanes.sh` | yes | **yes** | 0 | 0 | Registered, passes both. |
| `test-broad-status-lanes-blind.sh` | yes | **yes** | 0 | 1 (T8b: "malformed rows dropped silently, not surfaced") | **Registered AND a genuine cross-OS divergence** — 47/1 failed on Linux, 48/0 on macOS. |
| `test-broad-status-relay-scope.sh` | yes | **no** | 1 (7 passed, 18 failed) | 0 (all pass) | Not registered anywhere. **Massive divergence, but not a real OS difference** — root cause is host contamination: this machine has dozens of concurrently-live `/leadv2` sessions (see the `[LEADV2_ACTIVE_OTHER_SESSIONS]` list this task's own session header carries) writing real founder-status/relay state that this suite reads unsandboxed; the Linux container has no such neighbours and passes clean. Recorded as a finding, not "fixed" — D0 does not touch fixtures. |
| `test-broad-status-renderer-truth.sh` | yes | **yes** | 0 | 0 | Registered, passes both. |
| `test-broad-status-row-identity.sh` | yes | **yes** | 0 | 0 | Registered, passes both. |
| `test-lanes-snapshot.sh` | yes | **no** | 0 | 1 (after installing `tmux` — see §3; exit 127 before that, missing binary, not a real result) | Not in EXTRA_SUITE_MAP; `leadv2-lanes-snapshot.sh`'s stem (`test-leadv2-lanes-snapshot.sh`) doesn't match this file's name. **Genuine cross-OS divergence**: "Test 3b: adopted=False" fails only on Linux once tmux is present. |
| `test-leadv2-lane-heartbeat.sh` | yes | **yes (implicit)** | 0 | 0 | Not in EXTRA_SUITE_MAP as a literal row, but its name equals `test-<stem>.sh` for source `leadv2-lane-heartbeat.sh` — the basename-stem convention (`tests/run-all.sh:527-533`) selects it without needing a map row. Passes both OSes. |

**9 of 23 reachable, 14 dark** (counting the nonexistent suite as dark by definition). Of the 9
reachable: 3 are currently red or hanging while registered (`test-lane-registry-outlives-dispatcher.sh`,
`test-lane-placement-pin.sh`, `test-broad-status-duty.sh`) — meaning a real `--scope changed`
push against `leadv2-active-registry.sh`, `leadv2-dispatch-code.sh`, or `leadv2-broad-status.sh`
would currently fail or hang CI, independent of this task.

## 2. FOREIGN-PROJECT-ROOT-GUARD-01 breaks test isolation for ≥2 suites (code-confirmed)

`leadv2-dispatch-code.sh:299-323` (comment) documents the guard's own assumption: "most suites in
tests/ that `git init` a throwaway repo under mktemp ALSO `cd` into it before invoking this
script, so cwd's own git toplevel already equals the throwaway repo and no mismatch is ever seen."

`test-dispatch-ledger-task-id.sh:53` violates that assumption:
```
( cd "${ROOT}" && git init -q && git config user.email test@example.com && git config user.name test ... )
```
This is a **subshell** — `cd "${ROOT}"` never affects the parent test process. Every later
invocation of `leadv2-dispatch-code.sh` (lines 83, 163, 191, 220, 328, 355) runs with
`CLAUDE_PROJECT_ROOT="${ROOT}" LEADV2_PROJECT_ROOT="${ROOT}"` set but the process's actual cwd
still at wherever the suite was launched from (this worktree root, in my run). The guard sees
`env != cwd`, logs `foreign project root detected ... using cwd-derived root
(FOREIGN-PROJECT-ROOT-GUARD-01)` (`leadv2-dispatch-code.sh:449`), and **overrides the test's
isolated root back to the real worktree**. From there the dispatch call runs against this
machine's real, shared arbiter/utilization state and either:
- returns `rc=3`/`rc=4` with empty ledger rows (Linux, no lock held), or
- blocks on the real registry's flock, held by one of the other concurrently-active `/leadv2`
  sessions on this machine (macOS, where I ran this from a session that itself is one of dozens
  listed in `[LEADV2_ACTIVE_OTHER_SESSIONS]`).

`test-dispatch-ledger-partial-close.sh` has the identical pattern (confirmed by log: same
`foreign project root detected` line, same `env=/private/var/.../repo cwd=<this worktree>`).

This is **not** a new regression I'm introducing or fixing (D0 is measurement-only, off-limits to
touch fixtures) — it is a pre-existing, code-verifiable gap between the guard's documented
assumption and these two suites' actual fixture code. It explains why these suites are red/hanging
independent of any change to the lane-state owner mechanisms themselves, and it means: **any
future suite written for D1-D5 must actually `cd` its process into the throwaway root**, not just
`cd` inside a subshell that only runs `git init`.

## 3. Methodology notes (things I got wrong on the first pass, corrected before reporting)

- **My first `timeout 25` run on `test-status-surface.sh` reported exit=124 (looked like a hang).**
  It was not — the suite legitimately takes ~26s (`time bash test-status-surface.sh` → `26.167
  total`, exit 0, 92/0). Widened to 90s for the rest of the batch. Recorded here so this isn't
  mistaken for a real finding.
- **My "macOS" batch ran under Homebrew `bash` 5.3.9 (PATH-resolved), not Apple's `/bin/bash`
  3.2.57**, which is what SwiftBar and the repo's own bash-3.2 standing decision actually target
  (`uname -a` / `bash --version` / `/bin/bash --version` all checked). I spot-checked 2 suites
  under real `/bin/bash` 3.2 directly: `test-lane-liveness-authoritative.sh` (exit=1, same) and
  `test-status-surface.sh` (exit=0, 92/0, same). Consistent with the bash-5 run for both, but this
  is a 2-of-22 spot-check, not full 3.2 coverage — flagging so nobody reads "macOS exit codes
  above" as bash-3.2-verified.
- **Linux run needed `tmux` installed** (`test-lanes-snapshot.sh` uses `tmux -L <socket> new-session`
  for a keepalive fixture) — a bare `ubuntu:latest` container doesn't have it; GitHub's
  `ubuntu-latest` runner image does by default. First run without it gave a misleading exit=127
  ("command not found"), discarded and re-run.
- Container setup: `docker run ubuntu:latest`, mounted the **main repo root** (not just this
  worktree) at its real host path so the worktree's `.git` pointer (`gitdir:
  .../leadv2/.git/worktrees/CONTROL-PLANE-HAS-NO-OWNER-01`) resolves; `git config --global
  --add safe.directory '*'`; `pip3 install --break-system-packages pyyaml`.

## 4. U1–U8 — resolved against code / live behaviour, not the brief's own prose

- **U1 — RESOLVED, confirmed by code (not just call-site plausibility).**
  `dispatch-code.sh:5695-5705` calls `lane_adopt_pid "${DISPATCH_REG_ID}" ... "${_LV2_LANE_PULSE_WATCH_PID}"`
  → `lib/leadv2-lane-state.sh:158-161`: `lane_adopt_pid() { lane_register "$1" "$2" "$3" "$4" "$5" ...; }`
  → `lane_register` calls `_lv2_lane_state_mutate register ... "${5:-$$}"` → the Python register op
  (`lib/leadv2-lane-state.sh:82-99`) finds the **existing row by `task_id`** and does
  `existing.update(pid=pid, pid_start_time=birth(pid), ...)` unconditionally. The watcher pid handed
  in at `:5705` lands in `pid` every time this call fires (gated only on `arm != sonnet` and the
  watcher pid being alive) — there is no live-row observation needed; the mutation is
  unconditional in the code. Symptom 1's mechanism is real, not just plausible.
- **U2 — RESOLVED, per-site, mixed verdict (the brief's framing as one question was too coarse).**
  - `leadv2-gate1-prompt.sh:64,132` — **live**. `leadv2-dispatch-code.sh` calls
    `leadv2-gate1-prompt.sh` directly (confirmed: `grep -n "leadv2-gate1-prompt" *.sh` shows
    `leadv2-dispatch-code.sh` as a caller). This registration runs on the single-lead path.
  - `leadv2-helpers.sh:628,650` (`leadv2_lock_acquire`/`leadv2_lock_release`) — **dead**. Zero
    callers anywhere in `plugins/leadv2/scripts/*.sh`, `plugins/leadv2/hooks/*.sh`, or
    `plugins/leadv2/commands/*.md` other than the function's own definition and its
    `export -f` at `:2566`. It is exported for a child process to inherit but nothing in the
    current tree ever invokes it. **This one is not on the live path at all today.**
  - `leadv2-fanout*.sh` — **not dead, live but secondary**. `plugins/leadv2/commands/leadv2.md`
    references `leadv2-fanout.sh` directly (a real `/leadv2` entry point), so it is not
    "supervisor-era orphan" in the sense `leadv2-lanes.sh`/`leadv2-lane-watch-v2.sh` are (0
    callers, confirmed dead). It IS explicitly named in three session-runner scripts'
    system-prompt text as forbidden self-recursion ("NEVER invoke ... leadv2-fanout.sh ...: that
    is self-recursion") — meaning fanout is a **separate top-level launch mode**, not something a
    dispatched worker should call, and not something the single-lead dispatch-code.sh path calls
    either (only comments reference it there). Its W9 unregister sites are live for whoever
    invokes `/leadv2 fanout` directly, dead for the single-lead path this brief is scoped to.
- **U3 — RESOLVED by reading the function** (`leadv2-dispatch-code.sh:3072-3090`).
  `_dispatch_evidence_exists(created_epoch, sig8)` returns **rc0 ("evidence or unknown — do not
  reclaim")** when inputs are malformed, when `EVIDENCE_ATTRIBUTION=1` and a handoff-dir match by
  sig8+timestamp exists, or — the fallback used when attribution mode is off — when
  `git log --all --since=<created_epoch's ISO time>` shows ANY non-empty, non-excluded path
  touched anywhere in the repo since the task's registration time. It returns **rc1
  ("unattributed_empty" — reclaimable)** only when that git-log scan comes back completely empty.
  This is a repo-wide "did anything land since I was created" heuristic, not sig8-scoped unless
  attribution mode is explicitly on — a sixth Q3 mechanism, distinct from R11's `lv2_lane_work`.
- **U4 — RESOLVED, and the brief's own citation needs a nuance correction.**
  `leadv2-broad-status.sh:158-176` (`_live_lane_facts()`) does count `active.yaml` rows directly —
  brief's citation is accurate for that function. But that function is **only the degraded-path
  fallback narrative** (fired when the collector step itself fails, per its own
  ANTI-SILENCE-ONE-MECHANISM-01 comment). The **primary** render path — the one that produces the
  `table_md` with the `(живых линий нет)` fallback at `:1023` — goes through
  `bash "$COLLECTOR_SH" --project-root ... --out "$SNAPSHOT_PATH"` at `:241`
  (`COLLECTOR_SH=leadv2-status-collector.sh`), then builds `rows_out_full`/`rows_out` from that
  snapshot (`:900-950`). So the real producer chain for a wrongly-empty pulse is
  `leadv2-status-collector.sh`'s snapshot content, not a direct `active.yaml` miscount inside
  broad-status.sh itself — U4's "not traced past :1023" is now traced to :241, one more hop toward
  status-collector.sh's own row production, which full root-cause of the specific 09:07Z/09:37Z
  incident would require reading next (425 lines, out of D0's scope; flagged for D5).
- **U5 — partially resolved.** `leadv2-lane-outcome.sh:1-25` (header) confirms it is a "pure-ish
  classifier + artifact writer" producing exactly one of `completed | died-with-work | died-clean |
  parked`, writing `<run_dir>/.outcome`, `<run_dir>/progress.log`, and 3 keys in
  `<run_dir>/meta.yaml`. The producer side is now documented; the ledger-side consumption mapping
  (which terminal-ledger states each token maps to) was not traced end-to-end within D0's budget —
  left open for D3, which already owns the terminal-funnel rework.
- **U6 — RESOLVED as absent, and the brief's own pointer is a false lead.**
  `tests/test-run-all-carrier-map.sh` exists but has nothing to do with mutation catalogs — its
  header (`:1-15`) says it proves `tests/run-all.sh --scope changed` selects the FABLE-THINK-TIER-01
  contract suite for non-`.sh` carrier files. Grepping the whole tree for `kill.rate`/`mutation
  catalog` turns up exactly one other hit: `docs/handoff/MUTATION-RUNNER-STAGES-EVERYTHING-01/brief.md`,
  which names `scripts/v5-mutation-kill-rate.sh` and `scripts/mutation-kill-rate.sh` — **neither
  file exists anywhere in this tree** (`find` empty). That brief describes a never-built (or
  since-deleted) task, not a live convention. **Conclusion: no kill-rate catalog convention exists
  in this repo today.** D6's `mutations.md` will be the first one — not a resurrection of
  something that already exists under a different name.
- **U7 — RESOLVED, mixed like U2.** `leadv2-stale-sweeper.sh` has no confirmed live caller: it is
  not referenced in `plugins/leadv2/hooks/hooks.json` (grep empty) or any hook file, despite
  `leadv2-outcome-watch.sh:12`'s own header claiming "Called by leadv2-stale-sweeper.sh at every
  SessionStart" — that claim is not backed by a wired hook in this tree. Its only other references
  are a comment inside `leadv2-fanout.sh:1901` and its own file. **Appears orphaned — consistent
  with the brief's "supervisor-era" hypothesis, and a D5 deletion candidate.** But
  `leadv2-outcome-watch.sh` itself is separately, definitely live: called directly from
  `leadv2-phase8-close.sh` and `leadv2-soak-rollback.sh`, independent of stale-sweeper. **Do not
  delete outcome-watch.sh if stale-sweeper.sh is deleted — they are not the same lifecycle.**
- **U8 — RESOLVED, confirmed fallback stub, not live definition.**
  `product-close.sh:91`'s `lv2_lane_dirty() { return 0; }` (and the identical stub at
  `leadv2-dispatch-ledger.sh:109`) is defined **only inside the `else` branch** guarding a failed
  `source` of `lib/leadv2-lane-guard.sh` (checked at both the local path and
  `${LEADV2_CANONICAL_ROOT}/.../lib/leadv2-lane-guard.sh`). The branch's own comment: "Unknown
  guard state is unsafe at close: it must fail closed, never allow the later terminal funnel to
  call a dirty lane clean." The **live** definition, used whenever the source succeeds (the normal
  case), is `lib/leadv2-lane-guard.sh:50`. So `return 0` here means "assume dirty" (fail-closed),
  not "assume clean" — worth stating explicitly since the stub's own `return 0` reads ambiguously
  out of context.
- **Row-authoritative safety (§5 risk 1, "is 'no row → not alive' safe for every spawner")** — not
  resolved in D0; this is D1's spawner census, explicitly deferred there by the brief itself. Not
  re-litigated here.

## 5. What I did not do (explicitly out of scope for D0)

- Did not touch `leadv2-dispatch-code.sh`, any test fixture, or `tests/known-red-suites.txt`.
- Did not root-cause the two double-OS hangs (`test-lane-placement-pin.sh`,
  `test-broad-status-duty.sh`) past "reproduces identically in an isolated container, so it is not
  purely host-contention" — that is real investigative work belonging to whichever deliverable
  touches liveness/broad-status (D2/D5).
- Did not attempt a mutation/negative-control run — D0's own row says "none — measurement only,"
  and I have no behaviour change to prove red/green around.
- Did not run the full `tests/run-all.sh --scope changed` or `--scope all` end-to-end (would pull
  in the ~83-suite `run-core-offline.sh` set, well past a baseline check of the 23 named suites,
  and risks the same live-registry contention documented in §2 at much larger blast radius on a
  machine already running dozens of concurrent `/leadv2` sessions).

DELIVERABLE_COMPLETE
