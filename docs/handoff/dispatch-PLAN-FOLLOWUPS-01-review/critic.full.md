# Verify: leadv2-plan-run.sh:371 — extract_plan_yaml order-A disabled by any preceding fence

**Verdict: upheld (High / correctness).** Refutation attempted and failed; reproduced empirically.

## Claim under test
`extract_plan_yaml`'s order-A pass is disabled by ANY ``` fence appearing before
`PLAN_YAML:`, so a marker→fence output that also contains a prose code block falls
through to `cat <whole file>`. HEAD handled this correctly.

## Evidence (docs/handoff/PLAN-FOLLOWUPS-01/build-attempt-3.diff, extract_plan_yaml hunk)

New order-A awk:

    !found && /^```/ { fence_before_marker=1 }
    /^PLAN_YAML:/ && !fence_before_marker { found=1; next }
    found && !in_fence && /^```/ { in_fence=1; next }
    in_fence && /^```/ { exit }
    in_fence { print }

`fence_before_marker` is latched by the FIRST fence line anywhere ahead of the marker —
including both the opening and closing fence of an unrelated prose code block — and is
never cleared. So `found` can never be set and pass A yields empty.

Order-B awk enters the prose block (`!in_fence && /^```/ { in_fence=1 }`) and `exit`s at
that block's closing fence, before ever reaching `PLAN_YAML:` → empty.

The legacy marker-only pass is explicitly gated on "no fence at all in the file"
(`! awk '/^```/ { found=1 } END { exit !found }'`), which is false here → skipped.

Control therefore reaches `cat "$f"` and the entire file (prose + fences + marker) is fed
downstream as the plan YAML document.

## Reproduction (executed; both functions lifted verbatim from the diff's + and - sides)

Input file — prose code block, then marker, then the YAML fence:

    Here is an example command:
    ```bash
    echo hi
    ```
    PLAN_YAML:
    ```yaml
    decisions:
      - Decision A
    plan:
      steps:
        - Step A
    ```

NEW (post-diff) output — the whole file, verbatim, fences and all:

    Here is an example command:
    ```bash
    echo hi
    ```
    PLAN_YAML:
    ```yaml
    decisions:
      - Decision A
    plan:
      steps:
        - Step A
    ```

OLD (HEAD) output — correct extraction:

    decisions:
      - Decision A
    plan:
      steps:
        - Step A

HEAD's awk only begins fence-counting after the marker (`found && /^```/`), so pre-marker
prose fences are inert. The rewrite converts a correct extraction into a raw-file dump that
no YAML parser downstream will accept.

## Why the new tests do not catch it
Fixtures 2a–2d each contain at most one fenced block and never a fence ahead of the marker,
so the `fence_before_marker` latch is never exercised against a preceding prose block. This
is an uncovered logic branch introduced by the diff — per the test-coverage bar, a fixture
is required alongside the fix.

## Required fix
Either latch order-A's guard only for an *unclosed* fence ahead of the marker, or drop the
guard entirely and restore HEAD's post-marker-only fence counting for pass A (pass B already
covers the fence→marker ordering, and pass A returning empty on that input still falls
through to B). Add fixture 2e: prose code block, then `PLAN_YAML:`, then the YAML fence;
assert output contains `Decision A` and contains neither `echo hi` nor `PLAN_YAML`.

VERIFY_VERDICT: upheld

DELIVERABLE_COMPLETE
