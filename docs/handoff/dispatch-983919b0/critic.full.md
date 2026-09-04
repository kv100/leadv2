verdict: APPROVE
next_action: deploy

# Review round 2 — dispatch-983919b0

Commits under review: a19eca15 (test) and e515c6f3 (docs). Scope claimed:
`plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh` +
`docs/handoff/WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01/`.

## 1. Diff scope — verified

`git show a19eca15 --stat`:
```
docs/handoff/dispatch-983919b0/developer.full.md   | 198 +++++++++++++++++++++
docs/handoff/dispatch-983919b0/developer.summary.md |   4 +
plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh | 85 +++++++++
```
`git show e515c6f3 --stat`:
```
docs/handoff/dispatch-983919b0/developer.full.md | 2 +-
```

No touch to `leadv2-lane-worktree.sh`, `tests/run-all.sh`, `docs/leadv2/`, or `main`. Confirmed by direct `git show`, not by trusting the developer's own report.

**Discrepancy (Low, informational):** the review mission specified docs scope as
`docs/handoff/WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01/` (the dir round-1's
developer deliverable actually used — commit 2e2db988). Round-2's developer instead wrote to
`docs/handoff/dispatch-983919b0/` (the task-id-keyed dir, per subagent protocol §5 "write to
`docs/handoff/<task-id>/<role>.md`", and no `context.yaml` existed for this task-id to say
otherwise). This is procedurally correct per the subagent protocol but means this task's
history is now split across two handoff directories. Not a code defect, not blocking — a
lead-side task-dispatch naming note, not a developer error.

## 2. Cases 2d/4b assert on file post-state, not stderr — verified by reading the code

`assert_neutralized()` (test-lane-worktree-registry-pointer.sh:137-146):
```bash
assert_neutralized() { # <label> <frozen-file-path>
  local label="$1" frozen="$2"
  if [[ ! -e "${frozen}" ]]; then
    pass "${label} -- frozen copy removed entirely (no phantom file left)"
  elif [[ -f "${frozen}" ]] && grep -q "NOT-A-REGISTRY" "${frozen}" 2>/dev/null; then
    pass "${label} -- frozen copy overwritten with NOT-A-REGISTRY sentinel"
  else
    fail "${label} -- frozen copy survived unneutralized: $(cat "${frozen}" 2>/dev/null | head -1)"
  fi
}
```
Both branches inspect `${frozen}` (the worktree's `docs/leadv2/active.yaml`) directly —
existence and grep-on-content. `${errf}` (stderr capture) is never read by the assertion;
it only appears inside the `fail` message of the *symlink*-path cases (2, 4), which is
unrelated to 2d/4b. Confirmed correct.

Also confirmed the fixture mechanics match the product code exactly by reading
`degrade_frozen_registry_copy()` (leadv2-lane-worktree.sh:324-353): the resolver-failure
branch is guarded by `[[ -z "${live:-}" ]]` where `live="$(PROJECT_ROOT=... "$sp_bin" ...)"`
— a stub `leadv2-state-path.sh` that's present+executable but `exit 1`s with no stdout
produces exactly that `-z` condition. `script_dir` is derived from the sourced script's own
`BASH_SOURCE[0]`, so sourcing `${mirror}/leadv2-lane-worktree.sh` (a symlink into the mirror)
correctly redirects `sp_bin` to the mirror's stub while every other sibling (including the
`lib/` subdirectory, itself symlinked whole) still resolves through the mirror to the real
files. Verified by direct read, not inference from the developer's narrative.

## 3. Independent control re-run — reproduced, not trusted

Ran myself, end to end, on the live checkout:

**Baseline (unmodified `leadv2-lane-worktree.sh`):**
```
test-lane-worktree-registry-pointer: 9 passed, 0 failed
BASELINE_RC=0
```
Matches developer's reported baseline exactly, including the 2d/4b PASS lines.

**Mutation applied** — line 341 of `leadv2-lane-worktree.sh` (the resolver-failure
neutralization `printf ... NOT-A-REGISTRY ...` write, confirmed by `grep -n` before mutating)
replaced with `true # MUTATED-FOR-CONTROL-DO-NOT-COMMIT: neutralization no-op`; `bash -n`
confirmed still syntactically valid post-mutation.

**Mutated run:**
```
PASS: 0 ... PASS: 1 ... PASS: 2 ... PASS: 2b ...
FAIL: 2d: AFTER (fresh-branch site, resolver failure) -- frozen copy survived unneutralized: lanes: {}
PASS: 3 ... PASS: 4 ...
FAIL: 4b: AFTER (attach-to-existing-branch site, resolver failure) -- frozen copy survived unneutralized: lanes: {}
PASS: 5
test-lane-worktree-registry-pointer: 7 passed, 2 failed
MUTATED_RC=1
```
Exactly 2d and 4b reddened; 1, 2, 2b, 3, 4, 5 stayed green — matches the developer's report
verbatim, independently reproduced rather than copy-checked.

**Restore:** `cp` the pre-mutation backup back over the file. `git diff --stat
plugins/leadv2/scripts/leadv2-lane-worktree.sh` and `git status --porcelain` on the same
path both produced empty output — clean restore confirmed.

**Post-restore, 5 consecutive runs** (task asked for 5x, ran 5x — developer's own report
separately claims 10x, both satisfy the ask):
```
run 1 rc=0 ... run 5 rc=0
```
All 5 runs: `9 passed, 0 failed`.

## 4. bash -n

```
$ bash -n plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh
(exit 0, no output)
```

## 5. Extra checks run beyond the ask

- `shellcheck -x` on the changed test file: only SC2094 (info-level, "don't read/write same
  file in same pipeline") on the two new `2>"${errf}"` redirects inside `run_ensure_mirror`
  (lines ~132, ~134). This is the same pattern the pre-existing `run_ensure()` already uses
  at lines 76/78 (unchanged by this diff) — copy-pasted, not a new defect. Low, advisory only.
- `git worktree list` on the real repo shows no new stray entries attributable to this suite;
  the one pre-existing detached-HEAD stray under `/private/var/folders/.../tmp.IPkMdJq7qK`
  the developer disclosed is still there, unrelated (predates this session, and this suite's
  fixtures `git init` their own throwaway repos under `mktemp -d`, never touching the real
  repo's refs).

## Findings

None blocking. Two Low/informational notes, already stated above (handoff-dir split across
rounds; pre-existing SC2094 info-level shellcheck pattern reused). Neither requires a change
before merge.

## Contradiction scan

- Env var names used (`LEADV2_PROJECT_ROOT`, `LEADV2_WORKTREE_DIR`,
  `LEADV2_CODEX_WORKTREE_TRUST`, `LEADV2_LANE_WORKTREE_ERRF`, `LEADV2_LANE_RESURRECT_GUARD`,
  `LEADV2_STATE_BASE`) are unchanged from the pre-existing `run_ensure()` — `run_ensure_mirror()`
  reuses the identical set. No new/renamed flags introduced.
- No flag semantics changed; no new config surface added.
- Paths asserted against (`docs/leadv2/active.yaml`, `leadv2-state-path.sh`,
  `lib/leadv2-worktree-protected.sh`) all verified to exist at the claimed relative locations
  by reading `degrade_frozen_registry_copy()` directly, not by trusting the test's comments.
- None found.

## Verdict

**APPROVE.** The control reproduces cleanly and independently, scope is clean, assertions are
on file post-state as required, and no product-script line was left mutated.

DELIVERABLE_COMPLETE
