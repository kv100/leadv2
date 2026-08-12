#!/usr/bin/env bash
# Fixture: stub architect arm for plan-run tests.
# Emits a valid PLAN_YAML fenced block with all required judgment fields.
# Used by test suites that need the engine to complete a full plan cycle.
cat <<'EOF'
PLAN_YAML:
```yaml
decisions:
  - Use leadv2-plan-run.sh as sole owner of Phase 2 Plan
off_limits:
  - leadv2-review-run.sh
  - leadv2-dispatch-code.sh
plan:
  steps:
    - Create the engine
    - Write tests
    - Validate
acceptance:
  surface: file_artifact
  observable: >
    A reader opening the plan-gate.md file sees mode, status, reason, arms,
    artifact and acceptance fields as key-value pairs.
risk: low
```
EOF
