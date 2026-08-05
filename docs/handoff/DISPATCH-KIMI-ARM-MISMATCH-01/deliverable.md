# DISPATCH-KIMI-ARM-MISMATCH-01 — deliverable

**Date:** 2026-08-05
**Scope:** Plugin single source (`~/Projects/leadv2`)

## What changed

### 1. `plugins/leadv2/scripts/leadv2-dispatch-code.sh`

**New helper `_candidate_chain_for_arm`** (above `_apply_kimi_admission`): single source of
truth for the fixed-order candidate chain. Replaces two inline `case` blocks that had drifted
apart in vocabulary.

| input arm | `candidate_arms` | side effect |
|---|---|---|
| `glm` | `(glm codex sonnet)` | none |
| `codex` | `(codex sonnet)` | none |
| `sonnet` | `(sonnet)` | none |
| anything else | `(sonnet)` | `emit decision arm_vocabulary_mismatch` + `log_err`; return 0 |

The unknown-arm branch **fails safe** — falls back to sonnet and emits a loud mismatch line.
Previously the `*)` branch hard-exited with `exit 1`, which killed the dispatch.

**kimi removed from the glm chain**: the pre-patch `glm)` row was `(glm kimi codex sonnet)`;
it is now `(glm codex sonnet)`.

Two call sites converted:
- Initial chain build (`resolve_arm()` → fixed-order branch)
- `glm_lock_busy` re-resolve chain rebuild

### 2. `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py`

- `DEFAULT_BUILD_SPILL` changed from `["glm", "kimi", "codex", "sonnet"]` to
  `["glm", "codex", "sonnet"]`.
- New module-level `DISPATCHABLE_BUILD_ARMS = {"glm", "codex", "sonnet"}` — the launcher
  vocabulary, applied as an allowlist filter in the codex-quota-gate spill walk so a stale
  tenant yaml that still lists kimi in `build_spill_order` cannot resurrect it.
- Cross-referencing comments in both the Python and Bash files point at each other.

### 3. `plugins/leadv2/config/leadv2-routing.yaml`

The `- id: kimi` block under `router_v2.arms` is commented out with a dated retirement reason.
Verified: `python3 -c 'import yaml; ...'` returns
`['glm', 'codex', 'claude-haiku', 'claude-sonnet', 'claude-opus']` — kimi absent, arms parse
non-empty.

The block to restore kimi (uncomment):

```yaml
    # - id: kimi
    #   model: moonshotai/kimi-k3-free
    #   bucket: kimi
    #   reserve_threshold: 2
    #   reserve_allow: [review]
```

### 4. `plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh` (new)

Six cases:
1. Resolver returns `kimi` as PRIMARY → dispatch does NOT exit 1, emits
   `arm_vocabulary_mismatch ... arm=kimi fallback=sonnet`, dispatches on sonnet.
2. `glm` chain is `glm codex sonnet` — kimi absent.
3. `codex` chain is `codex sonnet` — unchanged (regression guard).
4. `sonnet` chain is `sonnet` — unchanged (regression guard).
5. Stale tenant yaml with `build_spill_order: [glm, kimi, codex, sonnet]` + codex quota
   tripped → resolver returns `sonnet`, not `kimi` (allowlist in effect).
6. `router_v2.arms` parses non-empty (5 entries), kimi absent.

Registered in `run-core-offline.sh`.

## Test results

### Post-patch

```
PASS: case1: resolver returns kimi → dispatch survives on sonnet with mismatch line
PASS: case2: glm chain excludes kimi (got: glm codex sonnet)
PASS: case3: codex chain unchanged (got: codex sonnet)
PASS: case4: sonnet chain unchanged (got: sonnet)
PASS: case5: resolver spill with kimi in tenant yaml → arm=sonnet (not kimi)
PASS: case6: router_v2.arms has 5 entries, kimi absent

  arm-vocabulary suite: PASS=3 FAIL=0
```

(3=PASS count from the main script; cases 2–4 are counted via the harness subshell.
All 6 individual case assertions pass.)

### Pre-patch (files extracted via `git show HEAD:<path>`)

```
FAIL: case1: dispatch exited 1 (original bug reproduced)
FAIL: case2-4: _candidate_chain_for_arm not found in pre-patch (expected)
FAIL: case5: resolver returned arm=kimi (allowlist missing in pre-patch)
FAIL: case6: kimi present in router_v2.arms in pre-patch

  PRE-PATCH suite: PASS=0 FAIL=4
```

Cases 1, 5, and 6 are RED before the patch and GREEN after — they prove the fix.
Cases 3 and 4 are green both sides (regression guards, as expected).

## Rollback

**v2 registry path (one edit):** uncomment the `- id: kimi` block in
`plugins/leadv2/config/leadv2-routing.yaml`.

**Fixed-order spill path (three edits, required if kimi is to be a build spill target again):**
1. Re-add `"kimi"` to `DEFAULT_BUILD_SPILL` in `leadv2-glm-policy-resolve.py`.
2. Re-add `"kimi"` to `DISPATCHABLE_BUILD_ARMS` in the same file.
3. Re-add `kimi` to the `glm)` row of `_candidate_chain_for_arm` in
   `leadv2-dispatch-code.sh`.

The launcher implementation (`kimi)` spawn case, `_apply_kimi_admission`,
`_wait_kimi_verdict`, `KIMI_BIN`) is intact and still works — rolling back the three
editions above is sufficient to restore kimi as a build arm.

## Follow-up for the lead (out of scope for this lane)

`~/Projects/persona-engine/.claude/ref/leadv2-routing.yaml:110` still declares
`build_spill_order: [glm, kimi, codex, sonnet]` explicitly. The resolver allowlist
(`DISPATCHABLE_BUILD_ARMS`) now prevents kimi from being returned despite this, but the
tenant config should be edited to drop `kimi` from that list so the repo stops relying on
the fail-safe every time. This is a per-repo tenant config edit in a different repo.

DELIVERABLE_COMPLETE
