verdict: APPROVE
next_action: review_round_4

# HOOK-OUTPUT-CAP-PLUGIN-01 — developer deliverable, round 4

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOK-OUTPUT-CAP-PLUGIN-01`
Branch: `worktree-HOOK-OUTPUT-CAP-PLUGIN-01`, committed at `0f95c19`; prior HEAD `bd63187`.

## [High] the merge-base range re-selected settled suites forever — fixed

Round 3's `<merge-base>..HEAD` union is unbounded: every invocation re-diffs the whole
lane range against `main`, so every already-committed, already-tested commit on the
lane re-selects its suite on every future unrelated commit, growing monotonically with
lane length.

### Fix — persist the last-checked SHA per git-dir

`tests/run-all.sh`, `--scope changed` branch: after computing `_merge_base` as before,
resolve `git rev-parse --git-dir` (worktree-scoped, so concurrent lanes sharing this
machine never collide on the same file) and read `<git-dir>/leadv2-run-all-last-checked-sha`.
If present and still a valid commit, diff `<that sha>..HEAD` instead of
`<merge-base>..HEAD`. If absent (first run on this lane/worktree), fall back to the
merge-base exactly as round 3 did — the docs-only-HEAD property is preserved. At the
end of the branch, write current HEAD to the state file (tmp+`mv -f`, best-effort,
never fails the run).

```diff
+  _git_dir="$(git -C "${ROOT}" rev-parse --git-dir 2>/dev/null || true)"
+  _state_file=""
+  if [[ -n "${_git_dir}" ]]; then
+    case "${_git_dir}" in
+      /*) : ;;
+      *) _git_dir="${ROOT}/${_git_dir}" ;;
+    esac
+    _state_file="${_git_dir}/leadv2-run-all-last-checked-sha"
+  fi
+  _range_start=""
+  if [[ -n "${_state_file}" && -f "${_state_file}" ]]; then
+    _range_start="$(cat "${_state_file}" 2>/dev/null || true)"
+    if [[ -n "${_range_start}" ]] && ! git -C "${ROOT}" rev-parse --verify "${_range_start}^{commit}" >/dev/null 2>&1; then
+      _range_start=""
+    fi
+  fi
+  if [[ -z "${_range_start}" ]]; then
+    _range_start="${_merge_base}"
+  fi
-  if [[ -n "${_merge_base}" ]]; then
+  if [[ -n "${_range_start}" ]]; then
     changed="${changed}
-$(git -C "${ROOT}" diff --name-only "${_merge_base}..HEAD" 2>/dev/null)"
+$(git -C "${ROOT}" diff --name-only "${_range_start}..HEAD" 2>/dev/null)"
   elif git -C "${ROOT}" rev-parse HEAD~1 >/dev/null 2>&1; then
     changed="${changed}
 $(git -C "${ROOT}" diff --name-only HEAD~1..HEAD 2>/dev/null)"
   fi
+  if [[ -n "${_state_file}" ]]; then
+    _head_sha="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
+    if [[ -n "${_head_sha}" ]]; then
+      printf '%s\n' "${_head_sha}" > "${_state_file}.tmp.$$" 2>/dev/null \
+        && mv -f "${_state_file}.tmp.$$" "${_state_file}" 2>/dev/null
+    fi
+  fi
```

## Proof — both properties + control, one sequence, scratch clone

Scratch clone at `/private/tmp/hookcap-r4-scratch` (`/tmp` is a symlink to `/private/tmp`
on this macOS box — cloning under `/tmp` trips the repo's own root-escape guard, so the
clone lives under the resolved path directly), cloned from
`/Users/kostiantyn.vlasenko/Projects/leadv2`, checked out to
`worktree-HOOK-OUTPUT-CAP-PLUGIN-01`, with this round's `tests/run-all.sh` copied in
(uncommitted at clone time — verified with `bash -n` before every run).

### Property 1 — docs-only HEAD + unrelated dirt, no prior state (round 3's case)

```
$ git log --oneline -1
b885e0d docs: record round-2 findings in HOOK-OUTPUT-CAP-PLUGIN-01 report.md
$ git status --short
 M docs/LEAD_V2_STATE.md
 M tests/run-all.sh
$ rm -f "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"   # ensure no prior state
$ LEADV2_SUITE_LOCK_WAIT_S=5 timeout 300 bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline.lock (held by a concurrent run)
[CORE-OFFLINE] FATAL lock_timeout file=/tmp/leadv2-core-offline.lock wait_s=5
[FAIL] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] .../tests/test-status-surface-bash32.sh
  FAIL - _t6c: urgent divergence (min=-1 full=46) — file as follow-up
test-status-surface-bash32: 14 passed, 1 failed, 0 skipped
[FAIL] .../tests/test-status-surface-bash32.sh
[RUN] .../tests/test-status-surface-single-lead.sh
test-status-surface-single-lead: 23 passed, 0 failed
[PASS] .../tests/test-status-surface-single-lead.sh
[RUN] .../tests/test-status-surface-fast-names.sh
test-status-surface-fast-names: 12 passed, 0 failed
[PASS] .../tests/test-status-surface-fast-names.sh
[RUN] .../plugins/leadv2/scripts/tests/test-hook-output-cap.sh
7 passed, 0 failed
[PASS] .../plugins/leadv2/scripts/tests/test-hook-output-cap.sh
run-all: 3 passed, 2 failed, scope=changed
$ cat "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"
b885e0df563f41d62a31dc009dfa3f9038d237bd
```

`test-hook-output-cap.sh` selected and passes 7/7. The two failures
(`run-core-offline.sh` blocked on a real concurrent lane holding the machine-global
`/tmp/leadv2-core-offline.lock`; `_t6c` a pre-existing baseline red per the
`run-all-changed-preexisting-reds` memory) are both unrelated to this fix — neither
touches `leadv2-one-copy-drift.sh`/`leadv2-truth-card-inject.sh`/`test-hook-output-cap.sh`.

### Property 2 — same HEAD, state now persisted, exactly ONE new unrelated dirty file

```
$ git checkout -- docs/LEAD_V2_STATE.md
$ echo "unrelated single-file edit" >> plugins/leadv2/scripts/leadv2-lane-shape.sh
$ git status --short
 M plugins/leadv2/scripts/leadv2-lane-shape.sh
$ cat "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"
b885e0df563f41d62a31dc009dfa3f9038d237bd     # == current HEAD — already "checked"
$ LEADV2_SUITE_LOCK_WAIT_S=5 timeout 300 bash tests/run-all.sh --scope changed
[RUN] .../run-core-offline.sh                         [FAIL]  # same lock contention
[RUN] .../tests/test-status-surface-bash32.sh          [FAIL]  # same pre-existing red
[RUN] .../tests/test-status-surface-single-lead.sh     [PASS]  # always-on, not scope-governed
[RUN] .../tests/test-status-surface-fast-names.sh      [PASS]  # always-on, not scope-governed
[RUN] .../plugins/leadv2/scripts/tests/test-leadv2-lane-shape.sh
[PASS] .../plugins/leadv2/scripts/tests/test-leadv2-lane-shape.sh
run-all: 3 passed, 2 failed, scope=changed
```

`test-hook-output-cap.sh` is **not** re-selected — only `leadv2-lane-shape.sh`'s own
suite runs, plus the 4 always-on suites (`run-core-offline.sh` + 3 status-surface
suites, added unconditionally before the scope branch — see `tests/run-all.sh`'s
"Always-on" block — not governed by `--scope changed` selection at all, so their
presence in every log here is expected and not part of what this property tests).

### Control — mutate the bounding logic out, prove property 2 breaks

Mutation inside the function body of the production file (`tests/run-all.sh`), no
scratch-copy trick, no source grep:

```diff
-  if [[ -z "${_range_start}" ]]; then
+  if true; then
     _range_start="${_merge_base}"
   fi
```

Re-ran the exact property-2 scenario above (same dirty file, same state file) with no
other change:

```
$ LEADV2_SUITE_LOCK_WAIT_S=5 timeout 300 bash tests/run-all.sh --scope changed
...
[RUN] .../plugins/leadv2/scripts/tests/test-leadv2-lane-shape.sh   [PASS]
[RUN] .../plugins/leadv2/scripts/tests/test-hook-output-cap.sh     [PASS]   # RED
run-all: 4 passed, 2 failed, scope=changed
```

RED: `test-hook-output-cap.sh` reappears despite being already-tested and unrelated to
the one dirty file — property 2 breaks under the mutation, confirming the bounding
logic (not some other code path) is what makes property 2 hold.

Reverted the mutation, re-ran property 2 again: back to GREEN
(`run-all: 3 passed, 2 failed` — `test-hook-output-cap.sh` absent, matching the
property-2 log above exactly).

## Real run in this lane's own worktree

First run in this worktree (no prior state file there — equivalent starting condition
to property 1):

```
$ cd /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOK-OUTPUT-CAP-PLUGIN-01
$ LEADV2_SUITE_LOCK_WAIT_S=60 timeout 300 bash tests/run-all.sh --scope changed
...
[RUN] .../plugins/leadv2/scripts/tests/test-hook-output-cap.sh
7 passed, 0 failed
[PASS] .../plugins/leadv2/scripts/tests/test-hook-output-cap.sh
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: 4 passed, 1 failed, scope=changed
```

The one failure is `run-core-offline.sh` blocked on `[CORE-OFFLINE] waiting for lock
... held by a concurrent run]` → `FATAL lock_timeout ... wait_s=60` — a real concurrent
lane elsewhere on this machine holding `/tmp/leadv2-core-offline.lock` (machine-global
path, shared across all worktrees/clones). Outside `LANE_WRITES`.

## [Low] does `/tmp/leadv2-core-offline.lock` self-expire?

`plugins/leadv2/scripts/tests/run-core-offline.sh:61-62`:
```
exec 9>"$LEADV2_SUITE_LOCK_FILE"
if ! flock -n 9; then
```
This is a kernel `flock` held on an open file descriptor, not a stale-PID-file scheme —
the OS releases it automatically the instant the holding process's fd closes (clean
exit or crash), so it cannot be permanently orphaned by a dead holder.

It is **not**, however, self-expiring on any timer: `run-core-offline.sh:52-56`
documents the default wait as unbounded —
```
# Default wait is unbounded (matches "the lane should finish, not race") — set
# LEADV2_SUITE_LOCK_WAIT_S for a bounded wait
```
`LEADV2_SUITE_LOCK_WAIT_S` unset → `flock 9` with no `-w`, blocks indefinitely while a
concurrent run genuinely holds it. The multi-minute hangs observed live in this session
(both the scratch-clone runs and the in-worktree run above hit
`[CORE-OFFLINE] waiting for lock ... held by a concurrent run]`) are this by-design
unbounded default meeting real concurrent-lane contention on this shared machine — every
one of them resolved deterministically once bounded (`LEADV2_SUITE_LOCK_WAIT_S=5` or
`=60` above), never actually hung forever. If CI needs a hard ceiling, the fix is a
default `LEADV2_SUITE_LOCK_WAIT_S` in `run-core-offline.sh` — not a staleness fix, and
`run-core-offline.sh` is outside this lane's `LANE_WRITES`, so not changed here. Also
recorded in `docs/handoff/HOOK-OUTPUT-CAP-PLUGIN-01/report.md`.

## Self-check (falsification set)

```
$ bash -n tests/run-all.sh
(clean, no output)
```
No Python files touched this round.

```
$ cd /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HOOK-OUTPUT-CAP-PLUGIN-01
$ LEADV2_SUITE_LOCK_WAIT_S=60 timeout 300 bash tests/run-all.sh --scope changed
... run-all: 4 passed, 1 failed, scope=changed   # 1 fail = lock contention, unrelated (see above)
```

## What I did NOT touch this round

- `plugins/leadv2/hooks/leadv2-one-copy-drift.sh`, `leadv2-truth-card-inject.sh` —
  unchanged, rounds 1-2 fixes stand.
- `plugins/leadv2/scripts/tests/run-core-offline.sh` — the lock's unbounded-default-wait
  behaviour is documented but not changed; outside `LANE_WRITES`.
- `hooks.json` — not touched (off_limits per mission).
- No new file added to `plugins/leadv2/scripts/tests/test-hook-output-cap.sh` for the
  range-selection logic itself — that logic lives in `tests/run-all.sh`'s suite
  discovery, not the hook scripts; the scratch-clone properties + control above are the
  falsification evidence for it, matching the mission's "Done means" requirement
  verbatim (both properties + control, pasted, from a scratch clone).

## Commit

```
$ git log --oneline -1
0f95c19 fix(tests): bound --scope changed to unseen commits, not the whole lane range forever
$ git status --short tests/run-all.sh docs/handoff/HOOK-OUTPUT-CAP-PLUGIN-01/report.md
(clean — committed)
```

DELIVERABLE_COMPLETE
