# D1 — a 401 from the usage endpoint is not a dead account

Lane `60fdbb5be2c6`, 2026-09-08. Fix commit `44475674` (fix + tests) and the
report/artifact commits after it. Base: `fe491bff` (merge-base with main).

## 1. The contradiction, verified — and its resolution

`classify_account_state` (`plugins/leadv2/scripts/leadv2-quota-read.py`) claimed
two things at once: (a) every account it classifies has already resolved an
access token, and (b) a 401 on a non-team account is "the ordinary
this-credential-is-actually-dead shape". The mission asked me to verify that
derivation before building on it. It holds, and the code itself is the proof:

- `read_anthropic` skips any entry with no `accessToken` bytes
  (`leadv2-quota-read.py:572` — `if not at: continue`): a credential-less entry
  never reaches the classifier at all.
- The token it does send is a **stored** one. The DPoP refresh
  (`platform.claude.com/v1/oauth/token`) is not wired — the no-accounts branch
  says so in so many words (`:653`), and the `expiresAt` comment (`:574-584`)
  records that the CLI refreshes in-process without rewriting keychain state,
  so the stored token (and its `expiresAt`) are not liveness signals.

So a 401 at this call measures exactly one thing: *this stored token cannot
read usage data*. It is not evidence of a dead credential, for `max` any more
than for `team` — the launch path uses the refresh token, which the probe never
exercises.

**The signal that distinguishes a genuinely dead credential: there is none at
classification time.** Confirmed independently of the first attempt's finding by
reading the producer (`read_anthropic:585-598`): the only launch-shaped signal
would be a live DPoP refresh, and it does not exist in the probe. Deadness is
discovered by launching, and a failed launch is already parked by the arbiter's
failure-memory/lockout machinery (`lib/leadv2-route-arbiter.sh:707-722`). That
is the honest answer the mission asked to be named, and it is the shape of the
fix: classification may only say "we cannot price this from a measurement", it
may not say "this account cannot launch".

Corroborating in-tree measurement for `max` specifically
(`lib/leadv2-route-arbiter.sh:319-333`): on 2026-09-04 the active `max_20x`
entry read http 401 while a *different entry of the same account* returned a
freshly-probed pct — a 401 coexisting with a provably-alive account. The
2026-09-08 live-probe 401 on the max accounts (the D1 mission input; consumer
half merged as `fe491bff`) is the same shape.

## 2. The fix

`classify_account_state` now prices every **measured** 401 class as `unmetered`:

```python
if http_code == 401 and subscription_type in ("team", "max"):
    return ACCOUNT_STATE_UNMETERED
```

- `max` joins `team` as a measured class. `max_20x` (the yaml's pinned
  `active_account`) is now selectable: no probe penalty, cost priced at the
  least-generous configured allowance weight (0.2 → haiku 2/0.2 = 10, sonnet
  25, opus 45) — expensive-but-reachable, ranked after any measured arm, ahead
  of unknown-probe arms (51+) and the freepool floor (100).
- **`pro` + 401 deliberately stays `unknown`/50.** It is the P1b guarded
  boundary (`tests/test-unmetered-account-not-penalised.sh`), never measured
  live, and the addendum rules it is the founder's to retire, not this lane's.
  The docstring says so explicitly, so the next reader knows the gate is a list
  of measured classes, not a distinguishing test.
- No arbiter change was needed: `util()`'s unmetered branch, `capped()`,
  `headroom_weight()` and the decision-line tokens are all tier-agnostic — they
  key on `account_state`, which the producer now emits for max.

### Why not shrink UNKNOWN_PROBE_PENALTY instead

Read before touching it, as ordered (`lib/leadv2-route-arbiter.sh:906-912`,
`:937`): the 50 exists to rank ANY measured arm above ANY unmeasured one while
staying under the freepool floor — the ordering property that fixed C3
(a broken probe must never look cheap). Shrinking it would globally re-admit
genuinely-broken probes (network errors, 429s, `needs_login` codex) into
selection against measured arms — the milder cousin of the C3 bug — and would
necessarily change pro+401's price too, widening past the guard. The unmetered
classification prices ONE fact (cannot-read-usage) exactly once (matrix cost ×
conservative weight, no stacked penalty — `headroom_weight`'s unmetered branch
returns before `unk` is consulted), which is what the :937 "never price one
fact twice" warning asks for. The penalty number itself is untouched.

## 3. Negative controls (E2E-KILLRATE-01) — red, then green

Suite: `plugins/leadv2/tests/test-401-is-not-a-dead-account.sh`
(`# run-all-triggers: leadv2-quota-read leadv2-route-arbiter`). Auction mirrors
the 2026-09-07 incident: glm/codex probes failed (`unknown`), claude read
through the usage endpoint; arms haiku(2)/sonnet(5)/glm(1);
`complexity=simple` (flag, conf 0.7 → req_eff 2.3) puts every arm in
fit_bucket 0 so effective cost alone decides.

### Control 1 — the symptom, RED before the fix (raw)

```
arm=glm kind=docs model=glm-5.3 tier=standard effort=low reason=cheapest_capable
chain=glm,sonnet,haiku util_claude=unknown_capped ... claude_account_state=unknown
claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty ... haiku:price_ratio
AssertionError: SYMPTOM max+401 claude lost the auction to a probe-failed competitor: arm=glm
```

`subscription_type=max` + http 401 lost the selection to a probe-failed glm
(52 vs 51) — the exact `max_20x` symptom. Suite rc=1.

### Control 1 — GREEN after the fix (raw)

```
SYMPTOM-OK max+401 -> arm=haiku penalty=0 state=unmetered
GUARD-OK pro+401 -> arm=glm penalty=50 state=unknown
MUTATION-CONTROL-OK everything-usable -> arm=haiku penalty=0 state=unmetered (guard reddens on these values)
PASS d1-401: max+401 selectable (claude wins the auction); pro+401 still excluded; everything-usable mutation caught
```

Suite rc=0. The selection *outcome* is asserted (the returned arm), not a log
line.

### Control 2 — the guard, mutation inside the function body

The suite rewrites `classify_account_state`'s final
`return ACCOUNT_STATE_UNKNOWN` → `ACCOUNT_STATE_UNMETERED` ("everything is
usable") and re-runs the pro auction: the mutant hands claude the auction
(`arm=haiku ... claude_probe_penalty=0`), i.e. the guard reddens on
`arm=`/`claude_probe_penalty=` values. Backed by the runner artifact
`docs/audits/mutation-control/20260908T164422Z-53712.txt`:

```
baseline_rc=0
mutated_rc=1
red_line=arm=haiku ... claude_account_state=unmetered claude_probe_penalty=0 ...
lane_diff_hash=37fcb01e2cd5a513a4590edb50ae96f7928e230720af487f25f1b3aee66c33d6
```

## 4. Registration and selection proof

- The new suite carries `# run-all-triggers: leadv2-quota-read
  leadv2-route-arbiter`; both changed production stems select it, and a changed
  `test-*.sh` self-selects anyway.
- **Range measured from: `fe491bff..HEAD` + uncommitted diff** — the
  merge-base was pinned into
  `.git/worktrees/60fdbb5be2c6/leadv2-run-all-last-checked-sha` before the run
  (per SCOPE-CHANGED-IS-STATEFUL-AND-A-SECOND-RUN-LIES-01; the checkpoint is
  worktree-scoped and was removed after the run completed, verified gone). This
  selected 7 suites: run-core-offline.sh plus the three status-surface suites
  (changed shell stems from the lane range) and the three quota suites
  (test-401-is-not-a-dead-account, test-claude-account-states,
  test-unmetered-account-not-penalised).
- Verified with `LEADV2_RUN_ALL_LIST_TRIGGERS=1` before running: the suite
  appears in the discovered map (exit path exercised, not assumed).

## 5. Falsification set (raw)

```
$ bash -n plugins/leadv2/tests/test-401-is-not-a-dead-account.sh \
      plugins/leadv2/tests/test-unmetered-account-not-penalised.sh \
      plugins/leadv2/tests/test-claude-account-states.sh   → BASH_N_OK
$ python3 -m py_compile plugins/leadv2/scripts/leadv2-quota-read.py → PY_COMPILE_OK
```

Neighbour suites (same producer/consumer pair):

```
$ bash plugins/leadv2/tests/test-unmetered-account-not-penalised.sh
PASS unmetered(team,max) penalty=0; unknown penalty=50; measured penalty=0     rc=0
$ bash plugins/leadv2/tests/test-claude-account-states.sh
PASS=11 FAIL=0                                                                rc=0
```

Changed-scope runner verdict: see §4 for the range; **runner output**:

```
$ bash tests/run-all.sh --scope changed     # checkpoint pinned to fe491bff, removed after
[PASS] plugins/leadv2/tests/test-401-is-not-a-dead-account.sh
[PASS] plugins/leadv2/tests/test-claude-account-states.sh
[PASS] plugins/leadv2/tests/test-unmetered-account-not-penalised.sh
... (run-core-offline.sh + 3 status-surface suites, all green)
run-all: 7 passed, 0 failed, scope=changed                                    rc=0
```

## 6. Recommendation to the founder (the pro guard)

The addendum asked for an explicit argument if my fix touches pro+401. It does
not — but the honest argument for retiring the guard is now on record:

**The pro+401 → unknown/50 rule rests on a hypothesis never measured**: that a
401 on a pro account is "the ordinary dead credential shape". By the producer's
own mechanics it cannot be — dead credentials are excluded upstream
(token-less), and the 401 only ever says "this stored token cannot read
usage". A revoked pro refresh token and a stale-token-alive pro account are
indistinguishable at classification time, and the second is the *common* case
for an account whose CLI sessions refresh in-process.

If you retire the guard, the honest replacement is not "trust everything": it
is the missing launch probe. Wire the DPoP refresh into `read_anthropic` (one
POST per account per probe, exactly the credential use a launch would make) and
classify on *that* result: refreshed → unmetered-or-measured, refresh refused →
`unknown` with a penalty that finally measures something real. Until then, pro
accounts that 401 stay parked — recoverable by any live Claude session
refreshing the credential, exactly the `needs_session=True` path the
no-accounts branch already documents.

Two smaller observations, noted not acted on: (a) 429 lands in `unknown` and so
is priced as a dead probe even though a 429 proves the credential is alive and
merely capped — same family as this bug, smaller blast radius; (b) no live
launch attempt was performed in this lane: the classification fix requires
none, and the mission caps probes at one (none spent).

## 7. Files changed

- `plugins/leadv2/scripts/leadv2-quota-read.py` — `classify_account_state` +
  docstring (the only production change).
- `plugins/leadv2/tests/test-401-is-not-a-dead-account.sh` — new suite
  (symptom/guard/mutation controls).
- `plugins/leadv2/tests/test-claude-account-states.sh` — added the `max+401 →
  unmetered` case; negative-control #3's mutation anchor updated to the new
  condition line (same semantics: collapse unmetered back into unknown).
- `plugins/leadv2/tests/test-unmetered-account-not-penalised.sh` — added the
  `max-unmetered` iteration; the `pro` arm is byte-identical.
- `docs/audits/mutation-control/20260908T164422Z-53712.txt` — runner artifact.
- This report.

Incident, disclosed: a first `rm -rf plugins/leadv2/scripts/__pycache__` (py_compile
hygiene) deleted four *tracked* .pyc files; restored immediately via targeted
`git checkout --` before the commit. No committed damage; the final tree is
clean.
