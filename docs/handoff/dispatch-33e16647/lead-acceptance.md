# D6-REGISTRY-LANE-OWNERSHIP-01 — lead acceptance, independently measured

Everything below was run by the lead in the lane worktree
`~/Projects/leadv2/.claude/worktrees/D6-REGISTRY-LANE-OWNERSHIP-01`, not copied from the worker's
report. Where the worker's claim and this measurement agree, they were produced separately.

## 1. Ten consecutive runs — re-measured, not trusted

```text
independent bash rcs: 0 0 0 0 0 0 0 0 0 0
independent zsh  rcs: 0 0 0 0 0 0 0 0 0 0
```

Verbose tail of one run:

```text
[TEST] PASS: distinct owners: lead-63094-3289297870 != lead-63096-1694248385
[TEST] PASS: cap proves defect dead: lane1(same session)=0 lane2(same session)=3(refused) lane3(other session)=0
[TEST] PASS: lead alive corroboration: live owner + matching birth -> rc=0
[TEST] PASS: lead alive corroboration: recorded birth mismatch -> rc=1 (not alive)
[TEST] PASS: lead alive corroboration: dead owner reports not-alive (rc=1)
[TEST] PASS: legacy rows resolve: lane_count_live direct returned '0' without exception
[TEST] 6 passed, 0 failed
```

The cap assertion is the acceptance the brief asked for and it is state-based, not a count of
names: **same session refused with rc=3, other session permitted with rc=0.**

## 2. The gap the report left as prose — closed by measurement

The report landed the resolver but described the four consumer wirings only in words. Each consumer
gets a 6-line top-level wiring change (`git diff --numstat main...HEAD`: 6/1 in each of
`leadv2-broad-status.sh`, `leadv2-codex-session-runner.sh`, `leadv2-inbox.sh`,
`leadv2-session-runner.sh`), and nothing in the hermetic suite exercises those four files. So the
question "does the wiring actually resolve, or does it fall through to `direct`?" was open.

Probe: extract each consumer's own wiring lines from its own bytes, evaluate them with
`LEADV2_LEAD_SESSION_ID` and `LEADV2_PARENT_SESSION_ID` unset, print what resolves.

```text
leadv2-inbox.sh                    -> lead-51591-1174514947
leadv2-broad-status.sh             -> lead-51591-1174514947
leadv2-session-runner.sh           -> lead-51591-1174514947
leadv2-codex-session-runner.sh     -> lead-51591-1174514947
```

Not `direct` in any of the four. All four agree because a durable pid is per-process and this probe
ran in one process; distinctness across processes is what the suite's `distinct owners` case
asserts, and it passes.

## 3. Negative controls — measured rc pairs, from the worker's artifacts

`docs/handoff/dispatch-33e16647/mutation-control/` carries the pairs, each mutation inside a
function body, none a syntax error:

| file | mutation | baseline_rc | mutated_rc | red line |
|---|---|---|---|---|
| `lib/leadv2-lead-identity.sh` | `id="lead-${pid}-${birth_hash}"` -> `id="direct"` | 0 | 1 | `FAIL: distinct owners: got A='direct' B='direct'` |
| `lib/leadv2-lane-state.sh` | `register` loses its 6th/7th args | 0 | 1 | `FAIL: lead alive corroboration: live owner + matching birth got rc=1 (want 0)` |
| `lib/leadv2-lane-state.sh` | `recorded == observed` -> `observed` | 0 | (artifact) | recorded-vs-observed collapse |

The first control kills the identity itself and the failing assertion is the **state** one
(`distinct owners`), not a message-text one — the falsification the shared constraints demand.

## 4. Scope — clean

```text
git diff --name-status main...HEAD    -> 7 files: 5 M, 2 A
git diff --diff-filter=D --name-only main...HEAD  -> (empty)
forbidden paths (dispatch-code / profile-select / route-arbiter / active-registry /
                 docs/leadv2/ / known-red-suites.txt / tests/run-all.sh)  -> clean
git ls-files -> lib/leadv2-lead-identity.sh, tests/test-lead-session-identity.sh both tracked
```

The 18 dirty files in the worktree are all shared runtime state (`docs/leadv2/*`, foreign
`phases.d`) and are deliberately **not** committed.

## 5. What is NOT proven, stated plainly

- **e2e gate: `status: unknown, reason: e2e_timeout, rc: 124` after 900 s.** Not red — unknown.
  This is `E2E-GATE-BROKE-TODAY-01`, not a property of this branch.
- **`review-gate.md` says `blocked / no_work`.** It is stale: written by the pre-answer round that
  stopped on `q-0e1bfed6`. The work landed in `7fabbc26` after the answer.
- **The live registry check cannot pass yet.** "at least 2 distinct `lead_session_id` while two
  sessions work" needs the dispatcher to call the resolver, and `leadv2-dispatch-code.sh` belongs to
  another session. Until that one line lands, the registry keeps writing `direct` and the check is
  not merely unverified — it is unreachable. The worker was right to mark it UNVERIFIED rather than
  claim it.
- **CI does not select the new suite.** The `EXTRA_SUITE_MAP` row is in the report, unpasted, per
  the brief's bound.

## 6. The one line to land, in the file this lane may not touch

`leadv2-dispatch-code.sh:7071`:

```bash
local _lead_session_id="${LEADV2_LEAD_SESSION_ID:-${LEADV2_PARENT_SESSION_ID:-$(source "${SCRIPT_DIR}/lib/leadv2-lead-identity.sh"; leadv2_lead_session_id)}}"
```
