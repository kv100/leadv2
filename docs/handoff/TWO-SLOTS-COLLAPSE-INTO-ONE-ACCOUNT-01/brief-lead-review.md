# TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01 — lead review, 2026-09-03

Reviewed by the lead session `fb` after the lane's worker died repeatedly and its work was rescued by
hand. Everything below was produced by running the code, not by reading it.

## Evidence: suites green, both negative controls bite

| run | result |
|---|---|
| `tests/test-claude-account-check.sh` | `PASS=15 FAIL=0` |
| `tests/test-claude-profile-select.sh` | `PASS=73 FAIL=0` |
| `tests/nc-claude-account-collapse.sh` — mutation inside `detect_same_account()` | suite `exit=1`, `PASS=65 FAIL=8`, `NC-PASS` |
| `tests/nc-claude-account-check.sh` — mutation inside `verdict()` | suite `exit=1`, `PASS=13 FAIL=2`, `NC-PASS` |

Both mutations are inserted **inside a function body**, not at file top level, and both NCs carry an
`NC-SETUP-FAIL` guard that aborts loudly if the target line ever changes shape — so the control cannot
silently degrade into mutating nothing. The suite is run against the mutated copy through
`LEADV2_TEST_SELECT_BIN` rather than against a hand-edited original. This is the strongest acceptance
shape any lane produced today.

`T5b` asserts no token value is printed even with a live keychain stub, which satisfies the standing
ban on logging credential values.

## Finding — the verdict ignores `organizationUuid`, and that is the exact failure class we were warned about

`verdict()` (`leadv2-claude-account-check.sh:142-165`) compares **only** `ACCOUNTS[]`, the pairwise
`accountUuid`. `organizationUuid` is collected and printed in the per-slot detail line, but never
enters the decision.

Two distinct `accountUuid`s that sit inside the **same organization** therefore report
`TWO_BUCKETS`. Rate limiting for an org applies at the org level — the script itself reads
`organizationRateLimitTier` at line 84 as a fallback for exactly that reason. So the check can answer
"two independent buckets" about a configuration that has one.

This is the same class c2 named: two working logins into one quota, reported as success. It is one
level up from the case the lane fixed — not two slots into one account, but two accounts into one org.

**Today the verdict is still correct** for the live pair: personal is `max` on a gmail identity with
no org; work is `team` under mythical.games. The gap is not currently firing. It matters because the
whole point of this check is to keep answering correctly **after** 15 September, when the founder may
move a slot in response to the Max 5x downgrade — which is precisely the moment someone would put two
seats in one org and read `TWO_BUCKETS` as reassurance.

Fix is small and local: one pairwise comparison on `organizationUuid` alongside the `accountUuid`
loop, with its own verdict word so the operator can tell the two collapse shapes apart, plus a
fixture pair (distinct accounts / same org) and a matching NC.

## Identity proof vs consumption proof — a limit worth stating plainly

Distinct `accountUuid` is an **identity-level** answer. The question the September plan actually rests
on is **consumption-level**: does spending on one slot leave the other's remaining quota untouched?
The two coincide for genuinely separate accounts, but the check does not demonstrate the second, it
infers it.

The instrument for the empirical version is the sibling lane
`QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01`, which turns the single overwritten `kv` row into
per-probe history. With that history, consumption independence is read from recorded probes —
a spend on one slot with no movement on the other — instead of being staged. Worth doing once that
lane lands; not a blocker for this one.

## Not yet satisfied from the original acceptance list

- **Linux container green.** Both suites ran on macOS only. The header claims `.claude.json` is
  present on a keychain-less Linux container and that a missing keychain never flips the verdict —
  `T4` covers that assertion on macOS with a stubbed absence, which is not the same as running there.
- **Runner registration.** The suite is registered in `plugins/leadv2/scripts/tests/run-core-offline.sh:424`.
  Confirm that is the runner CI actually selects for this repo, and that a change to
  `leadv2-claude-profile-select.sh` selects it — an unregistered suite rots silently.
