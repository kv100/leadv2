# PLUGIN-PREPASS-TRUTH-BUNDLE-01

## Defect 1 — verified design artifact

`architect_prepass` now verifies the actual handoff candidate before admission:
it must be readable under the lane root (or materializable from `HEAD:path`),
and have at least eight non-blank lines. Eight is the minimum that admits the
compact scope/acceptance format while refusing an acknowledgement stub. Success
journals `design_artifact_verified`; missing and short artifacts journal the
distinct `design_artifact_missing` and `design_artifact_stub` causes.

Probe rc: `0`.

```text
[TEST] PASS: present non-trivial artifact is verified
[TEST] PASS: path in no ref is refused as design_artifact_missing
[TEST] PASS: empty/stub artifact is refused as design_artifact_stub
[prepass-verifies-the-design-artifact] PASS=4 FAIL=0
```

Negative control (RED, then restored green):

```text
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-prepass-verifies-the-design-artifact.sh file=plugins/leadv2/scripts/leadv2-dispatch-code.sh red_line=[TEST] FAIL: missing rc=0 out= reason=design_artifact_verified porcelain_clean=yes
```

Artifact: `mutation-control/20260915T130201Z-live-73844.txt`.

## Defect 2 — named prepass outcomes

The real outcome classifier maps prepass-owned `rc=124` to
`prepass_timeout` and journals `timeout_sec=<configured value>`; `rc=1` after
an explicit `status=allowed` is `prepass_failed_after_allowed`. `rate_limited`
is emitted only for the provider's explicit rate/quota class.

Probe rc: `0`.

```text
[TEST] PASS: rc=124 is named prepass_timeout
[TEST] PASS: rc=1 after allowed is named distinctly
[TEST] PASS: explicit provider quota refusal remains rate_limited
[prepass-outcome-is-named] PASS=4 FAIL=0
```

Negative control (RED, then restored green):

```text
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-prepass-outcome-is-named.sh file=plugins/leadv2/scripts/leadv2-dispatch-code.sh red_line=[TEST] FAIL: rc=124 was not prepass_timeout porcelain_clean=yes
```

Artifact: `mutation-control/20260915T130206Z-live-80766.txt`.

## Defect 3 — Claude failure leaves Codex eligible

The cited source-level premise was already correct in this checkout:
the Claude-model branch resolves to `anthropic`. I factored that identity into
the source function used by the fallback path and guarded it with the real
fallback loop. Therefore Codex (`openai`) remains eligible; only an identical
provider identity is excluded as `same_provider`.

Probe rc: `0`.

```text
[TEST] PASS: Claude failure admits Codex fallback candidate
[prepass-fallback-admits-codex] PASS=2 FAIL=0
```

Negative control (RED, then restored green):

```text
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-prepass-fallback-admits-codex.sh file=plugins/leadv2/scripts/leadv2-dispatch-code.sh red_line=[TEST] FAIL: fallback rc=1 out= porcelain_clean=yes
```

Artifact: `mutation-control/20260915T130213Z-live-73800.txt`.

## Falsification set

```text
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh
$ bash -n plugins/leadv2/scripts/tests/test-prepass-verifies-the-design-artifact.sh
$ bash -n plugins/leadv2/scripts/tests/test-prepass-outcome-is-named.sh
$ bash -n plugins/leadv2/scripts/tests/test-prepass-fallback-admits-codex.sh
$ grep -q design_artifact_verified plugins/leadv2/scripts/leadv2-dispatch-code.sh
$ grep -q prepass_timeout plugins/leadv2/scripts/leadv2-dispatch-code.sh
all rc=0
```

The direct provider-fallback regression suite passed. An unrelated legacy
`test-prepass-resume-invalidate.sh` remains red before prepass execution:
its fixture is refused at `writeset_persist_failed`. The required
`tests/run-all.sh --scope changed` selected the broad core runner; it hit its
own explicit 600s ceiling while waiting behind a concurrent core-offline lock,
reported `[SUITE-TIMEOUT]`, and continued. This is ambient runner contention,
not a green suite result.

DELIVERABLE_COMPLETE
