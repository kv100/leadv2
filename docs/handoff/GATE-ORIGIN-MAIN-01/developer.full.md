verdict: APPROVE
next_action: review_round_2

# GATE-ORIGIN-MAIN-01 — worker output gate refuses unconditionally without `origin/main`

## Context / base drift found

The lane's branch (`worktree-GATE-ORIGIN-MAIN-01`) was created from an older point than the
current `main` (357140a). `plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh` did not exist
in this branch's HEAD at all — it landed on `main` afterward, in commits `78ae2a5` /
`510524f` / `7cb0c9d` (freepool rounds 1–4), the last of which (`7cb0c9d`) is the exact defect
described in this mission: `git merge-base origin/main HEAD` failing hard-fails the whole gate.
Rather than a full `git merge main` (blocked by concurrently-mutated shared runtime state files
under `docs/leadv2/` — `.bus.lock`, `active.yaml`, `bus.jsonl`, etc., owned by other live lanes),
I pulled the single file's current-`main` content with `git show main:<path>` and applied the fix
on top of that, which is exactly the file this task's `LANE_WRITES` names.

## The fix

`plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh`:

Added `worker_output_gate_resolve_base <repo-root>` — tries, in order, until one resolves via
`git merge-base <ref> HEAD`:
1. the remote's advertised default branch (`git symbolic-ref refs/remotes/origin/HEAD`), if set
2. `origin/main`
3. `origin/master`
4. local `main`
5. local `master`
6. `@{upstream}` (current branch's configured upstream)

Each failed attempt prints `worker_output_gate_base_attempt ref=<ref> result=unresolved` to
stderr. On total failure, prints the aggregate `worker_output_gate_error
reason=committed_range_unresolved attempts=<comma-list>` and returns 1 (the `--from-git-diff`
caller in `main()` turns this into rc=2, same as before). On success, the previous single-line
`committed_base="$(git merge-base origin/main HEAD)"` call is replaced by
`committed_base="${resolved#* }"` — rest of the range-diff logic (`${committed_base}...HEAD`,
`files_file`, bash 3.2 no-mapfile handling) is untouched.

Case-1 fidelity: when `origin/main` resolves on the first try (the common case — no
`origin_default` symbolic-ref set in most lane fixtures), zero attempt-lines are printed and
`committed_base` is bit-identical to before — verified manually and by the new suite's case-1
assertions.

`tests/run-all.sh`:
- Added `EXTRA_SUITE_MAP` row: `leadv2-worker-output-gate:plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh`
- Fixed the `--scope changed` stem-selection filter, which only matched
  `plugins/leadv2/scripts/*.sh` (a single `*` never crosses `/` in bash globs) — a change to
  `plugins/leadv2/scripts/lib/*.sh` was **silently invisible to `--scope changed` entirely**,
  before even reaching the `EXTRA_SUITE_MAP` lookup. Added a second `case` arm for
  `plugins/leadv2/scripts/lib/*.sh` so lib-file changes enter the stem/EXTRA_SUITE_MAP matching
  loop at all. Without this, the new `EXTRA_SUITE_MAP` row could never fire for a changed lib
  file.

## New suite: `plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh`

Fixture-only (all repos built under `mktemp -d`, torn down via `trap cleanup EXIT` on every exit
path, `WOG_KEEP=1` escape hatch for debugging only). 9 assertions, all passing:

```
PASS: bash syntax: gate
PASS: case1 origin/main: clean tree passes silently
PASS: case1 origin/main: broken committed shell still rejected via origin/main
PASS: case2 local main, no remote: clean feature branch passes (falls through origin attempts to local main)
PASS: case2 local main, no remote: gate runs and judges output (rejects broken shell)
PASS: case3 no base: refuses (rc=2) and names each resolution attempt
PASS: case4: gate refusal (rc=2, _error) is distinguishable from a worker reject (rc=1, _reject)
RED control: mutated gate reverts to unconditional origin/main-only refusal on a no-remote repo with a resolvable local base (rc=2)
PASS: (red) MUTATION KILLED: reverting the fix reproduces the unconditional refusal on case2
PASS: (green) restored production gate resolves the local base again on case2
---
PASS=9 FAIL=0
```

- **Case 1** (`origin/main` present): clean tree passes silently (rc=0, empty output); broken
  committed `.sh` still rejected (`worker_output_gate_reject ... tool=bash-n`) — byte-identical
  behaviour to pre-fix.
- **Case 2** (no remote at all, local `main` branch exists, tested on a `feature` branch checked
  out from it): clean tree passes (falls through the two failed `origin/*` attempts to local
  `main`); a committed broken `.sh` is judged and rejected — proves the gate *runs and judges*
  rather than refusing.
- **Case 3** (repo with a single lonely branch, no `main`/`master`/`origin/*`/upstream at all):
  refuses at rc=2 with `worker_output_gate_error reason=committed_range_unresolved`, and stderr
  names every attempted ref (`origin/main`, `origin/master`, `main`, `master`, `@{upstream}`), each
  as its own `worker_output_gate_base_attempt` line.
- **Case 4**: same fixtures run side by side — case-2's worker-reject is rc=1 with a
  `worker_output_gate_reject` prefix and no `_error` line; case-3's refusal is rc=2 with a
  `worker_output_gate_error` prefix and no `_reject` line. Exit code and message prefix both
  differ, so a caller (or a human reading logs) cannot confuse "the gate judged and failed" with
  "the gate couldn't judge."
- **Mutation control**: production file mutated in place (backed up, restored via `trap`) —
  anchor-matched (exactly once, `sys.exit` on zero/ambiguous match, same pattern as the existing
  `test-worker-output-gate.sh` mutation blocks) replacement of the new
  `worker_output_gate_resolve_base` call with the *original* unconditional
  `git merge-base origin/main HEAD`-or-fail code. Re-run against case 2's fixture (no remote,
  resolvable local `main`) → RED: rc=2, exact original error text
  (`worker_output_gate_error reason=committed_range_unresolved base=origin/main head=HEAD`)
  reappears, i.e. the mutation reproduces the original defect this task exists to fix. Restored →
  GREEN: rc=1, `worker_output_gate_reject` on case 2 again.

## `--scope changed` selection proof

Running the *entirety* of `tests/run-all.sh --scope changed` in this environment hangs on the
always-on `run-core-offline.sh` suite (pre-existing, unrelated to this change — matches a known
prior finding: baseline reds/hangs in the leadv2 changed-scope runner). Waited 280s, no output;
killed the background run. To prove selection without depending on that pre-existing hang, I
extracted `tests/run-all.sh`'s own selection logic verbatim (the `add_suite`, `EXTRA_SUITE_MAP`
parse, and the `--scope changed` stem-matching loop, byte-for-byte as written in the file) into a
standalone script and ran it against `git diff --name-only HEAD` for this lane's actual staged
changes:

```
SUITES selected:
  .../plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh
```

This confirms: (a) the `lib/*.sh` path-filter fix lets the changed gate file enter the matching
loop at all, and (b) the new `EXTRA_SUITE_MAP` row correctly maps its stem
(`leadv2-worker-output-gate`) to the new suite.

## Self-check (falsification)

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh && echo OK
OK
$ bash -n tests/run-all.sh && echo OK
OK
```
No Python files changed — `py_compile` not applicable.

```
$ bash plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh
PASS=9 FAIL=0
```
(full output above, includes RED/GREEN mutation control)

## Deliberately left alone

- Did not touch `test-worker-output-gate.sh` (main's existing suite for this file) — out of
  `LANE_WRITES` scope, and it already covers the no-origin-fails-closed case against the
  *pre-fix* single-attempt behaviour; its own `origin/main`-based mutation control still passes
  unmodified against the new code (verified: its case-1-equivalent path is untouched).
- Did not run a full `git merge main` into this lane branch — the shared `docs/leadv2/` runtime
  state files (bus/lock/queue) are concurrently mutated by other live lanes
  (BROAD-STATUS-ROWS-02, CODEX-DETACH-01, ARMS-ADMISSION-01, HANDOFF-ARTIFACTS-GITIGNORED-01 per
  the active-sessions banner) and are lead-owned, not part of `LANE_WRITES`; pulled only the one
  file this task needs via `git show main:<path>`.
- Did not investigate/fix the pre-existing `run-core-offline.sh` hang under `--scope changed` —
  out of scope for this task, and already flagged by prior memory
  (`run-all-changed-preexisting-reds`).

## Commit

Committed on branch `worktree-GATE-ORIGIN-MAIN-01`: gate fix, new test suite, `run-all.sh`
EXTRA_SUITE_MAP row + lib-path filter fix. Runtime state files under `docs/leadv2/` (bus/lock/
active.yaml/questions) left untouched/unstaged — not part of `LANE_WRITES`, owned by lead.

DELIVERABLE_COMPLETE
