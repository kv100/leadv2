# §3 — account switch as a working operation: measurement and runs

Lane `5ee952587fdf` (worktree `w-account-switch-impl`). Files changed:

- `plugins/leadv2/scripts/leadv2-account-switch.sh` — the operation (new)
- `plugins/leadv2/scripts/tests/test-account-switch.sh` — hermetic suite, 30 checks (new),
  self-selected via `# run-all-triggers: leadv2-account-switch`
- `docs/handoff/w-account-switch-impl/step0-observer.log` — Step-0 raw artifact
- `docs/handoff/w-account-switch-impl/mutation-control/<run-id>.txt` — mutation-control artifact
- this report

No Python file was changed (`python3 -m py_compile`: nothing to compile — the
reused instruments `leadv2-claude-profile-pick.py` / `leadv2-quota-read.py`
are consumed as-is, unmodified).

## Step 0 — the measured branch: the client RE-READS its credential per call

Question (brief, mandatory before any code): does an already-running claude
process pick up an account change made underneath it, or is it pinned for
life?

Method: one real `claude -p` client (v2.1.267), a throwaway `CLAUDE_CONFIG_DIR`
whose credential comes from a file under my control, and a local observer
that answers `/v1/messages` and records `sha256(Authorization)[:12]` for every
request (digests only — a token never appears anywhere). The client's task
uses the Bash tool to rewrite the credential file (A → B) between its two API
calls. Raw artifact (`step0-observer.log`):

```
seq=1 path=/v1/messages?beta=true auth_sha12=8b68191d0d93 x-api-key=no
seq=2 path=/v1/messages?beta=true auth_sha12=7761473b97aa x-api-key=no
```

Expected digests, computed independently:

```
Bearer step0-fake-access-A -> 8b68191d0d93
Bearer step0-fake-access-B -> 7761473b97aa
```

Call #1 presented credential A; after the file swap the SAME process's call #2
presented credential B. **Branch measured: перечитывает** — for a file-sourced
credential the running client follows an underneath change on the next call.

Scope of the measurement, stated honestly:

- Measured on a `file:`-credential slot against a local endpoint observer.
- UNVERIFIED: whether a `keychain:`-sourced credential is re-read per call —
  measuring that would require mutating real keychain entries, which this
  lane does not do. The operation does not depend on it: it never rewrites a
  live slot's credential (that is the 2026-08-28 two-slots-collapse incident
  class, guarded below).
- Consequence for the operation's shape: leadv2 production slots are
  keychain-pinned by process env (`CLAUDE_CONFIG_DIR` /
  `LEADV2_ANTHROPIC_ACTIVE_SERVICE` — fixed at exec, verified in code at
  `claude-subsession.sh:563`). So the switch steers every FUTURE spawn of the
  lane, proves it by observing the next selection, and reports live children
  (their env is theirs; they finish on the old account, counted, never
  silently ignored).

## The operation

`leadv2-account-switch.sh --handoff <dir> [--from <label>] [--dry-run]` — one
action, no second instruments: every pick is a real
`leadv2-claude-profile-select.sh` run (balancing for the decision, hard-pinned
`LEADV2_CLAUDE_PROFILE_REQUESTED` for target confirmation), the TWO_BUCKETS
guard is `leadv2-claude-account-check.sh`, free-ness is the live probe
(`source=live score<100`) — a stale `expiresAt` is not death and never gates
(case 4 pins this end-to-end).

Mechanics of "switch": arm the selector's OWN cooldown marker
(`probe-cooldown-until` + `.cred` digest sidecar) for the exhausted account,
expiring exactly at that account's own window reset (read from the same live
probe; falls back to the selector's own 900 s default when the probe cannot
say). Then OBSERVE: a fresh balancing selector run must pick the target —
otherwise rc 5 `switch_not_taken`, loud (including the mirror shape: the pick
moved but the target stopped being free — observed score ≥ 100 is a failure,
not a success). Refusals are loud and named: `no_free_alternative` (+ nearest
reset), `current_is_best_free`, `registry_not_two_buckets`, `target_not_*`.
Survivors are checked by reading bytes back (`claude-profile.log` must stay
byte-identical — the operation never writes it; the handoff stream survives).
Journal: separate `<handoff>/account-switch.log`, because
`leadv2-claude-profile-status.sh` reads `tail -1` of `claude-profile.log`
expecting a `selected=` line — the pinned line format is untouched.

## Runs (honest)

Suite `tests/test-account-switch.sh`, hermetic (keychain stub, probe stub,
registry fixtures — real accounts never touched, nothing sensitive printed):

- green: `summary: PASS=30 FAIL=0` (7 cases: main switch + independent
  next-pick observation; paired both-exhausted refusal; current-is-best
  refusal; stale-expiresAt-but-alive target; ONE_BUCKET guard;
  target-exhausted `switch_not_taken`; dry-run).
- changed-scope runner: `run-all: 5 passed, 0 failed, scope=changed`
  (the suite was selected by its `run-all-triggers` marker — registration
  works, not asserted).
- mutation (negative control), removing the "next call went to the new
  account" verification inside the script body: `summary: PASS=20 FAIL=10`,
  main fixture red (`case1 rc=0 (switched) -- rc=1 want=0`, no
  `observed_next_pick=b`). After restoring: `PASS=30 FAIL=0` again.
- mutation-control tool (DoD-gate-accepted artifact,
  `mutation-control/<run-id>.txt`):

```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-account-switch.sh \
  file=plugins/leadv2/scripts/leadv2-account-switch.sh \
  red_line=[TEST] FAIL: case1 rc=0 (switched) -- rc=1 want=0 \
  diff_hash=def5870f88efaf71471bf5ffae8921086dbf2893f337172448c1add73cc0d7f6 \
  lane_diff_hash=b30b8f87b1e045010449626a11016b3eb420c97154af9b1224fd1ee5f66cd79a
```

- syntax: `bash -n` on both changed shell files — OK (output above in the
  session log: `bash -n leadv2-account-switch.sh: OK`, `bash -n
  test-account-switch.sh: OK`).

## Round 2 — the label guard gets its own fixture (and its own journal voice)

Round-1 defect (lead's mutation): killing the FIRST switch_not_taken guard
(`:357` — "the next pick stayed on the OLD account") left the suite 30/0.
Two guards, one fixture: `case 6` covers only the score guard.

### What changed

- `test-account-switch.sh` **case 8**: the switch arms the steer for `a`,
  then the operator re-logs into the exhausted account mid-switch
  (`SWITCH_TEST_A_RELOGIN`: the credential stub returns a different blob
  from the moment the marker's `.cred` sidecar exists — the selector's own
  `PROBE-COOLDOWN-OUTLIVES-ITS-CONDITION-01` invalidation then deletes the
  steer) AND the account reads free again (`a_drop_after=3`: probeings 1-2
  see 100, the marker probe and the observation run see 10/5). The
  observation run therefore legitimately lands back on `a` with a NORMAL
  score (<100) — the score guard is silent, only the label guard can catch
  it. Expects rc=5, stdout names observed+expected, journal names both plus
  which guard fired.
- `leadv2-account-switch.sh`: the label guard's journal line now carries
  `detail=next_pick_not_target`, symmetric to the score guard's
  `detail=target_no_longer_free` (that guard moved `:366` -> `:368` — three
  comment lines added above it; same guard).
- Suite 39/0 on intact code; existing cases byte-untouched (case 6's
  counter/flip path identical).

### Mutation -> what went red (the two matrices)

Mutation A — kill the label guard, `:357`:

```
s,if \[\[ "$OBSERVED_NEXT" != "$TARGET_LABEL" \]\]; then,if false; then,
summary: PASS=35 FAIL=4   -- ALL four failures are case 8:
  FAIL: case8 rc=5 (switch_not_taken) -- rc=0 want=5
  FAIL: case8 names switch_not_taken
  FAIL: case8 names the EXPECTED label (b)
  FAIL: case8 journal: observed+expected+label-guard discriminator
case 6: green.  cases 1-7: green.
```

Mutation B — kill the score guard, `:366`/`:368`:

```
s,if \[\[ ! "$OBSERVED_SCORE" =~ \^\[0-9\]+\$ || "$OBSERVED_SCORE" -ge 100 \]\]; then,if false; then,
summary: PASS=35 FAIL=4   -- ALL four failures are case 6:
  FAIL: case6 rc=5 (switch_not_taken) -- rc=0 want=5
  FAIL: case6 names switch_not_taken
  FAIL: case6 says the target stopped being free
  FAIL: case6 journalled as failed
case 8: green.  cases 1-5,7: green.
```

Each mutation reds exactly one case and never both — the fixtures
discriminate the two guards.

### The journal line of each refusal (which guard, readable after the fact)

```
FAILED reason=switch_not_taken observed=a expected=b detail=next_pick_not_target marker_rc=0
FAILED reason=switch_not_taken observed=b observed_score=100 detail=target_no_longer_free marker_rc=0
```

### Evidence

- `bash -n` both changed files: OK.
- Suite on intact code: `summary: PASS=39 FAIL=0`.
- changed-scope runner: `run-all: 5 passed, 0 failed, scope=changed`.
- mutation-control artifacts (re-bound to the final lane HEAD after the
  report commit — see below):
  `mutation-control/<run-id>.txt` ×2 — `MUTATION-CONTROL ok ... mutated_rc=1`
  for both mutations (diff_hash bca5e06e... / 07676975...).

## Live-lane behaviour (what the operation says, not assumes)

- Already-running sessions keep the old account for their lifetime (their
  credential is never rewritten under them). The operation counts them
  (`staying_children=N pids=...`) and says so on stdout.
- Work that must survive a switch survives by read-back: the lane's
  claude-profile.log and handoff stream artifacts are byte-compared before
  and after; a change fails the operation (`survivor_changed`, rc 5).
- The steer self-reverts: at the exhausted account's window reset the marker
  expires and the account competes again automatically.

## Not done (explicitly)

No design report was written (per brief). `leadv2-route-arbiter.sh`,
`leadv2-dispatch-code.sh`, spawn hooks, `leadv2-launch-registry.py`,
`leadv2-workflow-step.py`, routing-config readers, and the
`claude-profile.log` line format are untouched.
