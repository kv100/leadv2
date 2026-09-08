REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=0 low=3

# Review of docs/handoff/dispatch-c4717023/review.diff

Scope: 3 files, 1551 diff lines — `plugins/leadv2/scripts/leadv2-quota-read.py`,
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`, and new test
`plugins/leadv2/tests/test-claude-account-states.sh`. Full diff read
(offsets 1-782, 783-1182, 1183-1550). No `context.yaml` present for this
review task.

## Summary of the change

1. `leadv2-quota-read.py`: adds a `claude-profiles.tsv` registry to filter
   which macOS Keychain "Claude Code-credentials*" services count as real
   multi-profile accounts (fails open/unfiltered if the registry is
   missing/empty/unreadable), and adds a three-state account classifier
   (`ok`/`unmetered`/`unknown`) so a team-tier account whose usage endpoint
   401s is priced conservatively instead of being conflated with a dead
   credential.
2. `leadv2-route-arbiter.sh`: propagates the new `unmetered` state through
   `util()`/`capped()`/`ufmt()`; replaces the flat capability-fit ban with a
   staged, auditable exclusion model (`not_in_pool`/`not_launchable`/
   `untrusted`/`capped`/`failure_memory`/`price_ratio`); adds cross-journal
   failure memory (bans an arm after N qualifying failures, with an explicit
   allow-list of failure causes and honest `unavailable`/`no_history`
   reporting instead of a false "zero"); adds an explicit-arm-request path
   with its own refusal reasons; adds an optional graduated capability-fit
   sort key (shadow-computed even when off); adds a headroom-weighted quota
   gradient (optional, rollback-flagged); and threads several new
   provenance/observability tokens onto the decision line
   (`kind_unmapped=`, `probe_outage=`, `failure_*=`, `headroom_*=`,
   `fit_*=`, `arm_excluded=`, revision hashes).
3. New test file exercises both quota-read fixes hermetically (no real
   keychain/network), including two negative-control mutations that prove
   the assertions actually detect a defeated fix.

This is dense, heavily self-documented code: nearly every non-obvious
decision carries a comment naming the incident/measurement that motivated
it. I did not find a functional break. All findings below are Low severity,
observability/messaging edge cases rather than incorrect behavior.

## Findings

### Low 1 — explicit-arm-request capped pre-check uses only one provider

`leadv2-route-arbiter.sh`, explicit-arm-request block:
```python
_pin_prov=next((c.get('provider') for c in _arm_cells[requested_arm]),None)
if capped(_pin_prov): _stage_add(requested_arm,'capped')
```
This samples only the *first* cell's provider for `requested_arm` to decide
whether to short-circuit with the specific `requested_arm_capped` (rc=70)
reason. If `_arm_cells[requested_arm]` ever spans cells with different
providers, a capped state on a later cell's provider would not be detected
here. The generic per-cell filter a few lines later (`ok=[c for c in
capable if not capped(c.get('provider'))]`) still removes the request
correctly, so the request is not mis-routed — it just falls through to the
generic `all_arms_capped` (rc=3) exit instead of the more specific
`requested_arm_capped` (rc=70), losing some of the "operator reads which
filter fired" precision this diff otherwise adds throughout.
UNVERIFIED: I did not read `config/leadv2-routing.yaml` (out of diff scope)
to confirm whether any arm's cells actually span multiple providers in
practice; if arms are always 1:1 with providers, this has no observable
effect.

### Low 2 — `no_capable_cell` fast-path checks pool-vs-all-cells, not pool-vs-fit

```python
_bound_pool=arm_pool if arm_pool is not None else (allowed if allowed is not None else set(_arm_cells))
if not _fit or not (_bound_pool & set(_arm_cells)):
    ... reason=no_capable_cell ... raise SystemExit(68)
```
The accompanying comment describes this as catching "the bound pool names
no arm that fits," but the guard checks `_bound_pool` against
`set(_arm_cells)` (every arm with *any* capability-matrix cell), not against
the arms in `_fit` (arms that fit this kind/size). A pool that names an arm
with cells for a *different* kind/size than requested would pass this guard
and fall through to `pool_empty_all_excluded` a few lines later instead of
`no_capable_cell`. Functionally inert — the comment explicitly notes both
paths exit with the same rc (68) so callers are unaffected — but the
`reason=` string on the decision line would not always match the comment's
description of when it fires.

### Low 3 — `_registry_keychain_services` exception scope (unverified against literal source)

Per the file-1 diff (fully read in an earlier pass of this review, diff
lines 1–251), `_registry_keychain_services()` wraps its TSV read in a bare
`except OSError` and returns an empty set (fail-open) on that path. A TSV
row with unexpected shape (e.g. missing tab-separated fields, causing an
`IndexError`, or a non-UTF8 byte causing `UnicodeDecodeError`) would not be
an `OSError` and would propagate instead of triggering the documented
fail-open behavior. The test suite's registry fixtures are all well-formed
TSV, so this path is untested. Low severity: the failure mode (an
unreadable/malformed registry crashing quota-read entirely) is the opposite
of the fail-open design intent, but requires a malformed on-disk file to
trigger, not a code-path reachable from any tested input.

## What I did not find

- No logic path where `unmetered`/`unknown` accounts get silently treated as
  `capped` (the stated regression this diff fixes) — `capped()`'s new early
  `return False` for `unk.get(provider)` or `account_state=='unmetered'` is
  correctly ordered before the ceiling/reset checks.
- No stage-exclusion mis-scoping: `capable = [c for c in _fit if
  c.get('arm') not in _stages]` is applied once, before the `capped` stage
  is populated (capped filtering happens separately via `ok=[...]`), so an
  arm is never banned from a cell it wasn't actually excluded from.
- Failure-memory ban application (`failure_banned`, `_kept`/`failure_dropped`)
  correctly yields (never deadlocks) when every capable cell is a repeat
  offender, and says so via `failure_memory='exhausted'`.
- The two negative-control mutations in the new test file are structurally
  sound: each asserts the *mutated* module disagrees with the expected
  correct-path result, so a silently-reverted fix would fail the suite, not
  just fail to demonstrate the fix.
- `read_anthropic()`'s removal of the `expiresAt` staleness gate does not
  open a path to a null/garbage `accessToken`; `at` truthiness is still
  checked before use, and the 200/429/other-code branches are exhaustive.

DELIVERABLE_COMPLETE
