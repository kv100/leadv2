# builder selfcheck — dispatch-8ac1fe57
generated_at: 2026-09-03T23:50:31Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01
diff_hash: 732756f3cfaed385c7f75b7d954e5501dfaa96a202bef1e20b0dec7b100113f0
checks: 2   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh (falsification proof) (rc=1)
  "backend": "terminal",
  "pid": 68574
}) rc_dead=0 ({
  "task_id": "DEAD",
  "status": "dead",
  "reason": "heartbeat age 60.0m > 25m AND pid=999999 confirmed gone (kill -0 failed)",
  "backend": "terminal",
  "pid": 999999
}) rc_unknown=4 ({"error": "not_found", "message": "task_id NEVER-REGISTERED not in active.yaml"})
[TEST] PASS: T2: absent-record rc=4 differs from both alive(rc=0) and dead(rc=0) in the RETURN VALUE, not only in text
[TEST] T2-NC: mutating the not_found exit code must collapse it onto rc=0
[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid=68574
[TEST] T2-NC: baseline_rc=4 (from T2, unmutated) mutated_rc=0
[TEST] PASS: T2-NC: mutated not_found path now (wrongly) returns rc=0, indistinguishable from a real verdict -- the negative control is red as required
[TEST] T3: static scan -- no pgrep -f / ps|grep in the two canonical liveness libs
[TEST] PASS: T3: no process-name-pattern liveness check found in scan scope
[TEST] T3-NC: inserting a pgrep -f line inside a real function body must be caught
[TEST] T3-NC: baseline_rc=0 (from T3, unmutated) mutated_rc=1
[TEST] PASS: T3-NC: scanner caught the injected pgrep -f and named file:line -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01/plugins/leadv2/scripts/lib/.nc-pattern-leadv2-lane-state.sh:36: process-name-pattern liveness check: pgrep -f "$1" >/dev/null 2>&1 && return 0  # NC-MUTATION
[TEST] T4: static scan -- no $? captured after head/tail/wc/sort/uniq in the two canonical liveness libs
[TEST] PASS: T4: no post-filter-pipe $? capture found in scan scope
[TEST] T4-NC: inserting a piped-through-head command + trailing $? read must be caught
[TEST] T4-NC: baseline_rc=0 (from T4, unmutated) mutated_rc=1
[TEST] PASS: T4-NC: scanner caught the post-filter-pipe $? read and named file:line -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01/plugins/leadv2/scripts/lib/.nc-pipe-leadv2-lane-state.sh:36: $? read after a value-losing pipe stage instead of from the command itself: ps -eo pid,comm | head -3  # NC-MUTATION
[TEST] T5: static scan -- no ps/pgrep//proc enumeration + text row-select in the two canonical liveness libs
[TEST] FAIL: T5: text-matched process-table liveness decision(s) found (expected: the known lane-state.sh reconcile violator; any OTHER line is a new finding for the report):\n/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01/plugins/leadv2/scripts/lib/leadv2-lane-state.sh:133: liveness by process-table enumeration + TEXT row-select (ps table-wide enumeration; text select: if worktree not in line: continue)
[TEST] T5-NC: inserting ps -axo + 'not in' row-select inside a real function body must be caught
[TEST] T5-NC: baseline_rc=0 (watch-lifecycle.sh unmutated) mutated_rc=1
[TEST] PASS: T5-NC: scanner caught the injected ps -axo + not-in row-select and named file:line -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01/plugins/leadv2/scripts/lib/.nc-substr-leadv2-watch-lifecycle.sh:71: liveness by process-table enumeration + TEXT row-select (ps table-wide enumeration; text select: [[ "$1" =~ ^[0-9]+$ ]] || return 1)
[TEST] T5-NCb: injected pgrep -f must still be caught by the class scanner
[TEST] T5-NCb: baseline_rc=0 mutated_rc=1
[TEST] PASS: T5-NCb: class scanner still catches pgrep -f -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01/plugins/leadv2/scripts/lib/.nc-pgrepf-leadv2-watch-lifecycle.sh:71: liveness by process-table enumeration + TEXT row-select (named idiom (pgrep -f / ps|grep); text select: [[ "$1" =~ ^[0-9]+$ ]] || return 1)
[TEST] T5-NCc: injected ps | grep must still be caught by the class scanner
[TEST] T5-NCc: baseline_rc=0 mutated_rc=1
[TEST] PASS: T5-NCc: class scanner still catches ps | grep -- /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01/plugins/leadv2/scripts/lib/.nc-pipegrep-leadv2-watch-lifecycle.sh:71: liveness by process-table enumeration + TEXT row-select (named idiom (pgrep -f / ps|grep); text select: ps -Ao command= | grep -q "$2"  # NC-MUTATION)
[TEST] T5-FP: per-pid ps -p/-o lookups in watch-lifecycle.sh must stay green
[TEST] PASS: T5-FP: no false positive on wl_cmdline_match / wl_pidfile_live (per-pid ps -p ... -o command= + == *needle*)

=== test-liveness-tristate-01.sh: 13 passed, 1 failed ===
FAIL: T5: text-matched process-table liveness decision(s) found (expected: the known lane-state.sh reconcile violator; any OTHER line is a new finding for the report):\n/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SCANNER-MISSES-PS-SUBSTRING-01/plugins/leadv2/scripts/lib/leadv2-lane-state.sh:133: liveness by process-table enumeration + TEXT row-select (ps table-wide enumeration; text select: if worktree not in line: continue)

verdict: RED
