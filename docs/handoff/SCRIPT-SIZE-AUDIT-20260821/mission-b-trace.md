# Mission B — unified lane trace (the prerequisite for every perf claim)

Repo: ~/Projects/leadv2. Basis: docs/handoff/SCRIPT-SIZE-AUDIT-20260821/codex-findings.md
§Q1 + "Recommended order" item 2.

## Why
The audit proved parse cost is negligible (10-20 ms vs provider medians of 146-933 s),
but it could NOT attribute lane wall-clock because "the repository has no unified trace
joining lane start, all helpers, review, deploy, live verification, and close." Every
further refactor decision in that audit is gated on this data existing. Build the
instrument first; do not optimise anything in this mission.

## Do
Add an opt-in, default-OFF trace that emits one append-only NDJSON record per traced
span, keyed by a lane-scoped trace id.

1. Trace id: derive from the existing lane/task id (task-sig8 / dispatch-<8hex>) so a
   trace joins to an existing lane without a new registry. Propagate via an env var
   (e.g. LEADV2_TRACE_ID) so children inherit it across `bash`/`exec` boundaries.
2. Span record fields, one JSON object per line:
   trace_id, span (short stable name), script (basename), pid, ppid,
   t_start_ns / t_end_ns from a MONOTONIC clock (not `date`), duration_ms,
   exit_code, child_exec_count (best-effort counter, may be null).
   A wall-clock ISO stamp is fine as an extra field but must not be the timing source.
3. Sink: one file per trace under the existing state dir — resolve it via
   leadv2-state-path.sh, do NOT hardcode a path. Append-only, one writer per process,
   O_APPEND single-line writes so concurrent lanes cannot interleave a record.
4. Gate: OFF unless LEADV2_TRACE=1. When off, the added code must cost at most one env
   test per span — no subshell, no external command, no file open. Prove this: report
   `bash -n` plus a measured before/after of one dispatch `--help` path.
5. Instrument exactly these seams, no more, this round:
   leadv2-dispatch-code.sh (lane start/end), leadv2-router.sh, leadv2-review-run.sh,
   leadv2-status-collector.sh, leadv2-lanes-snapshot.sh, leadv2-backlog-pump.sh,
   and the provider launchers glm-coder.sh / kimi-coder.sh / codex-task.sh
   (span = the provider call itself).
6. Add a reader: a small script that takes a trace dir and prints p50/p95 duration per
   span name plus the per-lane total, so a week of data is readable without ad-hoc jq.
7. Tests: unit-test the record writer (schema + append-under-concurrency) and a test
   asserting that with LEADV2_TRACE unset, zero trace files are created on a dispatch
   resolve-only path (LEADV2_DISPATCH_SPAWN=0).

## Off-limits
- No refactor, no extraction, no Python rewrite of any existing block. Instrument only.
- Do not change any existing control flow, exit code, or output format.
- Do not turn the trace on by default. The founder flips it, not this mission.
- Do not create real copies of plugin files in project repos.

## Deliverable
docs/handoff/SCRIPT-SIZE-AUDIT-20260821/mission-b-report.md — the span-name list with
file:line of each instrumentation point, the record schema, the off-path cost
measurement, test output verbatim, git diff --stat, and the exact command the founder
runs to enable the trace and to read the p50/p95 rollup. End with DELIVERABLE_COMPLETE.
