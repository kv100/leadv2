# GLM-FIRST-RECOVERY-01 — report

**Task:** dispatch-24bab870 · **Repo:** `~/Projects/leadv2` (plugin canonical, worktree
`.claude/worktrees/24bab870`) · **Date:** 2026-08-15

## What the resolver was actually doing

Two mechanisms composed into the 90 `arm_resolved job=build arm=sonnet
reason=codex_quota_gate_80pct` rows:

1. **Codex's probe was stuck unknown.** The Codex quota login expired (`refresh http 401`),
   so `live_codex_weekly_pct` returned `None` on every dispatch. A prior deliberate fix
   ("quota unknown != known-0%") resolves that as `codex_blocked=True` — correct on its own:
   don't send work to an arm whose admission you cannot read.
2. **The spill walk deleted GLM from the candidate chain.** When the gate fired, the walk
   skipped `base_arm` ("already overridden by the precedence rules") unconditionally. Of the
   seven precedence rows, six are genuine *exclusions* of GLM — but
   `codex_fitting_mission_kind` is a *preference* (GLM is fine; Codex merely fits better),
   and it is the **only** row that can reach the walk (the other six resolve to
   opus/sonnet/kimi, never codex). So the skip was wrong in 100% of the cases where it
   fired: `[glm, codex, sonnet]` minus codex minus glm left **sonnet as the only arm**,
   forever — GLM's own quota (2%/40% at the time) was never read on the build path.

**Not staleness:** `resolve_arm()` re-resolves from live conditions on every dispatch; the
resolver holds no state and the on-disk lockout store was TTL-expired for both providers. No
cache, timer, or recovery daemon was needed (and none was built — design §1.4/§4).

## The change (scoped design §2, all four items)

| item | what | where |
|---|---|---|
| C1 | `glm_excluded` boolean per precedence-table row; the spill walk skips `base_arm` only when the fired row *excluded* GLM | `leadv2-glm-policy-resolve.py` `resolve_glm_policy` |
| C2 | spill candidates with a **known ≥ threshold** reading step aside; unknown keeps them eligible; sonnet terminal, never filtered; codex's unknown-blocks semantics untouched | same, walk loop + new `_live_pct_for_arm` |
| C3 | additive `readings=glm=<pct\|unknown> codex=… anthropic=…` line, gate-path only, memoised per process (`_LIVE_PCT_MEMO`); `dispatch-code.sh` parses it and appends it to the `arm_resolved` journal emit | resolver `_main` + `leadv2-dispatch-code.sh` |
| C4 | router.sh import-mode parity: verified, **no edit** — it reads only `arm`/`rule`/`reason` keys (additive `readings` is ignored), and it passes `enable_codex_fitting_rule=False` so its walk path (`base_arm=codex`, review) has an identical skip set to before | verified by code read + `test-review-pool-never-empty.sh` (incl. `test-routing-enforcement-p1.sh` 18/18) |

`arm=`, `rule=`, `reason=`, `tier=`, `codex_quota_blocked=` string values are **unchanged**;
absent a gate block or a blocked codex, output is byte-identical (v1 equivalence, suite case 7).

## Before / after — identical mission (codex_fitting kind), identical readings

Full transcript: [`before-after.txt`](before-after.txt). Condensed:

| scenario | BEFORE (HEAD) | AFTER |
|---|---|---|
| codex probe **unknown** (stuck 401), glm 2% | `arm=sonnet` | **`arm=glm`** + `readings=glm=2% codex=unknown anthropic=44%` |
| codex probe unknown, glm **known-hot 95%** (≥80) | `arm=sonnet` | `arm=sonnet` (R2 guard holds) + `readings=glm=95% codex=unknown anthropic=44%` |

The recovery is automatic: the next lane re-resolves from live conditions, which it always
did — the structural exclusion is what removed the path back.

## Tests (honest results)

| suite | result |
|---|---|
| `tests/test-glm-first-recovery.sh` **(new)** — 9 design cases, 11 assertions, incl. case 9 end-to-end through the real `leadv2-dispatch-code.sh` with a stub journal (`--no-spawn`, gates off) | **11 passed, 0 failed** |
| `tests/test-kimi-spill-resolve.py` — updated per R1 (see below) | **11 passed, 0 failed** |
| `tests/test-dispatch-arm-vocabulary.sh` | PASS 3/0 |
| `tests/test-plan-arms-role-scoped.sh` | PASS 4/0 |
| `tests/test-codex-quota-gate.sh` | PASS 10/0 |
| `tests/test-lock-busy-reresolve.sh` (spill-walk neighbour) | PASS 5/0 |
| `tests/test-review-pool-never-empty.sh` (incl. routing-enforcement-p1 18/18) | exit 0 |
| `bash -n` dispatch-code.sh · `py_compile` resolver | OK |

Notes:
- **`test-review-arm-pool.sh` (named in the design) does not exist** — the repo's review-pool
  suites are `test-review-pool-never-empty.sh` / `test-review-engine-pool-degrades.sh`; the
  former was run green (it sub-runs the review/routing suites).
- **R1 declared change:** `test-kimi-spill-resolve.py` expectations were updated, not
  silently rewritten — two of its tests were **already failing on main** (`arm=sonnet` vs the
  asserted `kimi`) because DISPATCH-KIMI-ARM-MISMATCH-01 removed kimi from
  `DISPATCHABLE_BUILD_ARMS`; after C1 the same scenarios recover to `glm`. Renamed to say so
  (`test_kimi_chain_recovers_to_glm`, `test_pre_kimi_chain_recovers_to_glm`,
  `test_quota_unknown_is_blocked_and_recovers_to_glm`), each with a comment naming R1.
- Gates: the lane-level e2e/review gates run in the product-close path, not in this
  implementation session; the end-to-end evidence here is suite case 9 (real dispatcher,
  real resolver, stubbed quota + journal) plus the before/after pairs above.

## Out of scope (unchanged, per design §4)

No decision cache / timer / daemon; no change to `arm=`/`rule=`/`reason=`/`tier=`/
`codex_quota_blocked=` values; no hardcoded arm list (spill order stays YAML-driven; the
`glm_excluded` flag lives in the precedence table that already governs it); no change to
`_lockout_blocked` or the lockout store; no change to `resolve_review_pool` thresholds or
the kimi probe gate; the unknown-Codex-blocks-Codex fix stands; no Codex re-login, no
deploy, no merge, no router-v2 changes. The Codex 401 itself remains — but after this fix it
costs nothing (lanes go to GLM, the founder's primary) and is visible for the first time via
`readings=`.

## Files

| file | change |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` | C1 (glm_excluded), C2 (`_live_pct_for_arm` + walk filter), C3 (`_fmt_readings` + `_LIVE_PCT_MEMO` + additive output) |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | C3 — parse `readings=` from the resolver, append to the `arm_resolved` emit |
| `plugins/leadv2/scripts/leadv2-router.sh` | none (C4 verified parity) |
| `plugins/leadv2/scripts/tests/test-glm-first-recovery.sh` | new suite, design §5 cases 1–9 |
| `plugins/leadv2/scripts/tests/test-kimi-spill-resolve.py` | R1 expectation updates |

R5 verified: persona-engine's `leadv2-glm-policy-resolve.py` is a symlink to canonical
(one inode, no copy to drift). No hook changes, so the plugin cache is not involved.
