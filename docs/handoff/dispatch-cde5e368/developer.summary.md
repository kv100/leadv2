verdict: APPROVE
next_action: deploy

Fixed both halves of LANE-LIVENESS-ARTIFACTS-FORCE-A-95-SUITE-RUN-01: hardened `leadv2-lane-liveness.sh`'s PROJECT_ROOT fallback to self-heal via `git rev-parse --show-toplevel` (mirrors state-path.sh), and widened `run-core-offline.sh`'s scope-exclusion case to match `docs/` at any depth plus `.lane-liveness-share/` by name. New suite `test-scope-excludes-nested-housekeeping.sh` (10/10 pass); both mutation controls proved red. See developer.full.md.
