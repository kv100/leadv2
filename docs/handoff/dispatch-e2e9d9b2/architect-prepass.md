# PLUGIN-CORE-OFFLINE-4RED-01 — architect prepass (scoped implementation design)

Prepass ran the 4 red suites individually on untouched main (not the full 50-suite runner —
the previous prepass timed out doing that). Every classification below is backed by raw
output captured this session.

## 0. Suite → file map (from `run-core-offline.sh`)

| # | run_check name | suite file |
|---|---|---|
| 1 | dispatch refusal fallback chain | `plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh` |
| 2 | plugin sync quarantine/dry-run safety | `plugins/leadv2/scripts/tests/test-drift-guard-quarantine-perimeter.sh` |
| 3 | foreground-dispatch guard hook | `plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh` |
| 4 | lane truth batch (log_path + quarantine convergence) | `plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh` |

## 1. Root-cause table (a = test drifted, b = code regressed, c = env-coupled)

| # | Suite | Class | Root cause (evidence) |
|---|---|---|---|
| 1 | routing-enforcement-p1 | **c (+a)** | Test's fake codex (`make_live_codex`) never emits a byte the codex first-byte probe can see. `_codex_first_byte_deadline_check` (`leadv2-dispatch-code.sh:2987`) defaults `LEADV2_CODEX_FIRST_BYTE_SECS=180` → after 180 s wall clock the arm is declared `no_first_byte`, so `worker_spawned by=router model=codex` never appears and the chain rolls back. Contract added by CODEX-DOOR-DEAD-01 §2/§3 *after* the fixture was written. |
| 2 | drift-guard-quarantine-perimeter | **a** | Contract changed by `07d8c56 fix(drift-guard): commit direction-aware guard + backward-sync refusal (DRIFT-GUARD-ADVISES-BACKWARD-SYNC-01)`. Guard now refuses when target content "is not reachable in canonical history" and performs **no quarantine and no target write**; the test still asserts quarantine-then-reconcile. |
| 3 | fg-dispatch-guard | **a** | Contract changed by `7ea5816 perf(hooks): merge 13 PreToolUse[Bash] hooks into trigger-manifest dispatcher`. `leadv2-block-fg-dispatch.sh` is no longer named in `hooks/hooks.json`; it is invoked by `hooks/leadv2-bash-pre-dispatch.sh`. Assertion #20 greps `hooks.json` for the filename → FAIL. |
| 4 | lane-truth-batch-01 | **a** (same family as #2) | Passes Rows 1–3 including "dry-run reports block without writing quarantine", then aborts under `set -e` at the `--write` quarantine-convergence step, for the same direction-safety refusal introduced by `07d8c56`. |

### Raw evidence (before)

```
# 1 — test-routing-enforcement-p1.sh (killed at 200s, still running; gate log shows FAILED)
FAIL: quota refusal advances chain -- rc=4
  [leadv2-dispatch-code] arm_refused by=router model=glm  reason=glm_refused_quota_gate
  [leadv2-dispatch-code] arm_refused by=router model=codex reason=no_first_byte
  [leadv2-dispatch-code] dispatch_rolled_back reason=all_arms_unavailable
      attempts=glm_refused_quota_gate,codex_dead_no_first_byte

# 2 — test-drift-guard-quarantine-perimeter.sh  EXIT=1
FAIL: quarantine: cache/probe.sh should be reconciled to canonical
FAIL: quarantine: expected preserved copy under .../q-quarantine/*/cache/scripts/probe.sh — NONE FOUND
FAIL: quarantine: preserved content must byte-match the un-landed fix (path=)
FAIL: quarantine: warning must name warn+quarantine + quarantine path
  stderr: WARN: DRY_RUN DIRECTION-SAFETY (would quarantine+reconcile): ... content is not
          reachable in canonical history for plugins/leadv2/scripts/probe.sh.
          No quarantine or target write performed.
TESTS FAILED

# 3 — test-fg-dispatch-guard.sh  → [fg-dispatch-guard] PASS=34 FAIL=1
[TEST] FAIL: hook not found in hooks.json

# 4 — test-lane-truth-batch-01.sh  EXIT=1
... [TEST] PASS: Row 3: dry-run reports block without writing quarantine
... [TEST] PASS: Row 3: dry-run writes no quarantine files
[plugin-sync] user-scripts: delivered=0 skipped=1 (of 1 canonical entries)
<aborts, no further assertions>
```

Note the mission's round-1 observation (a real `glm_refused_quota_gate,...` line appearing
inside a test run) is explained by #1: it is the test's own fixture output, not live-state
bleed — but see Risk R2, the dead-arm path *does* write real lockout state.

## 2. Changes — exact, per suite

### Suite 1 — `test-routing-enforcement-p1.sh` (deterministic + fast)
1. In `make_live_codex`, make the fake emit what `_codex_first_byte_probe` reads for the
   handle it prints, so "codex is alive" is proven, not assumed. Implementer must read
   `_codex_first_byte_probe` in `leadv2-dispatch-code.sh` and mirror its expected artifact
   (job/handle output path) in the fixture.
2. Export `LEADV2_CODEX_FIRST_BYTE_SECS=2` (not `0`) in every case that uses `live-codex.sh`.
   Rationale: `0` disables the deadline entirely and would make step 1 unfalsifiable; `2`
   keeps the deadline armed while bounding wall clock.
3. Add one **new** case that keeps the dead-arm path covered: a codex fake that emits
   nothing, `LEADV2_CODEX_FIRST_BYTE_SECS=1`, asserting `reason=no_first_byte` **and**
   spill to the next arm. This is the assertion currently being obtained by accident.
4. Point `record-quota-lockout` at the fixture root for these cases (see Risk R2).

**No assertion is weakened**: the suite still requires `worker_spawned by=router model=codex`,
still forbids `dispatch_rolled_back`, and now additionally proves the dead-arm branch.

### Suite 3 — `test-fg-dispatch-guard.sh` (assertion #20 only, lines 209–219)
Replace the single `grep hooks.json` with a two-part registration proof that matches the
post-`7ea5816` topology, both parts required:
- `hooks.json` is valid JSON **and** registers the dispatcher `leadv2-bash-pre-dispatch.sh`
  on `PreToolUse`;
- the dispatcher (or its trigger manifest, whichever the implementer finds `leadv2-bash-pre-dispatch.sh`
  reading) names `leadv2-block-fg-dispatch.sh`.

Strictly stronger than the old grep: it proves the guard is reachable from a registered
entry point, not merely that a string exists in a file.

### Suites 2 + 4 — one shared root cause, fix once
Both fail at the same juncture: post-`07d8c56` the guard refuses to quarantine when the
divergent target's content is **not reachable in canonical git history**.
Implementer must first determine which of the two contracts is intended:

- **(i) the guard is right** → the fixtures are unrealistic: they create a divergent target
  whose content was never committed. Fix = fixtures commit the "un-landed fix" content into
  the fixture's canonical history (or the tests assert the *refusal* contract:
  no quarantine, no target write, warning names the unreachable-content reason).
- **(ii) the guard is wrong** (class **b**) → `07d8c56` regressed the QUARANTINE-CONVERGENCE
  invariant that `ce7fe61`/`7235286` landed for LANE-TRUTH-BATCH-01, and the fix belongs in
  `leadv2-plugin-sync.sh`.

**Decide with evidence, not preference**: read `07d8c56`'s message and diff plus the
LANE-TRUTH-BATCH-01 quarantine spec. If (ii), the write set extends to
`plugins/leadv2/scripts/leadv2-plugin-sync.sh` and the deliverable must say so explicitly.
Under either branch, "3 syncs → 1 copy" convergence must remain asserted.

## 3. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Fixing #2 by asserting the refusal contract silently drops quarantine coverage | Keep a positive quarantine case whose fixture content **is** canonical-reachable; assert both branches |
| R2 | `_codex_first_byte_deadline_check` calls `record-quota-lockout --provider codex --hours 1` — a test run can stand down the founder's real codex arm for an hour | Confirm the fixture's `CLAUDE_PROJECT_ROOT` / `LEADV2_DISPATCH_CACHE_DIR` actually scopes lockout writes; if not, that is a genuine class-**b** finding and must be reported, not patched around |
| R3 | Suite 1 currently costs ≥180 s per dead-arm case — this is what timed out the previous prepass | Step 2 above bounds it to seconds; re-time the suite and record wall clock in the terminal artifact |
| R4 | If (ii) holds and `leadv2-plugin-sync.sh` changes, blast radius covers every repo's sync path | Run `test-drift-guard-safety-fixes.sh` + `test-lane-truth-batch-01.sh` + full core-offline twice |
| R5 | Fixing a hook file requires a plugin-cache copy + session restart to go live | Current design touches **no** hook file; if that changes, say so in the deliverable (mission requirement) |
| R6 | Flake: two of these suites touch tmp roots and `SECONDS`-based deadlines | Acceptance requires two back-to-back green runs |

## 4. Non-goals (implementer ignores these)
- `test-lane-writes-scoping` C3/L12 — separate known pre-existing failure.
- Any gate-policy change; any change to `leadv2-dispatch-product-close.sh` logic from
  `019ec29` / `85ae886` beyond test-only interaction.
- New features; refactors of the hook trigger-manifest; deleting or renaming suites.
- Weakening or deleting any assertion to obtain green.
- `.claude/scripts/tests/` duplicate-tree cleanup (open thread, separate blast radius).

## 5. Verification sequence
1. Each suite individually: raw red (captured above) → raw green.
2. `bash -n` + `shellcheck` on every touched file.
3. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` **twice** back-to-back.

acceptance:
  surface: rendered_line
  observable: "The final line printed by `run-core-offline.sh` reads `[CORE-OFFLINE] suites passed=50 failed=0 missing=0 repo=<lane tree>`, and reads the same on an immediate second run."
  authored_at: 2026-08-19T08:05:00Z

acceptance:
  surface: file_artifact
  observable: "The task deliverable contains, for each of the four formerly-red suites, its raw red output, its raw green output, and a one-line root cause labelled a, b, or c."
  authored_at: 2026-08-19T08:05:00Z

LANE_WRITES: plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh, plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh, plugins/leadv2/scripts/tests/test-drift-guard-quarantine-perimeter.sh, plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh, plugins/leadv2/scripts/tests/fixtures/**, plugins/leadv2/scripts/leadv2-plugin-sync.sh

DELIVERABLE_COMPLETE
