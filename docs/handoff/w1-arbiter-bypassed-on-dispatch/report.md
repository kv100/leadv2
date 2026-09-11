# W1-ARBITER-BYPASSED-ON-DISPATCH-01 — report

Lane `dfc9444bd227` (row 1: ARBITER-REFUSES-INSIDE-DISPATCH-BUT-WORKS-ALONE-01; row 2
LADDER-FALLBACK-TELEMETRY-DIES-UNDER-SET-U-01 is fixed in the same lane because it
silenced exactly the line that explains row 1). Brief: PRE-WAVES-PLAN.md §1.7.

## Part A — root cause, one phrase

**The dispatcher's launchability seam `_arm_launchable_arms` was queried with
`kind=plugin`, a kind present in NO `capability_matrix` row, so the registry answered
`arm_not_capable_for_kind` for every arm and the seam returned an EMPTY csv with
rc=0 — and that empty list reached the arbiter as `launchable_arms: []` (a list,
never `None`), which staged every arm `not_launchable` and refused
`pool_empty_all_excluded` (rc=68); the dispatcher then fail-opened to the legacy
ladder while the arbiter itself was healthy (it coerces `plugin -> code` via its own
`kind_unmapped` rule).**

Working order was followed: the exact input was logged from the live journal, the
failure was reproduced manually BEFORE any edit, only then was the code changed.

### Live evidence chain (journal `~/.claude/leadv2-state/leadv2/tasks/dispatch-b0ec3b03/journal.md`)

```
- 2026-09-09T22:19:05Z [decision] dispatch_classified task=b0ec3b03 class=non_product reason=explicit_kind_plugin kind=plugin
- 2026-09-09T22:19:13Z [decision] launchable_seam task=b0ec3b03 source=registry kind=plugin
- 2026-09-09T22:19:17Z [decision] arbiter_broken task=b0ec3b03 rc=68 reason=fail_open_to_ladder arb_reason=pool_empty_all_excluded arb_kind=code
- 2026-09-09T22:20:01Z [decision] route_resolved by=router router=v1 model=glm task=b0ec3b03 rule=none reason=glm_default after=fail_open arb_rc=68
```

The `launchable_seam ... source=registry kind=plugin` line is the smoking gun: the
seam "succeeded" while answering nothing.

### The exact JSON the dispatcher passes the arbiter (`leadv2-dispatch-code.sh`, `_arb_desc` build)

```json
{"kind":"plugin","size":"standard","protected":true,"safety":false,"ui_judgment":false,
 "task":"<sig8>","allowed_arms":["glm","glm-flash","codex","sonnet","freepool"],
 "launchable_arms":[],"arm_pool":null,"complexity":"unknown","duration_class":"unknown",
 "test_only":0,"requested_arm":"","complexity_source":"unknown"}
```

`allowed_arms` comes from `_ladder_policy_arms` (the class ladder: `glm,glm-flash,codex,
sonnet,freepool` for `standard` — glm IS in it, so the briefed "first suspect", the
router's pre-arbiter `protected_path` exclusions of glm-flash/freepool, is NOT the
mechanism: those exclusions are correct, re-applied by the arbiter itself as
`untrusted`, and never touch glm). The difference from the working manual form is
exactly `launchable_arms: []`.

### Reproduction, before → after (real arbiter, real config, pre-edit bytes)

Seam query (`_arm_launchable_arms`'s registry call), same machine, pre-fix:

```
kind=plugin -> []          (rc=0 — "success", empty answer)
kind=code   -> [codex,freepool,glm,glm-flash,sonnet]
```

Descriptor replay through the live arbiter — BEFORE (the exact live input):

```
arm=refuse model=none tier=none reason=pool_empty_all_excluded kind=code chain= ...
arm_excluded=codex:not_launchable,freepool:not_launchable+untrusted,glm:not_launchable,
glm-flash:not_launchable+untrusted,sonnet:not_launchable+forecast ...
rc=68
```

AFTER (seam answers for the code vocabulary — the fix changes only the input):

```
arm=glm kind=code model=glm-5.3 tier=standard effort=high reason=cheapest_capable
chain=glm,codex ... kind_unmapped=plugin ... arm_excluded=codex:price_ratio,
freepool:untrusted,glm-flash:untrusted,sonnet:forecast ...
rc=0
```

Every arm `not_launchable` in the before-line is the empty list at work; `kind_unmapped=plugin`
in the after-line is the arbiter telling us it coerced the kind itself all along.

## Part A — what was changed (words, not diffs)

In `leadv2-dispatch-code.sh`, `_arm_launchable_arms` ONLY (no second resolver, no
second ladder, arbiter config untouched — off-limits files were read but never written):

1. **Vocabulary guard (the input fix).** A kind outside the matrix's own `kinds`
   vocabulary is queried as `code` — the SAME fail-open coercion the arbiter applies
   at its `kind_unmapped` line; the matrix itself is the vocabulary, so this cannot
   drift from it. The remap is journalled on the seam line (`kind_mapped=plugin->code`),
   never silent.
2. **Empty-answer contract (the seam's own honesty).** An EMPTY successful answer is
   never a routing verdict (no kind has an empty launchable set): it is seam
   degradation, the same legacy fail-open ladder posture as an unavailable registry,
   under its own loud reason `registry_empty_answer`. The arbiter's capability_matrix
   filter still binds on top, so the fallback can only widen the auction, never admit
   an arm the matrix refuses. This guard independently rescues the outcome even if
   guard 1 regresses — which is why the suite pins the seam line itself (see controls).
3. **Fail-open is now loud AND counted.** `_arb_fail_open_count` — a day-file counter
   (`.arbiter-fail-open-YYYYMMDD`, same lock+count shape as `_arm_exception_bump`,
   one row per task signature per day) — bumps at the two main worker-resolve
   fail-open sites, and the `arbiter_broken` line now carries `fail_open_count=N`.
   Fail-open itself is untouched: an arbiter fault still never stops work.

**Significance (as briefed):** every §1 arbiter-side behaviour — 1.1 balancing, 1.4
spend forecast, 1.6 granularity — lives INSIDE the arbiter. While the production path
fail-opened to the ladder, all of it was green in suites and dead in prod. The counter
now makes the bypass rate visible per day.

## Part B — telemetry guard

Live crash: `leadv2-dispatch-code.sh: line 2026: attempted: unbound variable` inside
`_route_arm_source_suffix()` — the function died exactly when it owed the
`arbiter_pick=... arm_source=ladder_fallback depth=... after=...` line.

**Measured mechanism (differs from the brief's premise — bash 3.2 survives every
state; the killer is the PATH bash):** the dispatcher's shebang `#!/usr/bin/env bash`
resolves to the first `bash` on PATH (5.3.9 here), and `leadv2-dispatch-code.sh:8849`
declares `local -a candidate_arms attempted` — declared, never assigned until the
first arm attempt. Matrix, measured on this machine:

| state of `attempted`      | /bin/bash 3.2.57 (old guard) | PATH bash 5.3.9 (old guard) |
|---------------------------|------------------------------|-----------------------------|
| declared, never assigned  | survives (n=0)               | **CRASH `attempted: unbound variable`** |
| assigned empty `=()`      | survives                     | survives                    |
| non-empty                 | works                        | works                       |

`declare -p attempted` succeeds for the declared-unassigned state, so the old guard
let the expansion through and `set -u` killed the function on `${#attempted[@]}`.

**Fix:** the guard now requires `declare -p`'s own rendering to name element zero
(`'([0]='`) before ANY array expansion — an unset, declared-unassigned or empty array
is never expanded, on any bash. Post-fix smoke: all four states × both bash versions
print the telemetry line (depth=0/after=unexplained for empties, depth=2/after=codex
for a populated array), rc=0 everywhere.

**Census of the same pattern in the file:** `declare -p` array guards — **exactly 1**
(the fixed one; no other occurrence). Adjacent `${#arr[@]}`-under-`set -u` sites
(`_LADDER_IDS` :2462-area, `_trusted` :2527-area, `_sized` :2561-area) all declare
with assignment (`arr=()` / `local -a arr=()`) before the check — the assigned-empty
state survives on both bash versions, so none of them carries the crash shape.

## Suites (both self-registered: `# run-all-triggers: leadv2-dispatch-code [leadv2-route-arbiter]`)

### test-arbiter-seam-plugin-kind.sh — green run (full)

```
PASS: bash syntax: dispatch
PASS: (g1) dispatch resolves the arm THROUGH the arbiter
PASS: (g1) no fail_open_to_ladder on the production path
PASS: (g2) dispatch resolves the arm THROUGH the arbiter
PASS: (g2) no fail_open_to_ladder on the production path
PASS: (g2) seam queries the matrix vocabulary and says so (kind_mapped=plugin->code)
PASS: (g3) empty launchable signal still refuses loudly (rc=68 pool_empty_all_excluded)
PASS: (g3) refusal names the not_launchable stage per arm
PASS: (g4) genuinely empty pool still refuses loudly (rc=68)
PASS: (g5) arbiter fault fail-opens loudly with a counted reason (fail_open_count=1)
PASS: (g5) second distinct task signature increments the day counter (fail_open_count=2)
PASS: (g5) counter day-file exists under the redirected state root (hermetic, count=2)
PASS: (red) with the vocabulary coercion reverted, the kind_mapped seam line is gone (suite red under this mutation)
PASS: (red) ...and guard 2 says so by name: source=legacy reason=registry_empty_answer (the documented outcome-level rescue)
---
PASS=14 FAIL=0
```

- g1 = the mission's manual form (`kind=code, protected=true, task_class=standard`):
  full dispatch, journal carries the arbiter decision line, no `fail_open_to_ladder`.
- g2 = the LIVE broken form (`--kind plugin`, no writes, manual `--protected`): now
  resolves by=arbiter, and the seam line `kind_mapped=plugin->code` is the detector.
- g3/g4 = acceptance 2: the refusal on a genuinely empty launchable signal / genuinely
  empty pool stays LOUD (rc=68 + `pool_empty_all_excluded` + per-arm stage tokens).
- g5 = the counter: faulting-arbiter stub → `arbiter_broken ... reason=fail_open_to_ladder
  fail_open_count=1`, second distinct task signature → `fail_open_count=2`, day-file
  `count=2` with both `sig8=` rows under the redirected state root.

### test-route-arm-source-suffix-unbound.sh — green run (full)

```
PASS: bash syntax: dispatch
PASS: extracted _route_arm_source_suffix from the live dispatch script
PASS: (s1-declared-unassigned) /bin/bash prints the ladder_fallback line (depth=0 after=unexplained)
PASS: (s1-assigned-empty) /bin/bash prints the ladder_fallback line (depth=0 after=unexplained)
PASS: (s1-nonempty) /bin/bash prints the ladder_fallback line (depth=2 after=codex)
PASS: (s1-unset) /bin/bash prints the ladder_fallback line (depth=0 after=unexplained)
PASS: (s2-declared-unassigned) /opt/homebrew/bin/bash prints the ladder_fallback line (depth=0 after=unexplained)
PASS: (s2-assigned-empty) /opt/homebrew/bin/bash prints the ladder_fallback line (depth=0 after=unexplained)
PASS: (s2-nonempty) /opt/homebrew/bin/bash prints the ladder_fallback line (depth=2 after=codex)
PASS: (s2-unset) /opt/homebrew/bin/bash prints the ladder_fallback line (depth=0 after=unexplained)
PASS: bash 3.2 arm ran on /bin/bash 3.2
PASS: early-return contract intact (no line when pick empty or pick==landed)
NOTE: /bin/bash is 3.x -- the declared-unassigned crash arm needs bash >= 4.4; mutation red proven on the other bash
PASS: (red) reverted guard crashes the live declared-unassigned state on /opt/homebrew/bin/bash -- suite red under this mutation
---
PASS=13 FAIL=0
```

The extraction is `sed -n '/^_route_arm_source_suffix()/,/^}/p'` on the REAL file, so a
mutation-control run of the real file flows straight into the probe.

## Negative controls — leadv2-mutation-control.sh on the REAL file (lead re-runnable)

Both run post-commit (HEAD `00fc0acd`), artifacts in
`docs/handoff/w1-arbiter-bypassed-on-dispatch/mutation-control/`:

**Control (a) — revert the guard to `declare -p attempted`** (mutation INSIDE
`_route_arm_source_suffix`'s body: both new guard lines restored to the pre-fix bytes):

```
suite=plugins/leadv2/scripts/tests/test-route-arm-source-suffix-unbound.sh
file=plugins/leadv2/scripts/leadv2-dispatch-code.sh
baseline_rc=0
mutated_rc=1
red_line=FAIL: (s2-declared-unassigned) /opt/homebrew/bin/bash died rc=1 under set -u -- telemetry line lost -- ...: attempted: unbound variable
diff_hash=fa95b43e35bdaeaab60cccbf94f94d6711f540e225f44c7ec40a7ca43bc32e84
lane_diff_hash=145098f5e8a0d5b0b0c80a00cb1cd30da4f1beaa15ed8a5c4dd3b22354fea70d
```

The reverted guard reproduces the exact live crash byte-for-byte (`attempted: unbound
variable`) — suite part-3 goes red.

**Control (b) — revert the arbiter input** (`query_kind = kind`, i.e. the seam again
answers raw `kind=plugin` — the pre-fix input):

```
suite=plugins/leadv2/scripts/tests/test-arbiter-seam-plugin-kind.sh
file=plugins/leadv2/scripts/leadv2-dispatch-code.sh
anchor=s|query_kind = kind if kind in known_kinds else 'code'|query_kind = kind|
baseline_rc=0
mutated_rc=1
diff_hash=1dac93b6b8e4ff7dcb10a079b98cab343a6a5825d656957e76b8f57724bf70ea
lane_diff_hash=145098f5e8a0d5b0b0c80a00cb1cd30da4f1beaa15ed8a5c4dd3b22354fea70d
```

`mutated_rc=1`: the suite goes red — the failing assertion is g2's seam-line detector
(`kind_mapped=plugin->code` gone). Honest note: guard 2 (empty→legacy fail-open)
rescues the OUTCOME level under this mutation (dispatch still resolves by=arbiter via
the fallback ladder), which is by design — two independent nets. The seam-line
assertion is what detects the broken input, and the control proves the suite reddens.

## Falsification set

- `bash -n` on `leadv2-dispatch-code.sh` → OK (both suites gate on it too).
- No Python files changed (the seam python is an inline heredoc; `py_compile` N/A —
  the heredoc runs under `python3 -` and was exercised by every suite run above).
- Both suites: green runs pasted in full above (14/14, 13/13).
- Mutation controls on the real file: `MUTATION-CONTROL ok` ×2, artifacts cited above.
- `tests/run-all.sh --scope changed`: see below.

### changed-scope runner

<!-- RUNNER-OUTPUT-PENDING -->

## Write set / off-limits compliance

Written: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
`plugins/leadv2/scripts/tests/test-arbiter-seam-plugin-kind.sh`,
`plugins/leadv2/scripts/tests/test-route-arm-source-suffix-unbound.sh`,
`docs/handoff/w1-arbiter-bypassed-on-dispatch/` (report + mutation-control artifacts).
Read but never written: `lib/leadv2-route-arbiter.sh`, `config/leadv2-routing.yaml`,
`lib/leadv2-launch-registry.py` (all off-limits per brief; the arbiter was only ever
INVOKED).
