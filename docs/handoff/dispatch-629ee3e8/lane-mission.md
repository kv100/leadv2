# PLUGIN-RELIABILITY-02 test-gate round — ONE deliverable: the red/green proof test

Code fixes are DONE and committed (105e07f in worktree PLUGIN-RELIABILITY-02): run_dir
arg at product-close.sh reap call sites :1494/:1516, group-signalling for pgid entries,
grace-branch reorder, TASK in harness. Do NOT touch those.

Your ONLY job: one behavioral test (extend test-plugin-reliability-01.sh or a new file
wired into run-core-offline.sh) that:
1. Forks a real sleeper via setsid into a sandbox run dir, writes real `pgid` and
   `.lockref` files there (mirror how the spawn path creates them — read the code).
2. Drives the REAL timeout reap call-site path in leadv2-dispatch-product-close.sh (the
   code path through :1494/:1516 — source the script or invoke the close gate with a
   sandboxed env; NO reimplementation of the logic inside the test).
3. Asserts the setsid GROUP CHILD is dead afterwards.
4. GATE (hard, will be executed by the lead): the test must FAIL when
   leadv2-dispatch-product-close.sh is swapped for the c6c44b5 version (`git show
   c6c44b5:...` — broken reap) and PASS on current HEAD. Demonstrate both runs in the
   summary with rc lines. The previous three attempts all shipped tests that pass
   against the broken version — any such test is an automatic reject.

Deliverable: the test + docs/handoff/PLUGIN-RELIABILITY-02/summary.md with the red rc!=0
and green rc=0 lines, DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-629ee3e8" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.