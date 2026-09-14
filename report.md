# GLM review eligibility and 95 percent work ceiling

## Result

`router_v2.quota_ceilings.glm` is the live arbiter authority: `work_pct: 95`,
`review_pct: 98`.  The arbiter does not import the resolver `DEFAULT_*`
fallbacks; the focused suite proves that static relationship and runs the real
arbiter at 80, 94, and 95 percent.  The resolver defaults are retained only for
legacy non-arbiter calls and are aligned to 95/98, so they are not a competing
live arbiter source.

Ordinary `glm` is no longer statically excluded from review.  The existing
author-aware pool rule (`glm:author:`) refuses its own diff.  `glm-flash` and
`freepool` remain static exclusions, including if a tenant places either arm in
`review_arm_order`.

## Before (red state, raw extraction)

```text
RED_BEFORE_DEFAULT_REVIEW_EXCLUSIONS=['glm', 'glm-flash', 'freepool']
    glm:    { work_pct: 80, review_pct: 90 }
```

## Green focused falsification output

```text
[TEST] PASS: arbiter reads routing.yaml ceilings, not resolver DEFAULT_* fallbacks
[TEST] PASS: foreign author resolves glm; flash/freepool name their exclusions — reviewer=glm pool=glm:ok:85,glm-flash:excluded:review_arm_exclusion,freepool:excluded:review_arm_exclusion,codex:author: refusal=
[TEST] PASS: self-review refused by name (glm:author), codex selected — reviewer=codex pool=glm:author:,glm-flash:excluded:review_arm_exclusion,freepool:excluded:review_arm_exclusion,codex:ok:10 refusal=
[TEST] PASS: worker util=80 admits glm — arm=glm kind=code model=glm-5.3 tier=standard effort=low reason=explicit_requested_capable chain=glm util_glm=80
[TEST] PASS: worker util=94 admits glm — arm=glm kind=code model=glm-5.3 tier=standard effort=low reason=explicit_requested_capable chain=glm util_glm=94
[TEST] PASS: worker util=95 caps glm — arm=refuse model=none tier=none reason=requested_arm_capped kind=code requested_arm=glm chain= util_glm=95 ... arm_excluded=glm:capped
SUMMARY: pass=8 fail=0
```

The author-aware resolver output is the live selection surface.  The product
close wrapper converts the selected eligible arm into its journal form:

```text
route_resolved by=arbiter role=reviewer arm=glm task=<task> reason=<arbiter-reason>
```

No live Z.AI quota claim is made here: all quota values above are hermetic
fixture inputs, not a usage-page reading.

## Regression-guard census

Surface: `plugins/leadv2/scripts/tests/test-*` searched for explicit
`review_arm_exclusions: [glm]`, `DEFAULT_REVIEW_EXCLUSIONS`, and “never resolves
glm”.  There was **1 additional direct test guard** for the wrong global ban:
`test-glm-first-recovery.sh` case 6.  It now asserts that a base `glm` is not
globally excluded; ownership remains enforced by the author-aware pool.

Two further fixture-only occurrences (`test-reviewer-fable-preference.sh` and
`test-kimi-spill-resolve.py`) configure local legacy policies but do not assert
that the shipped default bans ordinary glm; they were not counted as guards.

`test-glm-flash-arm.sh` now requires exactly `{glm-flash, freepool}` and requires
ordinary glm to be absent from the static exclusions.

## Registration and verification

```text
leadv2-glm-policy-resolve.py:plugins/leadv2/scripts/tests/test-glm-review-and-ceiling-95.sh
leadv2-route-arbiter:plugins/leadv2/scripts/tests/test-glm-review-and-ceiling-95.sh
leadv2-routing.yaml:plugins/leadv2/scripts/tests/test-glm-review-and-ceiling-95.sh
```

`test-provider-quota-gate.sh`: `30 passed, 0 failed` (run with a foreground
mktemp shim because this sandbox’s default macOS temporary directory is not
writable).  The changed-scope runner was started in the foreground after the
new suite was staged; its core-offline delegation did not complete within the
300-second bound and was interrupted, so it is not claimed green.

Shell syntax passed for every changed shell file and `python3 -m py_compile`
passed for `leadv2-glm-policy-resolve.py`; `git diff --check` passed.
