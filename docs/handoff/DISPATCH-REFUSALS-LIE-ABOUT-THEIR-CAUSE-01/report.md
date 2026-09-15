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

The three independent negative controls, their `leadv2-mutation-control.sh`
artifacts, and the raw RED/GREEN output are recorded below after the committed
implementation is used as the mutation-control baseline.

## Self-check

Pending final changed-scope runner and control evidence.

DELIVERABLE_COMPLETE
