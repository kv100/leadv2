# Verify: _pc_reap_worker over-broad pgrep kill set

Finding [High/correctness]: `_pc_reap_worker` collects the same over-broad
`pgrep -f "${handle}"` match set and sends SIGTERM then SIGKILL to it.

VERIFY_VERDICT: upheld

## Evidence (docs/handoff/PR01-review/build.diff)

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, added block:

```
_pc_reap_worker() { # <handle> [meta_pid]
  ...
  done < <(pgrep -f "${handle}" 2>/dev/null || true)   # diff line 112
  ...
  for _pid in "${_pids[@]}"; do kill -TERM "${_pid}" ...; done   # diff line 115
  ...
  for _pid in "${_pids[@]}"; do kill -KILL "${_pid}" ...; done   # diff line 126
```

Confirmed mechanics:
- `pgrep -f` matches the *entire* command line as an ERE against every process
  owned by the user — there is no descendant/pgid scoping, no `-P`, no session
  filter, no ownership check beyond the default same-user rule.
- Any process whose argv merely *mentions* the handle string matches. Concrete
  cases: `tail -f <runs>/<handle>/journal.md`, `grep <handle> ...`, an editor
  with the run dir open, another dispatch/monitor script that carries the handle
  in argv, and the close gate process itself (HANDLE appears in its own argv).
- The match set is not filtered before killing; it is TERM'd, then KILL'd 5s
  later. Unlike `_pc_process_alive`, where a false positive only costs a longer
  poll, here a false positive is an unrecoverable SIGKILL of a third-party
  process.
- The handle is not a guaranteed-unique high-entropy token in a way that
  prevents substring matches; even a unique handle is *by construction* present
  in the paths that observability commands (`tail`, `grep`, `less`) operate on,
  which is exactly the co-occurrence that makes this fire in normal use.

No refutation available: nothing in the diff scopes the kill set (no `pgrep -g`,
no pgid capture at spawn, no `-P` parent filter, no self-PID exclusion).

Required fix: record the worker's process-group id at spawn into meta.yaml and
reap with `kill -TERM -<pgid>`; if pgrep must remain a fallback, anchor the
pattern to the spawn command form, exclude `$$`/`$PPID`, and skip PIDs whose
`/proc`-equivalent argv[0] is not the worker binary.

DELIVERABLE_COMPLETE
