# DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01 — report

## Change

The `EXTRA_SUITE_MAP` removal (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01) dropped 16
script→suite mappings. Each of the 12 suite files covering all 16 pairs now carries a
self-registration header, e.g.:

```
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-code.sh
```

Mapping table (committed in 44055d6b): same 16 pairs the mission listed. One deviation:
`leadv2-single-lead-beat.sh` (a hooks/ file, not scripts/) was named in the old map;
the header on `test-broad-status-relay-scope.sh` names `leadv2-single-lead-beat-loop.sh
leadv2-beat-owner.sh`, which are the scripts/ carriers that exist and are trigger-scanned.

## Dark-sweep (item 2)

Suites with NO `# run-all-triggers:` header across the suite directories — 267 total:

- `plugins/leadv2/scripts/tests/` — 235
- `plugins/leadv2/tests/` — 24
- `tests/` (repo root) — 8

Full list: `/tmp/dark-sweep-nohdr.txt`. Not fixed in this lane (sample-fix only, per
mission). The population finding: header-less selection is the same darkness one level
down.

## Nonexistent-suite mapping (item 3)

`test-lanes-snapshot.sh` DID NOT need creating — it exists (retargeted onto
`leadv2-lanes-snapshot.sh` by SUPERVISOR-DELETE-01, commit 3d6b1f31). Nothing was owed;
the mission's "does not exist" premise was stale. It has no header of its own (counted
in the 267).

## Negative control (acceptance 2)

Fresh reproduction this session (committed form in 18d53bb3/a2c22a73):

```
# header removed from test-lane-registry-self-deadlock.sh
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep -c test-lane-registry-self-deadlock
0
# header restored (git checkout)
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep -c test-lane-registry-self-deadlock
1
```

## Selection proof (acceptance 1)

E2E `--scope changed` run pending in this session; the trigger map at rest names all 12
suites under their production carriers:

```
leadv2-dispatch-code.sh:...test-dispatch-ledger-partial-close.sh
leadv2-dispatch-code.sh:...test-dispatch-ledger-task-id.sh
leadv2-dispatch-ledger.sh:...test-dispatch-ledger-task-id.sh
leadv2-dispatch-ledger.sh:...test-dispatch-terminal-deregisters-lane.sh
leadv2-lane-liveness.sh:...test-lane-liveness-authoritative.sh
leadv2-lanes-snapshot.sh:...test-lane-liveness-lies.sh
leadv2-active-registry.sh:...test-lane-liveness-lies.sh
leadv2-lane-liveness.sh:...test-lane-liveness-sentinel.sh
leadv2-dispatch-code.sh:...test-lane-registry-self-deadlock.sh
leadv2-status-surface.sh:...test-status-surface-close-phase.sh
leadv2-status-surface.sh + leadv2-state-path.sh:...test-status-surface-cwd.sh
leadv2-status-surface.sh:...test-status-surface-handle-identity.sh
leadv2-dispatch-ledger.sh:...test-t-core-dispatch-ledger.sh
leadv2-single-lead-beat-loop.sh + leadv2-beat-owner.sh:...test-broad-status-relay-scope.sh
```

## Suite results (acceptance 3) — PENDING

`test-broad-status-relay-scope.sh` RED: `7 passed, 18 failed` (first failure:
`FAIL: T1: owner did not get full relay:`). Pre-existing on base — the lane's only
change to that file is the comment header (git diff vs a3ac0067 shows exactly the one
added comment line). Reported as a finding; not fixed, not added to known-red lists.

Full 12-suite results: appended below when the foreground run completes.

## Falsification set

`bash -n` on all 12 changed suite files: PASS (no syntax errors). Python: none changed.
Changed-scope runner: in flight, results appended.
