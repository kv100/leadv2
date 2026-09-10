# W1-ARBITER-SUITE-THREE-RED-01 — round 2 report

Lane `633d067d3f98`, 2026-09-10. Governing document: the lead correction
(ПОПРАВКА ЛИДА, round 2), read together with `brief.md`.

## Outcome in one line

The round-2 rejection was **two trees, not a compliant suite**: the committed
suite DOES go red under the lead's exact mutation when the mutation and the
suite hit the same file — reproduced in place on the lane's real lib
(`SUMMARY: pass=22 fail=5`, named reds **(g7)** and **(g7-gap)**) — while the
lead's `pass=27 fail=0` is only constructible as *round-1 suite (worktree-only,
unmerged) + unmutated lib*: the mutation landed in the canonical checkout, the
suite sourced the lane worktree's clean lib. Structural fix: every suite run
now prints `arbiter_under_test=<path> sha256=<prefix>` (green and red alike),
so a cross-tree run is visible in the artifact itself. **(d2) untouched,
assertion count 27, arbiter lib byte-untouched.**

## 1. Why the lead measured green (mechanism, evidence)

1. `893193cc` (the round-1 re-pin, 27 assertions) exists **only** on
   `worktree-633d067d3f98`; main's last commit touching the suite is
   `80b2b73f` (pre-round-1). A `pass=27 fail=0` line requires the re-pinned
   suite ⇒ that run happened **in the worktree**.
2. The worktree lib was clean at session start (`git status`: only this
   report untracked; `grep -c no_capable_cell` = 4) ⇒ the suite sourced
   **unmutated** bytes there.
3. Same-tree repetition (artifact `mutation-control/20260910T043948Z-inplace.txt`):
   the lead's exact substitution applied to the lane's real lib —
   `grep -c no_capable_cell: 4 -> 2`, byte-identical to the lead's own
   measurement — suite goes **red**: `rc=1`, `pass=22 fail=5`. The suite's own
   first line inside that red run carries the *mutated* sha
   (`11ee23f6a2c6c4a6…`; the green run prints `5b4e4eaaa7ae161b`): the
   mutation and the suite provably hit one and the same file.
4. Conclusion: mutation in canonical main + suite in the lane worktree. A
   suite cannot observe a mutation applied to a file it does not source; no
   rewrite of assertions fixes that class — **observability** does. Since
   `d0968dcf` every run self-identifies, so the lead's green artifact would
   have shown `arbiter_under_test=…/worktrees/633d067d3f98/… sha256=5b4e4eaa…`
   (unmutated) next to a mutation applied elsewhere — the split would have
   been visible, not inferable.
5. One-command independent repetition for the lead, in any checkout that
   contains this task dir (canonical after merge included):
   `bash docs/handoff/w1-arbiter-suite-three-red/mutation-control/reproduce-lead-mutation.sh`
   — mutates THAT checkout's real lib, runs THAT checkout's suite, restores,
   verifies byte-identity, and tees a timestamped log next to itself.

## 2. Round-2 requirements, item by item

1. **(d2) — left as is** (per the correction): still asserts the
   capability_fit rank; PASS in both the green and the mutated runs
   (`standard cell deterministically picks glm (capability_fit rank, not
   stickiness)` — the mutation does not touch that path).
2. **(g7)/(g7-gap) — red under the named mutation, named tests:**
   - **(g7)** → `FAIL: arm_excluded protected=arm=sonnet … | unprotected=… | hole=…`
     (the hole half loses its `reason=no_capable_cell` token);
   - **(g7-gap)** → `FAIL: refusal-dictionary policy=… | vocabulary=…` (both
     descriptors would agree on one token — exactly what this case forbids);
   - collateral reds reading the same token: **(g)**, **(g-red)**,
     **(g8-refuse)** — a collapsed dictionary stays loud everywhere it is read.
   Assertion semantics are unchanged from `893193cc` (they already
   distinguished; the comments now name the lead's mutation as the negative
   control, and the run header makes the red self-proving).
3. **Three refusal states — the direct answer:** see §3.

## 3. The three refusal states (code-grounded, lib byte-untouched)

The code has **two reason tokens covering the lead's three named situations**,
plus one genuinely distinct third refusal token:

| situation (lead's words) | reason token | where | arms named? |
|---|---|---|---|
| political cut (arms removed by policy) | `pool_empty_all_excluded` | lib:1310-1311 | yes — `arm:stage`, e.g. `glm:untrusted` |
| dictionary hole (no fitting cell) | `no_capable_cell` | lib:1294-1295 | silent |
| pool empty after exclusions | `pool_empty_all_excluded` — **same token as the political cut** | lib:1310-1311 | yes — stage suffix differs: `:not_in_pool` / `:not_launchable` |

- The political-vs-pool distinction lives **only in the per-arm stage suffix**
  of `arm_excluded`; the reason token itself does not split them. So at token
  level there are **two** states for these three situations — said straight,
  as the correction demands.
- The **third distinct refusal name is `all_arms_capped`** (arms survived the
  stages, quota ceilings removed them all) — that is where a third name is
  used, pinned by suite case **(b)**.
- Suite coverage of all three situations: policy cut — (g7)/(g7-gap)
  (`pool_empty_all_excluded` + `glm:untrusted`); hole — (g7)/(g7-gap)
  (`no_capable_cell`, silent); capped — (b) (`all_arms_capped`).
- Known residual, flagged not fixed (out of write set, unchanged from round 1):
  the **pool-miss** sub-case (a bound pool naming no fitting arm) also prints
  `no_capable_cell` (lib:1293, `not (_bound_pool & set(_arm_cells))`) — but
  WITH `arm_excluded=<fitting>:not_in_pool`, unlike the pure hole. Pinned by
  `plugins/leadv2/tests/test-fable-cheapest-capable.sh:80`; that suite re-run
  green this round (2/0). `no_capable_cell` is therefore not *exclusively* the
  hole; the suite's hole descriptors are kind-misses, the pure sub-case.

## 4. Acceptance evidence

1. **Green run (final committed state)** — full output in §5.1:
   `SUMMARY: pass=27 fail=0`, rc=0. **The number is 27** — nothing deleted;
   (g7) extended in place back in round 1; round 2 added zero assertions.
2. **Mutated run (lead's exact substitution, in place on the real lane lib)**
   — full output in §5.2: `SUMMARY: pass=22 fail=5`, rc=1, named reds (g7),
   (g7-gap) (+ (g), (g-red), (g8-refuse)).
3. **Artifacts** in `docs/handoff/w1-arbiter-suite-three-red/mutation-control/`:
   - `20260910T043844Z-81424.txt` — `leadv2-mutation-control.sh` run with the
     lead's substitution as the anchor (scratch-copy tool run, `MUTATION-CONTROL
     ok`, lane_diff_hash bound to `d0968dcf`);
   - `20260910T043948Z-inplace.txt` — the in-place same-tree cycle: sha before
     → mutated sha → suite red → git restore → sha verified back;
   - `reproduce-lead-mutation.sh` + `20260910T044224Z-reproduce.txt` — the
     one-command repetition for the lead, self-tested end to end (§5.3).
4. Guard suites (same lib, unchanged bytes): `test-arm-pool-reachability.sh`
   19/0, `test-route-arbiter-spend-forecast.sh` 9/0,
   `test-fable-cheapest-capable.sh` 2/0, `test-headroom-continuous.sh` 9/0
   (brief acceptance §2).

## 5. Raw runs

### 5.1 Green (final committed state)

```text
GREEN_RUN_PLACEHOLDER
```

### 5.2 Mutated in place (lead's substitution, real lane lib, restored after)

```text
MUTATED_RUN_PLACEHOLDER
```

### 5.3 reproduce-lead-mutation.sh self-test

```text
REPRODUCE_PLACEHOLDER
```

### 5.4 Changed-scope runner

```text
CHANGED_SCOPE_PLACEHOLDER
```

## 6. Self-check (falsification set)

- `bash -n plugins/leadv2/scripts/tests/test-route-arbiter.sh` → OK (rc=0).
- No Python files changed (`py_compile` N/A).
- Lib restored and verified byte-identical after every mutation cycle
  (`git diff --quiet` clean; sha round-trip inside each artifact).
- Changed-scope runner: §5.4.

## 7. Files changed (round 2)

- `plugins/leadv2/scripts/tests/test-route-arbiter.sh` (+19: run header +
  two negative-control comments; semantics and count untouched) — `d0968dcf`.
- `docs/handoff/w1-arbiter-suite-three-red/` — this report, mutation-control
  artifacts, `reproduce-lead-mutation.sh`.
- NOT changed: `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`
  (byte-untouched both rounds — the dictionary the correction asked to
  verify exists and is load-bearing), `config/leadv2-routing.yaml`.
