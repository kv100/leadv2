verdict: APPROVE
next_action: review_round_2

# dispatch-983919b0 — prove degrade_frozen_registry_copy's neutralization write

No `context.yaml` existed for this task-id; worked from the mission text directly
(LANE_WRITES restricted to the test file and this handoff dir, as instructed).

## What changed

`plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh` only. No
change to `plugins/leadv2/scripts/leadv2-lane-worktree.sh` survives (see control
proof below — diff is clean after restore).

Added:
- `REAL_SCRIPTS_DIR`, `make_broken_resolver_mirror()`, `run_ensure_mirror()`,
  `assert_neutralized()` helpers.
- Case **2d** — fresh-branch site (`worktree add -b`), resolver-failure.
- Case **4b** — attach-to-existing-branch site (`worktree add <branch>`,
  mirrors case 4's "branch survived a prior aborted run" path), resolver-failure.

### How the resolver failure is forced (without touching the product script)

`degrade_frozen_registry_copy()` computes `script_dir` from its own
`BASH_SOURCE[0]` and calls `"$script_dir/leadv2-state-path.sh"`. To make that
resolution fail for exactly one `cmd_ensure` invocation, `make_broken_resolver_mirror()`
builds a scratch directory that symlinks through every sibling of the real
`plugins/leadv2/scripts/` dir (so all other relative lookups — including the
`lib/leadv2-worktree-protected.sh` require — still resolve correctly) except
`leadv2-state-path.sh`, which is replaced by a stub:

```bash
#!/usr/bin/env bash
# present + executable, but always fails to resolve (empty stdout,
# non-zero exit) -- simulates a corrupt state-paths.yaml override or
# an unreadable ~/.claude/leadv2-state dir in production.
exit 1
```

`run_ensure_mirror()` then does `source '${mirror}/leadv2-lane-worktree.sh'`
instead of the real `LANE_SH` for that one invocation only. Every other case in
the suite (0, 1, 2, 2b, 3, 4, 5) still sources the real, unmodified
`leadv2-lane-worktree.sh` / `leadv2-state-path.sh` pair.

This mirrors a real production failure mode of the resolver: `sp_bin` present
and executable but exiting non-zero with empty stdout — exactly the
`[[ -z "${live:-}" ]]` branch in `degrade_frozen_registry_copy()` — caused e.g.
by a corrupt `state-paths.yaml` override or an unreadable
`~/.claude/leadv2-state` directory, not by the resolver being missing.

### Assertion (post-state of the file, no stderr text)

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

## Baseline run (before control)

```
PASS: 0: bash -n .../leadv2-lane-worktree.sh
PASS: 1: BEFORE (raw git worktree add, no degrade helper) -- frozen plain file resurrected, exactly the defect
PASS: 2: AFTER (fresh-branch site) -- frozen file replaced by symlink to the live registry (active.yaml)
PASS: 2b: AFTER (fresh-branch site) -- git update-index --skip-worktree applied
PASS: 2d: AFTER (fresh-branch site, resolver failure) -- frozen copy overwritten with NOT-A-REGISTRY sentinel
PASS: 3: BEFORE (raw git worktree add, attach site) -- frozen plain file resurrected
PASS: 4: AFTER (attach-to-existing-branch site) -- frozen file replaced by symlink to the live registry
PASS: 4b: AFTER (attach-to-existing-branch site, resolver failure) -- frozen copy overwritten with NOT-A-REGISTRY sentinel
PASS: 5: branch never tracked active.yaml -- left untouched (no phantom file created)
test-lane-worktree-registry-pointer: 9 passed, 0 failed
RC=0
```

## Control: mutate the neutralization line, run, restore

`degrade_frozen_registry_copy()` is ONE function shared by both call sites
(fresh-branch line ~288 and attach line ~295) — the comment above it says so
explicitly ("Fix at the one chokepoint both creation sites share"). The
resolver-failure neutralization write is therefore a single line reached from
either site, so one mutation of that line is the correct control for both new
cases (2d exercises it via the fresh-branch call site, 4b via the attach call
site) — I did not duplicate the mutation because there is no separate
per-site copy of this code to mutate; duplicating it would not test anything
different.

**Mutated line** (`grep -n` before trusting the result):
```
341:    true # MUTATED-FOR-CONTROL-DO-NOT-COMMIT: neutralization no-op
```
(replacing the original:
`printf 'NOT-A-REGISTRY: ...' > "$frozen" 2>/dev/null || rm -f "$frozen" 2>/dev/null`)

**baseline_rc = 0** (see run above)

**mutated_rc = 1**, full red list under mutation:
```
PASS: 0: bash -n .../leadv2-lane-worktree.sh
PASS: 1: BEFORE (raw git worktree add, no degrade helper) -- frozen plain file resurrected, exactly the defect
PASS: 2: AFTER (fresh-branch site) -- frozen file replaced by symlink to the live registry (active.yaml)
PASS: 2b: AFTER (fresh-branch site) -- git update-index --skip-worktree applied
FAIL: 2d: AFTER (fresh-branch site, resolver failure) -- frozen copy survived unneutralized: lanes: {}
PASS: 3: BEFORE (raw git worktree add, attach site) -- frozen plain file resurrected
PASS: 4: AFTER (attach-to-existing-branch site) -- frozen file replaced by symlink to the live registry
FAIL: 4b: AFTER (attach-to-existing-branch site, resolver failure) -- frozen copy survived unneutralized: lanes: {}
PASS: 5: branch never tracked active.yaml -- left untouched (no phantom file created)
test-lane-worktree-registry-pointer: 7 passed, 2 failed
MUTATED_RC=1
```
Only 2d and 4b reddened; 1, 2, 2b, 3, 4, 5 kept their round-1 green result —
fixture is correctly scoped (no unrelated cases affected).

**Restore + verify clean diff:**
```
$ git diff --stat plugins/leadv2/scripts/leadv2-lane-worktree.sh
(empty — no output)
```

**restored_rc = 0**, full run after restore:
```
PASS: 0: bash -n .../leadv2-lane-worktree.sh
PASS: 1: BEFORE (raw git worktree add, no degrade helper) -- frozen plain file resurrected, exactly the defect
PASS: 2: AFTER (fresh-branch site) -- frozen file replaced by symlink to the live registry (active.yaml)
PASS: 2b: AFTER (fresh-branch site) -- git update-index --skip-worktree applied
PASS: 2d: AFTER (fresh-branch site, resolver failure) -- frozen copy overwritten with NOT-A-REGISTRY sentinel
PASS: 3: BEFORE (raw git worktree add, attach site) -- frozen plain file resurrected
PASS: 4: AFTER (attach-to-existing-branch site) -- frozen file replaced by symlink to the live registry
PASS: 4b: AFTER (attach-to-existing-branch site, resolver failure) -- frozen copy overwritten with NOT-A-REGISTRY sentinel
PASS: 5: branch never tracked active.yaml -- left untouched (no phantom file created)
test-lane-worktree-registry-pointer: 9 passed, 0 failed
RESTORED_RC=0
```

## bash -n on every shell file changed

```
$ bash -n plugins/leadv2/scripts/leadv2-lane-worktree.sh && echo "BASHN_LANE_OK"
BASHN_LANE_OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh && echo "BASHN_TEST_OK"
BASHN_TEST_OK
```
(`leadv2-lane-worktree.sh` is unchanged in the final tree — bash -n run for
completeness per instruction "every shell file you changed"; its content is
byte-identical to HEAD.)

## 10 consecutive runs post-restore

```
run 1 rc=0
run 2 rc=0
run 3 rc=0
run 4 rc=0
run 5 rc=0
run 6 rc=0
run 7 rc=0
run 8 rc=0
run 9 rc=0
run 10 rc=0
```

## Scratch worktree hygiene

All scratch git repos and worktrees created by the suite are created and removed
entirely inside the suite's own `mktemp -d` / `WT_CLEANUP` / `trap cleanup EXIT`
machinery (pre-existing pattern, unchanged) — none touch this repo's own refs or
`git worktree prune`. I created no additional scratch worktrees by hand outside
the suite invocation, so there was nothing extra to remove via `git worktree
remove`. `git worktree list` on the real repo shows one pre-existing stray
entry (`/private/var/folders/.../tmp.IPkMdJq7qK`, detached HEAD) that predates
this session — my fixtures never register a worktree against the real repo (they
`git init` their own throwaway repos under `$TMPDIR`), so this is unrelated and
was left untouched per the no-destructive-ops rule.

## What I deliberately left alone

- Did not add a second, separately-mutable copy of the neutralization line —
  there is only one, shared by both call sites (see control section above).
- Did not touch `leadv2-lane-worktree.sh` in the final commit (only during the
  transient control, fully restored — `git diff` confirms no changes).
- Did not modify `tests/run-all.sh`, `tests/known-red-suites.txt`, `main`, or
  `docs/leadv2/`.
- Did not create a `context.yaml` for this task-id (none existed; not in my
  writable scope to create one).

## Commit

Committed on the current branch
`worktree-WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01` (no push, no
merge, no main). Commit SHA recorded after `git commit` below.

DELIVERABLE_COMPLETE
