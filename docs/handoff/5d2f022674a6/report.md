# ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01

## Outcome

The pinned lane contains the production fix inherited from `f6491694`: bash preconditions emit named `FATAL` diagnostics, and the Python half uses a strict stdlib YAML-subset loader when PyYAML is unavailable, refusing unsupported YAML loudly instead of routing on a guess. The only lane code change is a test-only arbiter path seam, committed as `0b4fb0f4`, so the required mutation control can target a scratch arbiter copy without changing production behavior.

## Clean suite

The current `test-route-arbiter-loud-refusal.sh` run passed in Debian bookworm with Python and PyYAML installed. Raw output, including the exit code and separate stream byte counts, is in [round1-green.txt](round1-green.txt).

## Linux without PyYAML

The bare Linux probe ran the real `route_arbiter` through `bash -c` with Python 3 but without PyYAML. It returned a route line rather than silent rc=2; stderr contained the named fallback note. Raw output:

```text
EXIT_CODE=0
STDOUT_BYTES=959
STDERR_BYTES=194
--- STDOUT ---
arm=glm kind=code model=glm-5.3 tier=standard effort=low reason=capability_fit chain=glm,codex,sonnet,glm-flash util_glm=10 util_codex=20 util_claude=20 util_freepool=100 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=5.00h_default_full_period reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=ok claude_probe_penalty=0 claude_priced_from=measured arm_excluded=codex:price_ratio,freepool:capped,glm-flash:price_ratio,sonnet:price_ratio arb_rev=80aab75042e6 matrix_rev=5ae0b114845b floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=90.0 reset_in=5.00h reset_basis=default_full_period failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=1 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,glm-flash:1 forecast_basis=journal_unavailable forecast_class=standard/unknown
--- STDERR ---
[route-arbiter] NOTE: PyYAML unavailable (ModuleNotFoundError: No module named 'yaml') -- strict stdlib YAML-subset loader active (parse-or-refuse). Install python3-yaml to restore full PyYAML.
```

## Negative control

The clean suite went red when the new bash diagnostic was silenced: exit 1, stdout 359 bytes, stderr 0, with the bash-half refusal assertion failing. The raw required paste is [round1-red.txt](round1-red.txt). The repository mutation-control artifact is [20260910T184949Z-1.txt](mutation-control/20260910T184949Z-1.txt); it records `baseline_rc=0`, `mutated_rc=1`, the exact mutation anchor, the red line, and the lane/mutation hashes.

## Verification

- `bash -n` passed for the changed shell suite.
- `git diff --check` passed before the lane commit.
- The changed-scope runner and final committed-lane status are recorded below after execution.

Raw final falsification output before the evidence commit:

```text
BASH_N_RC=0
PY_COMPILE=NO_CHANGED_PYTHON_FILES
DIFF_CHECK_RC=0
CACHED_DIFF_CHECK_RC=0
```

## Changed-scope runner

```text
EXIT_CODE=0
STDOUT_BYTES=5502
STDERR_BYTES=0
--- STDOUT ---
[RUN] /tmp/runner-repo.iQYTzG/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] scope=changed running 2 of 95 suites (base=main@a5e1c4c51f, 1 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=2 total=95 base=main@a5e1c4c51f changed=1 unmapped=0 verdict=selected reason=-
[CORE-OFFLINE] known-red skipped=0 (budget mode: still executed by --scope all / bare runs)
[CORE-OFFLINE] running 2 suites across 4 shards

[CORE-OFFLINE] all plugin shell syntax
[CORE-OFFLINE] SHARD_RESULT idx=0 pass=1 fail=0 missing=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-route-arbiter-loud-refusal.sh (scope-selected ad-hoc)
PASS: stdlib YAML-subset loader routes byte-identically to real PyYAML on the real configs
PASS: subset-unsupported yaml refuses loudly (rc=2, stderr names the line), never routes on a guess
PASS: invalid LEADV2_ROUTE_ARBITER_YAML_LOADER value is a named refusal (rc=2, stderr bytes > 0)
PASS: unreadable routing yaml: FATAL rc=65 on stderr, zero decision bytes on stdout
SUMMARY: pass=4 fail=0
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=1 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=2 pass=0 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=0 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=serial pass=0 fail=0 missing=0

[CORE-OFFLINE] suites passed=2 failed=0 missing=0 known_red_skipped=0 repo=/tmp/runner-repo.iQYTzG
[PASS] /tmp/runner-repo.iQYTzG/plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] /tmp/runner-repo.iQYTzG/tests/test-status-surface-bash32.sh
test-status-surface-bash32: SKIP — not Darwin, no /bin/bash 3.2 to test against
[PASS] /tmp/runner-repo.iQYTzG/tests/test-status-surface-bash32.sh
[RUN] /tmp/runner-repo.iQYTzG/tests/test-status-surface-single-lead.sh
== single-lead fixture titles ==
  ok   - status-render consumes snapshot single_lead section
  ok   - no-dispatch idle -> ⚪ idle
  ok   - active dispatch -> 🛠 abcdef12 codex 2m
  ok   - bogus state filtered -> 🛠 abcdef12 codex 2m
  ok   - pending question -> ❓1
  ok   - malformed ledger -> ⚠
  ok   - python3 unavailable -> ⚠ (no legacy fallthrough)

== process census (SWIFTBAR-ACTIVE-SOURCE-02) ==
  ok   - (a) live claude-subsession → active with sig8
  ok   - (a-registry) seeded registry label -> 🛠 FIXTURE-REGISTRY sonnet now
  ok   - (a2) human task_id from reservation preferred over sig8
  ok   - (b) worker gone + terminal → idle
  ok   - (c) exactly 3 entries (2 live + 1 reservation-only)
  ok   - (d) glm worker + terminal → idle (no terminal lanes in body)
  ok   - (e) empty everything → idle

== founder-named lanes (human task_id in run-id segment) ==
  ok   - (f) founder-named glm lane → ACTIVE once with human name
  ok   - (g) founder-named codex pid-file → ACTIVE once with human name

== T-term: fresh vs stale terminal rows (Rule R retention) ==
  ok   - (T-term-1) stale terminal (10m) drops the lane entirely
  ok   - (T-term-2) fresh terminal (60s) drops the lane entirely

== T-lead: the lead's own session is never a lane (C3) ==
  ok   - (T-lead-1) lead's own session excluded from lanes
  ok   - (T-lead-2) real codex session-runner still visible (exclusion is targeted)

== T-multi: aggregation across repos (repo label on foreign lanes) ==
  ok   - (T-multi) foreign-repo lane visible with its repo label

== T-unverifiable: repo lacking a terminal ledger contributes zero rows ==
  ok   - (T-unverifiable) repo with unreadable terminals contributes no rows

== T-name: lane_label fallback + architect phase (C4) ==
  ok   - (T-name-1) lane_label resolves the human name + legacy architect phase
  ok   - (T-name-2) no name fields at all -> sig8 fallback (legacy ~ phase)

test-status-surface-single-lead: 24 passed, 0 failed
[PASS] /tmp/runner-repo.iQYTzG/tests/test-status-surface-single-lead.sh
[RUN] /tmp/runner-repo.iQYTzG/tests/test-status-surface-fast-names.sh
== T1: resolve_lane_label fallback chain ==
  ok   - ledger lane_label hit
  ok   - active.yaml worktree fallback
  ok   - mission heading fallback (MISSION-HEADING-TASK — implementation )
  ok   - miss -> sig8 unchanged
  ok   - lane_label pipe stripped (got 'AB')
== T2: cold cache ==
  ok   - cold cache shows «нет кэша», no spinner
  ok   - cold render <1s (wall 0s)
  ok   - cold render kicked a refresh (lock held)
== T3: warm cache ==
  ok   - warm cache: label in title+row, no sig8 sub-row
  ok   - warm render <1s (wall 1s)
== T4: stale cache ==
  ok   - stale cache -> «⚠️ кэш устарел»
== T5: rename hygiene (SELF_PATH) ==
  ok   - copy-reply bash= path is the .5s.sh and exists (/tmp/runner-repo.iQYTzG/plugins/leadv2/scripts/leadv2-status-surface.5s.sh)

test-status-surface-fast-names: 12 passed, 0 failed
[PASS] /tmp/runner-repo.iQYTzG/tests/test-status-surface-fast-names.sh
[RUN] /tmp/runner-repo.iQYTzG/plugins/leadv2/scripts/tests/test-route-arbiter-loud-refusal.sh
PASS: stdlib YAML-subset loader routes byte-identically to real PyYAML on the real configs
PASS: subset-unsupported yaml refuses loudly (rc=2, stderr names the line), never routes on a guess
PASS: invalid LEADV2_ROUTE_ARBITER_YAML_LOADER value is a named refusal (rc=2, stderr bytes > 0)
PASS: unreadable routing yaml: FATAL rc=65 on stderr, zero decision bytes on stdout
SUMMARY: pass=4 fail=0
[PASS] /tmp/runner-repo.iQYTzG/plugins/leadv2/scripts/tests/test-route-arbiter-loud-refusal.sh
run-all: 5 passed, 0 failed, scope=changed
--- STDERR ---
```
