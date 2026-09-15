# Dispatch refusals now name their actual cause

## D1 — supplied unknown kind

`cmd_resolve` now rejects a supplied kind unless it is `product` or appears in
`LEADV2_NON_PRODUCT_KINDS`; the error prints the supplied value and that shared
vocabulary. An absent kind remains `product\tconservative_default`.

Test: `plugins/leadv2/scripts/tests/test-dispatch-refusal-truth.sh` invokes the
real CLI for `--kind code`, then sources the production classifier for the
absent-kind policy control.

## D2 — mission exists but is untracked

The resume mission preflight now checks the lane filesystem after it proves the
path is absent from lane `HEAD`. A physical untracked file reports `untracked`
and the exact `git add && git commit` remedy; a file absent from disk retains
the existing absent-from-both refusal.

Test: the same suite creates a real Git main/lane fixture and exercises both
refusals through `_resume_mission_visibility_preflight`.

## D3 — external backlog identity

`row_matches` now resolves exact `id`, then `external_id`, then `node_id`,
before its existing exact `intent` heading compatibility match. A no-match
refusal now names the searched keys.

Test: the suite drives `_premise_probe_gate` against a real `docs/tasks.yaml`
row keyed by `external_id`, then a genuinely unknown id.

## Falsification and controls

All controls were run with the real `leadv2-mutation-control.sh` after commit
`14fa47bf`; each artifact records `baseline_rc=0` and `mutated_rc=1`.

| Defect | Mutation | Artifact | Raw RED line |
|---|---|---|---|
| D1 | parse guard `if [[ -n "${kind}" ]]` → `if false` | `mutation-control/20260915T083204Z-55711.txt` | `FAIL: D1 unknown kind refusal mismatch rc=8` |
| D2 | `present but untracked` → `present but invisible` | `mutation-control/20260915T083238Z-66193.txt` | `FAIL: D2 untracked refusal mismatch rc=5` |
| D3 | remove `external_id` from matcher keys | `mutation-control/20260915T083310Z-75918.txt` | `FAIL: D3 external_id resolution mismatch rc=8` |

The complete unedited red output, anchors, exit codes, and mutation hashes are
the three committed mutation-control artifacts named above.

### GREEN after restore

```text
PASS: D1 unknown kind is refused with supplied value and shared accepted set
PASS: D1 absent kind remains the conservative default
PASS: D2 untracked mission names the state and git remedy
PASS: D2 absent mission remains a distinct disk-absence refusal
PASS: D3 external_id resolves the real backlog row
PASS: D3 unknown id refuses and names searched keys
[DISPATCH-REFUSAL-TRUTH] pass=6 fail=0
```

## Self-check

```text
$ bash -n <every changed .sh>; python3 -m py_compile plugins/leadv2/scripts/leadv2_tasks_yaml_common.py
exit 0

$ bash plugins/leadv2/scripts/tests/test-dispatch-refusal-truth.sh
PASS: D1 unknown kind is refused with supplied value and shared accepted set
PASS: D1 absent kind remains the conservative default
PASS: D2 untracked mission names the state and git remedy
PASS: D2 absent mission remains a distinct disk-absence refusal
PASS: D3 external_id resolves the real backlog row
PASS: D3 unknown id refuses and names searched keys
[DISPATCH-REFUSAL-TRUTH] pass=6 fail=0
```

The required `tests/run-all.sh --scope changed` runner was run in the
foreground. It was RED for pre-existing/ambient reasons outside these three
seams: the core wrapper waited on an existing concurrent lock and hit its
bounded ceiling, then unrelated suites failed under the sandbox's denied
`mktemp` location. The raw terminal lines were:

```text
[CORE-OFFLINE] waiting for lock file=... held by a concurrent run
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 120s ceiling
[SUITE-TIMEOUT] tests/test-status-surface-bash32.sh exceeded 120s ceiling
mktemp: mkdtemp failed on .../T/tmp.*: Operation not permitted
```

After the first runner exposed legacy test callers using the now-invalid
`--kind code`/`--kind safety` spellings, those callers were migrated to the
accepted `--kind product` form (with `--safety` where applicable). The focused
six-case suite above is the green changed-seam proof; the aggregate runner has
not been represented as green.

DELIVERABLE_COMPLETE
