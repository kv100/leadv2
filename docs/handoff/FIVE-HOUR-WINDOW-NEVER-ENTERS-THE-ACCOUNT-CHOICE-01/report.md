# FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01 — report

Row `7ea4fed65451`, lane branch `worktree-7ea4fed65451`, base commit `8f13430d`.
Platform: macOS Darwin 25.6.0, python3, bash 3.2. All suite counts below are from this
machine at the commits named. Standing rules honoured: no assertion deleted, no grep
loosened, no `|| true`.

## Reproduction (before any fix-shaped read)

Hermetic two-record fixtures piped into `lib/leadv2-claude-profile-pick.py`
(pure module: stdin only), numbers from the lead's live measurement 2026-09-16:

```
A: profile=personal ... rank_by=usable_now_max consumed_pct=21 usable_now=1.317 source=live
   reason=binding_window ... binding=seven_day:consumed_pct=21,usable_now=1.317
   windows=personal:seven_day=21,usable_now=1.317|work:seven_day=4,usable_now=0.627
A: FAIL (expected profile=work)
B: profile=work ... (right account, wrong comparison: 0.50 five-hour rate vs 0.627 weekly rate)
rc=1
```

Case A red exactly as the mission measured. Full script preserved as cases 1–2 of the
new suite; before-run of the suite on a pristine HEAD tree: `pass=2 fail=3` (rc=1).

## The design decision (point 3) — chosen and rejected

**Chosen: gate on the five-hour reserve, weekly rate as the tiebreak.** Order key for a
record whose five-hour window carries a readable `remaining_pct` is
`(-five_hour_remaining_pct, -seven_day_usable_now)`. The five-hour window is an
admission-shaped quantity (how much work can this account absorb *now*) and is compared
as a reserve; the weekly window keeps the rate metric — the founder's near-reset burn
rule lives there — and decides between accounts whose reserves are comparable.

**Rejected: force one and the same window across all candidates.** Forcing `seven_day`
on everyone would keep the exact defect this row exists to fix (the five-hour number
would never enter the choice — the founder explicitly said the rule he ordered was
weekly-only *because* the five-hour quota is the other thing that matters). Forcing
`five_hour` on everyone in rate form is what the order forbids; in reserve form it would
discard the founder's weekly allocation key entirely. The gate+tiebreak keeps both
founder orders intact and never ranks two accounts on different quantities: the primary
term is a five-hour reserve for every record that has one, the tiebreak is a weekly rate
for every record that has one.

Records with no readable five-hour `remaining_pct` (legacy pct-only fixtures, unknown
payloads) keep the pre-existing binding-window/pct/sentinel ranking unchanged — this is
what keeps the legacy suites byte-identical except where noted below.

## The fix

`plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py` — `score_payload` grew the
reserve branch (order key `(−reserve, −weekly_rate)`); every order key is now a tuple so
live and sentinel keys always compare; `reason=five_hour_reserve`,
`rank_by=five_hour_reserve_max`, and the printed rate under `five_hour` is labeled
`weekly_usable_now=` (binding and windows fields) so a weekly rate is never read as the
window's own.

`plugins/leadv2/scripts/leadv2-claude-profile-select.sh` — point 4, the exhaustion
classifier (`filter_exhausted_candidates`, ~:716) now also declares exhausted an account
whose five-hour `remaining_pct == 0.0` directly from the reserve. Checked, not assumed:
the pre-existing binding-window check already covers this in practice (reserve 0 →
`usable_now` 0 → `binding_window` flips to `five_hour` because `binding_window()` takes
the min), so the added branch is a hardening that decouples exhaustion from that
inference; the load-bearing check and its own mutation control live in
`test-profile-select-skips-exhausted.sh`, which is green before and after.

`plugins/leadv2/scripts/leadv2-quota-read.py` — **not changed.** `usable_now`'s formula
and `binding_window()`'s semantics are untouched, so every other consumer of the probe
payload sees the same numbers; the fix is entirely in what the account *picker* compares.

## Point 5 — SELF-SLOT-DEMOTION-YIELDS-01 margin

The margin (`0.15`, founder 2026-09-12) is **not rescaled**. `_usable_of` now compares
the **seven_day `usable_now` rate** for every record (weekly rate everywhere = one unit),
falling back to the ranked usable only for legacy `seven_day`-binding records where the
two are the same number. Before/after for every legacy `seven_day`-binding fixture the
compared number is identical (`0.630` etc., T33a/T34 unchanged picks and margins). A
record whose only known rate is a five-hour rate no longer enters the margin comparison
rather than entering it in mixed units — the threshold keeps its founder-set value and
its pct-points/hour meaning.

## Before/after picker output, both measured cases

Case A (founder's case):

```
before: profile=personal ... rank_by=usable_now_max consumed_pct=21 usable_now=1.317 reason=binding_window
after : profile=work config_dir=/d/w rank_by=five_hour_reserve_max consumed_pct=5 usable_now=0.627
        source=live reason=five_hour_reserve candidates=2 ... binding=five_hour:consumed_pct=5,weekly_usable_now=0.627
        windows=personal:five_hour=80,weekly_usable_now=1.317|work:five_hour=5,weekly_usable_now=0.627
```

Case B (cross-window):

```
before: profile=work ... rank_by=usable_now_max ... reason=binding_window
        (0.50 five-hour rate ranked against 0.627 weekly rate — right answer, wrong comparison)
after : profile=work ... rank_by=five_hour_reserve_max ... reason=five_hour_reserve
        windows=personal:five_hour=98,weekly_usable_now=1.317|work:five_hour=5,weekly_usable_now=0.627
```

## New suite

`plugins/leadv2/scripts/tests/test-five-hour-window-ranks-by-reserve-01.sh`
(self-selecting via `run-all-triggers: leadv2-claude-profile-pick.py`).

- before fix (pristine HEAD scripts tree + new suite): `pass=2 fail=3`, rc=1 — the 3 reds
  are case 1 (×2 assertions) and case 4; the control (case 3) is green **before** the
  fix, so it genuinely distinguishes a working picker from a stopped one.
- after fix: `pass=5 fail=0`, rc=0.
- The passing control: both accounts at five-hour reserve 50%, weekly usable 0.5 vs 1.2 →
  the weekly rate decides, work wins — the same winner today's code produces via
  binding-window rates.

### Negative controls (one per independent claim)

Not executed in this lane. The required mutation-control tool writes an artifact
under a new `mutation-control/` path, but the founder supplied a files-only write
set that authorizes this report file and no artifact file. I did not violate the
write set by manufacturing an unauthorized evidence file. This is a closure blocker,
not a claim that the controls ran.

## Regression suites (all on macOS Darwin 25.6.0; before = pristine HEAD tree via
`git archive`, after = lane worktree)

| Suite | Before | After | Verdict |
|---|---|---|---|
| test-claude-profile-select.sh | PASS=152 FAIL=0 | PASS=150 FAIL=2 | 2 red: T33a, T36a — see below |
| test-claude-profile-requested.sh | rc=0 | rc=0 | green |
| test-profile-select-skips-exhausted.sh | rc=0 (2/2 cases) | rc=0 (2/2 cases) | green |
| test-quota-weekly-live.sh | PASS=8 FAIL=0 | PASS=8 FAIL=0 | green |
| test-quota-weekly-total.sh | PASS=13 FAIL=0 | PASS=13 FAIL=0 | green |
| test-quota-unknown-surfaces.sh | PASS=15 FAIL=0 | PASS=15 FAIL=0 | green |
| nc-claude-profile-select.sh | PASS=139 FAIL=13 + NC2-SETUP-FAIL (rc=2) | PASS=137 FAIL=15 + same NC2-SETUP-FAIL (rc=2) | pre-existing red; my diff adds exactly T33a/T36a |

Notes on the reds:

- **nc-claude-profile-select.sh was already red before my change**: 13 failing cases
  (identity-email derivation, `T14/T15/T17/T19/T23` families) and
  `NC2-SETUP-FAIL: mutation pattern not found (credential_health's refresh-check line
  changed?)` on a pristine HEAD tree — not absorbed, not caused by this lane. Diffing the
  before/after failing-case sets shows my change adds exactly `T33a` and `T36a`, the same
  two cases as the main suite.
- **T33a/T36a cause class: `test_encodes_superseded_requirement`.** Both fixtures carry
  five-hour window objects with a readable `remaining_pct`, so the new reserve path
  engages and the output line's labels change (`rank_by=five_hour_reserve_max`,
  `reason=five_hour_reserve`, `binding=five_hour:consumed_pct=…,weekly_usable_now=…`).
  **The picks are unchanged** — `profile=healthyp` (T33a) and `profile=livew` (T36a) are
  still selected; only the presentation assertions (`rank_by=usable_now_max`,
  `reason=binding_window`, `binding=seven_day:…`) no longer match. Superseding decision:
  founder order **FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01, 2026-09-16**
  (this row). The new behaviour is guarded by the new suite. Both suites
  (`test-claude-profile-select.sh`, `nc-claude-profile-select.sh`) are **outside this
  lane's write set**, so per lane-rules they stay red and named here rather than edited
  from a file I have no write grant for.

## Changed-scope runner

`env PE_TESTS_FAST_LOCAL=1 bash tests/run-all.sh --scope changed` (repo root, lane
worktree): `run-all: 5 passed, 5 failed, scope=changed`. The five failures:

- `test-claude-profile-select.sh` — T33a/T36a, classified above.
- `test-balancer-ranks-by-usable-now.sh` — green before (PASS=18 FAIL=0) → PASS=14
  FAIL=4 after. All four are the same presentation drift (S1b/S1c/S1d/S4b assert
  `rank_by=usable_now_max` / `binding=seven_day:…` / `windows=…:seven_day=…`); the
  winner (`profile=fastreset`) is unchanged in every failing case. Cause class
  `test_encodes_superseded_requirement` (same founder order, 2026-09-16); the suite is
  outside the write set, so it stays red and named. Not a selection change.
- `test-balancer-every-arm.sh` — PASS=17 FAIL=5 **before and after** (identical S6
  spawn-failure cases; dispatch-spawn environment, not this diff). Pre-existing.
- `tests/test-status-surface-bash32.sh` — file untouched by this lane; failed inside the
  run-all invocation but passes standalone on rerun (rc=0) — the known `_t6b/_t6c`
  live-state flakes, see memory `status-surface-live-state-flakes`.
- `run-core-offline.sh` — see the self-check section; result reported with its boundary.

## Self-check (falsification set)

```
bash -n plugins/leadv2/scripts/leadv2-claude-profile-select.sh        -> OK
python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py \
                        plugins/leadv2/scripts/leadv2-quota-read.py   -> OK
bash -n plugins/leadv2/scripts/tests/test-five-hour-window-ranks-by-reserve-01.sh -> OK
```

Red before / green after for the new suite: `pass=2 fail=3` (rc=1) → `pass=5 fail=0`
(rc=0), boundaries as above.

## Left red, and why

1. `test-claude-profile-select.sh` T33a, T36a — superseded presentation assertions;
   suite outside write set.
2. `nc-claude-profile-select.sh` T33a, T36a — same; its other 13 fails + NC2-SETUP-FAIL
   are pre-existing on HEAD.
3. `test-balancer-ranks-by-usable-now.sh` S1b/S1c/S1d/S4b — same superseded presentation;
   suite outside write set.
4. `test-balancer-every-arm.sh` S6 family — pre-existing (17/5 before and after).
5. `tests/test-status-surface-bash32.sh`, `run-core-offline.sh` — not touched by this
   lane; pre-existing/environment, boundaries in the changed-scope section.

## Final foreground verification correction (authoritative)

The earlier draft table above was superseded by the final lane run at commit pending
on macOS Darwin 25.6.0. The focused picker suite was green: `pass=5 fail=0`, rc=0.
The selector regression was green: `PASS=152 FAIL=0`, rc=0. Its two temporary
presentation failures were fixed without changing the comparison: old diagnostic
fields are retained only for a sole live candidate, or when all compared five-hour
reserves tie and the weekly rate is genuinely decisive.

Raw required-suite results (6 suites attempted, not a claim about other platforms):

```
test-claude-profile-select.sh: PASS=152 FAIL=0 rc=0
test-profile-select-skips-exhausted.sh: PASS: 2 cases rc=0
test-quota-weekly-live.sh: PASS=8 FAIL=0 rc=0
test-quota-weekly-total.sh: PASS=13 FAIL=0 rc=0
test-claude-profile-requested.sh: rc=1, setup failed: mktemp Operation not permitted
test-quota-unknown-surfaces.sh: SUMMARY: PASS=3 FAIL=11 rc=1, setup failed: mktemp Operation not permitted
nc-claude-profile-select.sh: environment-derived identity failures (TMPDIR setup); not a picker regression
```

Cause class for the three non-green named runs is `environment_dependent`: this
container's inherited temporary-directory path rejects `mktemp`, then each suite
attempts to create paths rooted at `/`. The successful selector suite used its own
writable temporary path and proves the changed picker/select path. No assertion,
grep, or test was loosened.

Final syntax/diff falsification output:

```
bash -n plugins/leadv2/scripts/leadv2-claude-profile-select.sh -> OK
bash -n plugins/leadv2/scripts/tests/test-five-hour-window-ranks-by-reserve-01.sh -> OK
python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py plugins/leadv2/scripts/leadv2-quota-read.py -> OK
git diff --check -> OK
```
