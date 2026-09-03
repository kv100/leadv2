# D2-UNBLIND-AND-THIRD-STATE-M0M1-01 — M0 + M1 report

Scope: rows M0 and M1 of the D2 migration table only. M2–M6 untouched; no
consumer of the liveness verdict was edited; `leadv2-dispatch-code.sh`,
`leadv2-active-registry.sh` and `tests/run-all.sh` untouched.

| step | commit |
|---|---|
| M0 — unblind the deliverable (`.gitignore`) | `c41dbbce` |
| M1 — rung E4 + `finished_unlanded:` + `unknown:yaml_unreadable` | `171ca2b2` |
| suite + core-offline registration | `d3d340ff` |

Commit-order note: M0 landed alone and first as ordered. The suite was
committed **after** M1, not before: its E4 assertions can only be green with
the rung present, so a suite-first commit would have been a deliberately red
commit. Order used keeps every commit's tree green (M1 without the suite is
green; suite with M1 is green).

## M0 — proof (both commands, before/after)

Scratch probe file `docs/handoff/D2-M0-SCRATCH-PROBE/developer.full.md`
(removed after the probe; no untracked full.md exists in a fresh worktree,
so a scratch one was required to make the commands observable).

`git add --dry-run docs/handoff/D2-M0-SCRATCH-PROBE/developer.full.md`:

```
# pre-M0 (HEAD .gitignore):
The following paths are ignored by one of your .gitignore files:
docs/handoff/D2-M0-SCRATCH-PROBE/developer.full.md
hint: Use -f if you really want to add them.
# post-M0:
add 'docs/handoff/D2-M0-SCRATCH-PROBE/developer.full.md'
```

`git status --porcelain -uall docs/handoff | grep -c 'full\.md'`:

```
# pre-M0: 0
# post-M0: 1
```

## M1 — the third state

`resolve()` gains two verdicts, nothing renamed (brief §2/§8): rung E4
(`deliverable_age_s`, sibling of `commit_age_s`) emits
`finished_unlanded:<age>s` before `dead:no_handoff_dir`/`dead:no_log_artifact`;
an absent/unparseable registry emits `unknown:yaml_unreadable` instead of a
manufactured dead. Window is the SAME `LEADV2_LANE_FINISHED_WINDOW_S` (no new
tunable, brief §11-5). Verdict is a sibling of `finished:` — consumers match
`finished*`; both new strings land in every consumer's existing `*)` arm.

Live smoke (scratch repo, unborn HEAD, dead pid, fresh deliverable):

```
== state 3 (deliverable, unlanded) ==   finished_unlanded:1s
== mirror (nothing at all) ==           dead:no_log_artifact
== corrupt registry + deliverable ==    finished_unlanded:1s   (E4 outranks unknown)
== absent registry, no deliverable ==   unknown:yaml_unreadable
```

## Suite — test-lane-verdict-three-states.sh (13 assertions, green)

```
[TEST] RESULTS: 13 passed, 0 failed
```

Covers: the incident shape (deliverable + no commits + dead pid →
`finished_unlanded:*`, **never** `dead:*`); the `finished*` sibling-prefix
contract (and no collision with `alive`/`starting:`/`silent:`/`dead:`/`child`);
the mirror (no deliverable → `dead:no_log_artifact`; no dir →
`dead:no_handoff_dir`); corrupt **and** absent registry → `unknown:*`, never
dead; `-s` guard (0-byte report is not evidence); mtime guard (7200s-old
report past the 1800s window → dead); `*.summary.md` counts and
newest-non-empty wins; live pid + deliverable → `silent:*` (C2 floor — a
worker mid-report is never finished); E3 still above E4 (commit + deliverable
→ `finished:*`); JSON evidence trail (`source=deliverable`,
`reason=no_pid_recent_deliverable`, numeric `age_s`). Fixtures verify their
own setup (registry row re-read, unborn-HEAD asserted, load-sensitive commit
status-checked) and assert filesystem post-state.

## Suite registration — run-core-offline.sh plan dump (LEADV2_SUITE_SHARDS_DUMP=1)

Appended one row to `SUITE_DEFS` (append-only; `tests/run-all.sh` untouched —
held by a concurrent lane). Plan-dump line naming the suite:

```
shard=0 idx=84 name=lane verdict three states (D2-UNBLIND-AND-THIRD-STATE-M0M1-01: deliverable=finished_unlanded, registry unreadable=unknown)
```

Executed green through the runner's own machinery (`LEADV2_SUITE_DEFS_OVERRIDE`
single-entry run): `[CORE-OFFLINE] suites passed=1 failed=0 missing=0`.

Changed-scope selection (`tests/run-all.sh --scope changed`, select-only,
first invocation before the range was consumed): `run-all: 12 selected,
scope=changed` — including `test-lane-verdict-three-states.sh`.

## Mutation controls (leadv2-mutation-control.sh, artifacts under mutation-control/)

Each mutation inside a function body, single-anchor sed, tool exit 0 =
`baseline_rc=0` / `mutated_rc=1`.

| # | control (function mutated) | exit | baseline/mutated | red line |
|---|---|---|---|---|
| C2 (mandatory) | rung E4 neutralized (`if False:` on the deliverable check) — `resolve` | 0 | 0/1 | `[TEST] FAIL: Test 1: verdict=dead:no_log_artifact (must match finished_unlanded:<age>s, never dead:*)` |
| U | `if active_unreadable:` neutralized — `resolve` | 0 | 0/1 | `[TEST] FAIL: Test 3a: verdict=dead:no_handoff_dir (must be unknown:*, never dead)` |
| S | `-s` guard neutralized (`if st.st_size <= 0:`) — `deliverable_age_s` | 0 | 0/1 | `[TEST] FAIL: Test 4: verdict=finished_unlanded:0s (must be dead:* — an empty report is not finished evidence)` |

C2 is the whole defect restated: with the rung not looking at the deliverable,
the lane goes back to `dead:no_log_artifact`.

Tool stdout (C2, pass A — pass B re-run after this report was committed so the
artifact's `lane_diff_hash` matches the final lane; red_line/diff_hash identical):

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh file=plugins/leadv2/scripts/leadv2-lane-liveness.sh red_line=[TEST] FAIL: Test 1: verdict=dead:no_log_artifact (must match finished_unlanded:<age>s, never dead:*) diff_hash=0f6ff4f17e290754f7bb63d6233b8bf8c1160df68ebee9134803a28f97c80d91 lane_diff_hash=c735bbb0033f626e9a0687b553a829faab94ad0a182a3d9ebf6f42c4e6376944
```

## Falsification set

`bash -n` every changed shell file — all OK:

```
OK  plugins/leadv2/scripts/leadv2-lane-liveness.sh
OK  plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh
OK  plugins/leadv2/scripts/tests/run-core-offline.sh
```

`python3 -m py_compile` — no `.py` file changed; the changed script's embedded
heredoc python extracted and compiled: `OK embedded python (1061 lines)`.

Changed-scope suites run individually (the official `tests/run-all.sh --scope
changed` invocation was killed at 570s inside the heavyweight
`run-core-offline.sh` child — core-offline alone measures >10min, known):

| suite | rc | note |
|---|---|---|
| test-lane-verdict-three-states.sh | 0 | 13/0 (this lane) |
| test-lane-finished-state.sh | 0 | 10/0 (E3 rung intact) |
| test-lane-liveness-sentinel.sh | 0 | 13/0 |
| test-board-blind-detached-workers-01.sh | 0 | 5/0 |
| test-reap-funnel-death-proof.sh | 0 | 19/0 — **D3 merged reap funnel intact, no consumer break** |
| test-handoff-artifacts-tracked.sh | 0 | 6/0 — M0 did not break the tracked-artifact contract |
| test-handoff-docs-not-leaked.sh | 0 | 5/0 |
| test-status-surface-single-lead.sh | 0 | 23/0 |
| test-status-surface-fast-names.sh | 0 | 12/0 |
| test-status-churn.sh | 0 | 13/0 |
| test-suite-lock-scope.sh | 0 | 12/0 |
| test-status-surface-bash32.sh | 124 | hangs at T6 minimal-env parity — reproduces identically with pre-M1 liveness (baseline swap) ⇒ pre-existing |
| test-fork-storm-watcher-liveness.sh | 1 | acc8 fixture never pins its watcher pidfile — reproduces identically at baseline ⇒ pre-existing |
| test-lane-liveness-authoritative.sh | 1 | D6 statusline parse (env-dependent quota chips) — reproduces identically at baseline ⇒ pre-existing |
| test-lane-registry-self-deadlock.sh | 1 | (c) probe-read file set — reproduces identically at baseline ⇒ pre-existing |

Full `run-core-offline.sh` (85 entries, 4 shards) killed at 560s: shards 2/3
completed (`pass=12 fail=4`, `pass=18 fail=2`), shard 0/1 still running; the
13 failing entries (skill proof gate, dispatch arm vocabulary, phase
precondition, plugin reliability, product-close, T14 worker MCP, broad-status
relay, idle-lead guard, review-round ×2, glm-deferred ladder, codex-dead
reroute, core-offline lock) are the known pre-existing red landscape —
**none** calls `leadv2-lane-liveness.sh` or reads the `.gitignore` semantics
M0 changed (verified by grep over the failing suites). No assertion was
weakened; nothing added to `tests/known-red-suites.txt`.
