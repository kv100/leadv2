Round-4 role selections: implement=anthropic/groq/openai/gpt-oss-120b (elapsed_s=1, probe_ms=355; artifact: `round3-selector/implement.log`); bulk=anthropic/groq/qwen/qwen3.8-27b (elapsed_s=5, probe_ms=3110; artifact: `round3-selector/bulk.log`); review=anthropic/groq/openai/gpt-oss-120b (elapsed_s=1, probe_ms=634; artifact: `round3-selector/review.log`); read=anthropic/groq/openai/gpt-oss-120b (elapsed_s=2, probe_ms=1800; artifact: `round3-selector/read.log`).

# FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 — round 4

## Gate closure

`leadv2-worker-output-gate.sh --from-git-diff HEAD` now fails closed when it
cannot resolve the committed range from `origin/main` to `HEAD`. It emits
`worker_output_gate_error reason=committed_range_unresolved` and returns 2;
the caller records the nonzero gate result as `parse_error`. This prevents a
clean working tree in a lane without `origin/main` from being accepted without
validating committed worker output.

Focused foreground control, Bash 3.2.57:

```text
PASS: committed range: clean tree still rejects broken origin/main...HEAD file
PASS: missing origin/main: committed broken shell fails closed with explicit range error
PASS: (red) MUTATION KILLED: production gate silently accepts no-origin committed broken shell
PASS: (green) restored production gate fails closed without origin/main
PASS: production call path: freepool-coder rejects committed bash-n failure as parse_error
PASS: MUTATION KILLED: production freepool-coder without gate call falsely accepts committed broken output
PASS: (green) restored production freepool-coder rejects committed bash-n failure
PASS=14 FAIL=0
```

The RED control mutates the missing-range guard inside the production gate,
observes the original silent `rc=0`, then restores the production bytes before
the GREEN assertion. The call-site control follows the same mutate/restore
shape for production `freepool-coder.sh`.

## Model selection provenance

The role ordering is honestly labelled as latency-only. The selector outputs
listed on the first line are the evidence; no discriminating round-3
bash-3.2 editing bakeoff was run or recorded, so this round makes no
correctness or quality-ranking claim for that ordering.

The selector liveness control also mutates production `_probe`, demonstrates
the blank-body false selection, restores it, and re-runs GREEN:

```text
[TEST] PASS: content probe: 200+blank primary rejected, secondary (real text) chosen
[TEST] PASS: mutation applied: production _probe reverted to status-code-only check
[TEST] PASS: MUTATION KILLED: status-only probe wrongly picks the blank-body route (reproduces the 2026-08-30 incident)
[TEST] PASS: (green) restored production selector rejects blank primary and chooses secondary
=== 7 passed, 0 failed ===
```

## Changed-scope selection

The yaml-only changed-scope run was attempted twice with a temporary Git index
containing exactly `plugins/leadv2/config/freepool-arm.yaml`. Both foreground
runs reached the canonical runner and stopped at its shared lock; no lock was
broken or bypassed:

```text
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline.lock (held by a concurrent run)
run-core-offline rc=124
```

The focused mapped suite was run directly and passed (`=== 7 passed, 0 failed ===`)
above. The changed-scope runner itself remains unverified until the concurrent
holder releases `/tmp/leadv2-core-offline.lock`.

## Additional foreground suite

```text
PASS: bash syntax: dispatch
PASS: (green) router still excludes freepool for a light task (when=standard,bulk)
PASS: (green) arbiter honours the router's exclusion -- freepool never arbiter_pick
PASS: (red) with allowed_arms wiring stripped, the exact live bug reproduces -- arbiter re-picks the router-excluded arm
PASS=4 FAIL=0
```
