# REGISTRY-SILENT-RC0-01 — closeout report

## Result

All six scoped silent-success sites now fail closed. The shared no-op code is
documented in `leadv2-active-registry.sh`: rc=4 means task not found or
`active.yaml` file-missing; rc=2 means the `set_worktree` target path is
absent. Every failure emits one line containing the task id and an explicit
`reason=` value (`not-found`, `file-missing`, or `path-absent`). Failed
unregister and missing-file paths do not rewrite or create state.

The production implementation is in
`plugins/leadv2/scripts/leadv2-active-registry.sh`. The required real-function
suite is
`plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh` and is
self-registered with `# run-all-triggers: leadv2-active-registry.sh`.

## Six-site mapping

| Site | Live behavior | Real suite case |
| --- | --- | --- |
| Python `unregister` no match | rc=4, `reason=not-found`, no rewrite | 1 |
| `leadv2_active_set_worktree` absent target | rc=2, `reason=path-absent`, no rewrite | 2 |
| `update_phase` missing file / unknown task | rc=4, `reason=file-missing` / `not-found` | 3 |
| `update_pulse` missing file / unknown task | rc=4, `reason=file-missing` / `not-found` | 4 |
| `set_worker_pid` unknown task | rc=4, `reason=not-found`, no row change | 5 |
| `leadv2_active_unregister` missing file | rc=4, `reason=file-missing`, no file created | 6 |

## Caller audit

I ran the requested repository-wide search:

    grep -rn leadv2_active_ plugins/leadv2

The relevant callers of the six changed operations were audited as follows.

| Caller | Sites | Disposition |
| --- | --- | --- |
| `scripts/leadv2-backlog-pump.sh` | unregister:670 | Explicit best-effort helper contract and `|| true`; reservation release is cleanup. |
| `scripts/leadv2-fanout.sh` | set_worktree:959,983,1074,1130,1144,1173,1261,1277; unregister:1488,1530,1731,1736,1747,1753 | Explicit launch/release cleanup tolerance; every call is guarded with `|| true`. |
| `scripts/leadv2-fanout-lane-launcher.sh` | unregister:151,193,279,296,304,316,324 | EXIT/death cleanup; every call is guarded with `|| true`. |
| `scripts/leadv2-phase8-close.sh` | unregister:748 | Explicit non-blocking log branch (`&& ... || log_info`). |
| `scripts/leadv2-stale-sweeper.sh` | unregister:313 | Fixed in this lane: concurrent disappearance is explicitly tolerated and logged. |
| `scripts/leadv2-dispatch-code.sh` | update_phase:728; set_worker_pid:6831,6961 | Phase mirroring and post-spawn pid stamping are explicitly best-effort; guarded with `|| true`. |
| `scripts/leadv2-dispatch-product-close.sh` | update_phase:493 | Explicit non-blocking phase mirror with `|| true`. |
| `scripts/leadv2-phase-record.sh` | update_phase:1028,1032 | Explicit `if ! ...; then` warning/phase-mirror-miss handling. |
| `scripts/leadv2-state-atomic-write.sh` | update_phase:258 | Runs in a subshell with an explicit outer non-fatal warning handler. |
| `scripts/lib/leadv2-lane-state.sh` | update_phase:408 | Deliberately propagates registry failure from the lane-transition API; this is the state-owner path, not a best-effort mirror. |
| `scripts/leadv2-gate1-prompt.sh`, `scripts/leadv2-fork-session.sh` | register | Admission/attach callers already use guarded `if`/`||` handling; unchanged by these no-op codes. |
| `scripts/leadv2-lane-heartbeat.sh` | heartbeat / terminal operations | Different registry operations; audited and unaffected. |
| provider/session runners | receipt operations | Different registry operations; all receipt writes are best-effort and unaffected. |

No production caller of `leadv2_active_update_pulse` was found; the new suite
is its direct caller coverage. Generated `.test-*` and `.dbg-*` function-copy
fixtures were included in the grep audit and retain the same explicit
best-effort guards as their source paths.

## Negative controls

Six live mutations were run with
`plugins/leadv2/scripts/leadv2-mutation-control.sh --live`. Each tool run
reported `MUTATION-CONTROL ok`, a red suite line, and
`porcelain_clean=yes`; the six newest files under `mutation-control/` are the
authoritative artifacts. Older artifacts from earlier committed intermediate
rounds are retained for traceability.

### round1-red.txt

The required raw six-red transcript is committed at
`docs/handoff/REGISTRY-SILENT-RC0-01/round1-red.txt` and is pasted here:

    M1 — python unregister no-match mutation
    MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh file=plugins/leadv2/scripts/leadv2-active-registry.sh red_line=[TEST] FAIL: case 1 rc=0 out=RC=0 diff_hash=510b2c4183e61823ee49d22d1fa0734f0d5ec078b7e87879254774eed29b045a lane_diff_hash=4f6a5e6b552697dc9cb678ddf7bb8183a7604d304c7123c4c655055d71a12def porcelain_clean=yes

    M2 — set_worktree path-absent mutation
    MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh file=plugins/leadv2/scripts/leadv2-active-registry.sh red_line=[TEST] FAIL: case 2 rc=0 out=UNKNOWN_RC=4 diff_hash=cb35a608eb23254649416a8354006ab803d8219a04a336a320b51c7ced1d419b lane_diff_hash=4f6a5e6b552697dc9cb678ddf7bb8183a7604d304c7123c4c655055d71a12def porcelain_clean=yes

    M3 — update_phase file-missing guard mutation
    MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh file=plugins/leadv2/scripts/leadv2-active-registry.sh red_line=[TEST] FAIL: case 3 rc=0 out=MISSING_RC=4 diff_hash=62070cce83b32da0a93b9beb80fa636d3131e091757489c7da1e6540f679d414 lane_diff_hash=4f6a5e6b552697dc9cb678ddf7bb8183a7604d304c7123c4c655055d71a12def porcelain_clean=yes

    M4 — python update_pulse no-match mutation
    MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh file=plugins/leadv2/scripts/leadv2-active-registry.sh red_line=[TEST] FAIL: case 4 rc=0 out=MISSING_RC=4 diff_hash=07e3edac0079e369ab8338e98865a2f46a7b47d656f79413a9dcdf2839cf95a5 lane_diff_hash=4f6a5e6b552697dc9cb678ddf7bb8183a7604d304c7123c4c655055d71a12def porcelain_clean=yes

    M5 — python set_worker_pid no-match mutation
    MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh file=plugins/leadv2/scripts/leadv2-active-registry.sh red_line=[TEST] FAIL: case 5 rc=0 out=RC=0 diff_hash=71102c90b727d69f10fc640bb6f858feeba0d79b2103d6986eac050135b5120d lane_diff_hash=4f6a5e6b552697dc9cb678ddf7bb8183a7604d304c7123c4c655055d71a12def porcelain_clean=yes

    M6 — unregister file-missing guard mutation
    MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh file=plugins/leadv2/scripts/leadv2-active-registry.sh red_line=[TEST] FAIL: case 6 rc=0 out=RC=4 diff_hash=87b3789a46f5f35099fa0b5bbc230098f5cd594ddd7381d9a756ccde67c7fdc6 lane_diff_hash=4f6a5e6b552697dc9cb678ddf7bb8183a7604d304c7123c4c655055d71a12def porcelain_clean=yes

## Verification

    bash -n plugins/leadv2/scripts/leadv2-active-registry.sh
    bash -n plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh
    bash -n plugins/leadv2/scripts/leadv2-stale-sweeper.sh
    python3 -m py_compile (no standalone Python files changed)
    bash plugins/leadv2/scripts/tests/test-active-registry-noop-is-nonzero.sh
    bash tests/run-all.sh --scope changed

Observed outputs:

    bash -n: PASS for active-registry.sh, test-active-registry-noop-is-nonzero.sh, and stale-sweeper.sh
    python3 -m py_compile: no changed Python files
    test-registry-fails-closed.sh: PASS=6 FAIL=0
    test-active-registry-noop-is-nonzero.sh: PASS=6 FAIL=0

The changed-scope runner was executed in the foreground with a 600-second
timeout. It returned non-zero: the run selected 25 of 95 suites, reported
10 passed and 13 failed (2 known-red skipped), and the transcript included
ambient sandbox failures such as `/bin/ps: Operation not permitted`, temp
directory creation denied, and unrelated writeset/liveness/worktree suites.
The focused registry suites above remained green after the suite portability
fix; this broad gate is recorded as red rather than upgraded to green.
