# ARMS-ADMISSION-01 round 2 — call-site mutation proofs

Added `case5` to `plugins/leadv2/scripts/tests/test-arm-admission.sh`: a new
`resolve_arm_harness()` that sed-extracts `_select_base_arm()` **and**
`resolve_arm()` (the real call site, not `_select_base_arm` in isolation) from
the live production file, points `GLM_POLICY_RESOLVER` at a stub `python3`
script that records the argv it was invoked with, and asserts the resolver
actually received `--base-arm cheap-arm`. Only diff: `test-arm-admission.sh`
(+48 lines). No other lane file touched.

## 1. glm-flash fix — mutate `leadv2-dispatch-code.sh:1920`

Mutated the real call site:
```
- local -a _resolver_args=(--routing-yaml "${ROUTING_YAML}" --job build --base-arm "${_base_arm}" --signals "${signals_json}")
+ local -a _resolver_args=(--routing-yaml "${ROUTING_YAML}" --job build --base-arm glm --signals "${signals_json}")
```
RED (only case5 + its post-mutation GREEN re-proof fail; cases 1-4 stay green):
```
[TEST] FAIL: case5: expected '--base-arm cheap-arm' in resolve_arm's resolver argv, got '--routing-yaml ... --job build --base-arm glm --signals {...}'
[TEST] FAIL: post-mutation GREEN: case5 regressed
[SUMMARY] PASS=16 FAIL=2
exit_code=1
```
Reverted the line, re-ran:
```
[SUMMARY] PASS=18 FAIL=0
exit_code=0
```
`git diff --stat` on the production file after revert: empty (no changes).

## 2. Protected-path exclusion — mutate `leadv2-dispatch-code.sh:2087`

Mutated the real `_build_candidate_chain` branch back to the old blanket
exclusion:
```
- if [[ "${DC_SAFETY:-0}" == "1" || ( "${DC_PROTECTED:-0}" == "1" && "${_writes_prod}" == "1" ) ]]; then
+ if [[ "${DC_SAFETY:-0}" == "1" || "${DC_PROTECTED:-0}" == "1" ]]; then
```
RED (case2 — protected+review must admit free-arm — fails, nothing else does):
```
[TEST] FAIL: case2 (ladder): expected free-arm in chain, got 'trusted-arm'
[TEST] FAIL: post-mutation GREEN: case2 regressed
[SUMMARY] PASS=16 FAIL=2
exit_code=1
```
Reverted, re-ran: `[SUMMARY] PASS=18 FAIL=0`, exit 0. `git diff --stat` on the
production file after revert: empty.

## 3. Router/arbiter agreement on `light` — mutate fixture `when:` (one side only)

Mutated only the ladder side of the fixture routing data inside the test file
(`free-arm`'s `when:` in the `ROUTING` heredoc), leaving the arbiter's own
SIZE_MAP fixture untouched — reproducing a config drift between the two
interpreters of the same routing data:
```
- when: [light, standard, bulk]
+ when: [standard, bulk]
```
RED, and it names the disagreement directly:
```
[TEST] FAIL: case3: ladder/arbiter disagree at light — ladder_admits=0 ('trusted-arm cheap-arm') arbiter_admits=1 ('arm=cheap-arm ...')
[TEST] FAIL: case2 (ladder): expected free-arm in chain, got 'trusted-arm cheap-arm'
[TEST] FAIL: post-mutation GREEN: case2 regressed
[TEST] FAIL: post-mutation GREEN: case3 (ladder) regressed
[SUMMARY] PASS=14 FAIL=4
exit_code=1
```
(case2 also flips here because free-arm's fixture `when:` also gated its
standard-lane reachability in the ladder path — expected, since it's the same
fixture cell being restricted.)
Reverted, re-ran: `[SUMMARY] PASS=18 FAIL=0`, exit 0. Final `git diff --stat`:
only `test-arm-admission.sh` changed (+48 insertions), confirming clean revert
of both production files.

## Falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh && /bin/bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh && /bin/bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-arm-admission.sh && /bin/bash -n plugins/leadv2/scripts/tests/test-arm-admission.sh && echo OK
OK
$ python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py && echo PY_OK
PY_OK
$ bash plugins/leadv2/scripts/tests/test-arm-admission.sh
[SUMMARY] PASS=18 FAIL=0   (exit 0)
```

`tests/run-all.sh --scope changed` timed out waiting on
`/tmp/leadv2-core-offline.lock`, held by a concurrent lane (multiple other
`/leadv2` sessions are active right now per the session's own task-anchor
list, including another ARMS-ADMISSION-01 entry) — environmental lock
contention, not a result of this change. The target suite itself was run
directly (above) as the falsification evidence for this diff; `run-all.sh`'s
suite-map entries for `test-arm-admission.sh` (leadv2-dispatch-code.sh /
leadv2-route-arbiter.sh) are unchanged from round 1 and were not touched.

## Left alone
Mutation A/B/C (pre-existing scratch-copy mutations from round 1) were kept
as-is; they are additional regression coverage but were not relied on as the
call-site proof — the proofs above are all real edits to the live production
files, run through the unmodified suite entrypoint.

DELIVERABLE_COMPLETE
