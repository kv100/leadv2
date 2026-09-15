# REVIEW-BODY-LOST-FIRES-ON-A-SHORT-CLEAN-PASS-01

The authoritative completion marker is the existing parser-owned
`REVIEW_VERDICT: <FAIL|PASS_WITH_NITS|PASS>` marker, with its existing
`Verdict:` compatibility surface centralized in the same helper so the
persistence guard cannot drift from final verdict parsing; the captured legacy
`Verdict: approve` clean-pass spelling normalizes to `PASS` only when its
explicit `No material findings.` conclusion is present.

## Acceptance cases

The focused live-engine suite was run in the foreground:

```text
$ timeout 120 bash plugins/leadv2/scripts/tests/test-review-body-short-clean-pass.sh
PASS: GREEN short 254-byte legacy clean PASS yields status: pass
--- short-clean gate ---
arms: sonnet
fanout: 1/1 degraded=false launched=1 pool_ok=1 source=pool reason=none excluded=-
unreadable: none
verified: 0/0
mission_source: unavailable
mission_snapshot: /private/tmp/review-body-short-clean-pass.Pw8EVn/repo/docs/handoff/short-clean/review-mission-source.md
mission_sha256: unavailable
mission_bytes: 0
diff_bytes: 22
review_input_bytes: 22
correctness_verdict: PASS
mission_verdict: UNAVAILABLE
status: pass
reviewer: sonnet
diff: 3983adc4
findings_source: markdown_sections
findings: none
report: docs/handoff/dispatch-short-clean/review-sonnet.md
PASS: GREEN truncated no-marker body yields review_body_lost
--- truncated gate ---
status: blocked
reason: review_body_lost
arm: sonnet
body: docs/handoff/truncated/review-sonnet.md
bytes: 62
retrieval_attempts: body
PASS: GREEN empty body yields review_body_lost
--- empty gate ---
status: blocked
reason: review_body_lost
arm: sonnet
body: docs/handoff/empty/review-sonnet.md
bytes: 0
retrieval_attempts: body
PASS: GREEN verdict-marker-only body is complete but not a usable review
--- marker-only gate ---
status: blocked
reason: empty_response
arm_rc: sonnet=0
unreadable: sonnet=below_floor
```

The marker-only body is not `review_body_lost`, because it has a parseable
completion marker. It still blocks as `empty_response`, because a verdict alone
does not satisfy the independent review-floor/findings contract. This keeps the
loss detector structural without turning an incomplete semantic review into a
pass.

## Negative controls

Both controls mutate the same exact guard anchor; each mutation has a distinct
expected red outcome. The tool-backed artifacts are committed under
`mutation-control/` in this deliverable directory.

```text
PASS: RED control: restoring byte threshold blocks the short clean PASS
--- threshold-mutant gate ---
status: blocked
reason: review_body_lost
arm: sonnet
body: docs/handoff/threshold-mutant/review-sonnet.md
bytes: 254
retrieval_attempts: body
PASS: RED control: removing missing-marker check wrongly admits truncated body
--- missing-marker-mutant gate ---
status: blocked
reason: empty_response
arm_rc: sonnet=0
unreadable: sonnet=below_floor
review-body-short-clean-pass: PASS=6 FAIL=0
```

Control 1 restores the byte threshold, so the 254-byte valid body regresses to
`review_body_lost`. Control 2 removes the missing-marker check, so the
truncated body is no longer classified as lost and incorrectly reaches the
later `empty_response` path. The exact anchors are checked once by the suite
and again by `leadv2-mutation-control.sh`; a zero-match/no-op mutation fails.

## Self-check

```text
bash -n plugins/leadv2/scripts/leadv2-review-run.sh
bash -n plugins/leadv2/scripts/tests/test-review-body-short-clean-pass.sh
timeout 120 bash plugins/leadv2/scripts/tests/test-review-body-short-clean-pass.sh
PASS=6 FAIL=0
```

Changed-scope runner raw terminal summary (foreground, `timeout 600`):

```text
$ timeout 600 bash tests/run-all.sh --scope changed
suite-discovery: [UNTRACKED-SKIP] 1 suite file(s) refused: not tracked by git
[CORE-OFFLINE] scope=changed running 38 of 93 suites (base=main@5da9324f27, 2 changed files, 0 unmapped)
[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-review-body-short-clean-pass.sh
review-body-short-clean-pass: PASS=6 FAIL=0
run-all: 13 passed, 27 failed, 0 known-red (allow-listed, non-blocking), 3 known-red-skipped (budget mode, still run by --scope all), 0 gone-green (remove from allow-list), scope=changed
```

The changed-scope aggregate is red independently of this change: its failing
review-engine fixtures consistently start with `mktemp: mkdtemp failed on
/var/folders/.../tmp.*: Operation not permitted`, then attempt to write under
`/repo` or `/resolver.py`. The focused new suite uses `/private/tmp` and passes
in the same run. No aggregate failure was attributed to this diff.

DELIVERABLE_COMPLETE
