verdict: APPROVE
next_action: review_round_2

# WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01 — developer full report

## Scope honored
Only touched:
- `plugins/leadv2/scripts/leadv2-lane-worktree.sh`
- `plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh`
- `docs/handoff/WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01/*`

Did not touch `leadv2-dispatch-code.sh`, `tests/run-all.sh`, `tests/known-red-suites.txt`, `docs/leadv2/` (live runtime state), or `main`. No `git worktree prune`, `reset --hard`, `clean`, or bare `stash` was run anywhere in this session.

`docs/handoff/dispatch-983919b0/context.yaml` does not exist in this worktree (checked at start) — no prior decisions/off_limits to honor beyond the mission text itself.

## The fix

New shared helper `degrade_frozen_registry_copy()` in `leadv2-lane-worktree.sh`, called immediately after both `git worktree add` successes (fresh-branch site ~line 286, attach-to-existing-branch site ~line 293), before `codex_trust_worktree`:

```bash
degrade_frozen_registry_copy() { # <abs_worktree_path>
  local lane_path="${1:-}"
  [[ -n "$lane_path" ]] || return 0
  local frozen="$lane_path/docs/leadv2/active.yaml"
  [[ -e "$frozen" && ! -L "$frozen" ]] || return 0

  local sp_bin script_dir live
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  sp_bin="${script_dir}/leadv2-state-path.sh"
  if [[ -x "$sp_bin" ]]; then
    live="$(PROJECT_ROOT="$lane_path" "$sp_bin" --no-link active.yaml 2>/dev/null)"
  fi
  if [[ -z "${live:-}" ]]; then
    log_error "degrade_frozen_registry_copy: could not resolve live active.yaml path via $sp_bin for $lane_path -- neutralizing frozen copy so it is never mistaken for the registry"
    printf 'NOT-A-REGISTRY: ...\n' > "$frozen" 2>/dev/null || rm -f "$frozen" 2>/dev/null
    return 0
  fi

  rm -f "$frozen" 2>/dev/null
  if ln -s "$live" "$frozen" 2>/dev/null; then
    git -C "$lane_path" update-index --skip-worktree docs/leadv2/active.yaml 2>/dev/null || true
  else
    log_error "degrade_frozen_registry_copy: symlink creation failed ($frozen -> $live) -- writing non-YAML sentinel so a stale copy is never mistaken for live state"
    printf 'NOT-A-REGISTRY: ...\n' > "$frozen" 2>/dev/null
  fi
  return 0
}
```

Design choices:
- **`--no-link` on the `leadv2-state-path.sh` call**: this resolver already does its OWN migration/symlink repair for `docs/leadv2/active.yaml` when called without `--no-link` (moving a real local file into the control plane and symlinking it, per its own header). I deliberately did NOT rely on that side effect — the mission wants explicit control of the failure path (visible sentinel on failure, `--skip-worktree` applied), so I resolve the path only (`--no-link`) and do the symlink + skip-worktree myself. This is a decision worth flagging in review: the two mechanisms now overlap in intent (both want a symlink at `docs/leadv2/active.yaml`), but only mine adds `--skip-worktree` and the fail-loud sentinel. If a bare, non-`--no-link` call to `leadv2-state-path.sh` runs elsewhere in the new worktree AFTER this fix (e.g. from a later lane script), its migration branch will see the symlink already in place and leave it alone (`os.path.islink(local)` branch) — no conflict observed in testing.
- **`[[ -e "$frozen" && ! -L "$frozen" ]]`**: only a REAL file is the hazard; an existing correct symlink (main-lineage branches, or a worktree already repaired) is left alone.
- **Failure path**: if `leadv2-state-path.sh` resolution fails OR the `ln -s` fails, the frozen file is overwritten with a `NOT-A-REGISTRY: ...` sentinel (not valid YAML lane data) and a loud `log_error` to stderr — never left as a stale-but-plausible copy. If even the sentinel write fails, the file is removed outright.

## False premise found in the mission
The mission cites `_lv2_repoint_newest_pointer` at `claude-subsession.sh:463` as "a documented mistake to avoid." I grepped the whole repo (`repoint`, `newest_pointer`, `newest pointer`) — no function or comment by that name exists anywhere in this checkout; line 463 of `claude-subsession.sh` is inside an unrelated function (`leadv2_select_claude_profile`'s selector-polling loop). I could not verify this specific anti-pattern instance, so I did not build on it as fact. I did honor the STATED principle (never do half the fix and silently return success) in the implementation above — the failure branches are loud (stderr) and visibly non-authoritative (sentinel content), never a silent `return 0` after a partial repair.

I also could not find a `# run-all-triggers:` comment convention anywhere in the repo (grepped `run-all-triggers` — the only hit is the mission's own brief.md, which is this task's spec doc, not a repo convention). Since editing `tests/run-all.sh`'s `EXTRA_SUITE_MAP` is explicitly off-limits for this lane, I registered nothing there. The new suite self-selects via the existing generic mechanism every other suite relies on: (a) `--scope all` picks up any `tests/test-*.sh` file, and (b) `--scope changed` always re-selects a test file that is itself part of the diff (`case "${cf}" in plugins/leadv2/scripts/tests/test-*.sh) add_suite ...`). It will NOT auto-select on a future *unrelated* change to `leadv2-lane-worktree.sh` that leaves this test file untouched — that would require an `EXTRA_SUITE_MAP` row, which is out of this lane's writable scope. Flagging this as a follow-up for whoever owns `tests/run-all.sh`.

## Test suite — `test-lane-worktree-registry-pointer.sh`

Entirely self-contained `mktemp -d` scratch git repos (never this repo's own refs/worktrees). Every worktree the suite creates is removed via `git worktree remove --force` in a trap-based cleanup; `git worktree prune` is never called.

7 assertions:
1. BEFORE (fresh-branch site): raw `git worktree add -b` with no `degrade_frozen_registry_copy` call reproduces the defect — frozen plain file, not a symlink, containing the stale marker.
2. AFTER (fresh-branch site): `cmd_ensure` (which now calls the helper) resolves `docs/leadv2/active.yaml` to a symlink matching `leadv2-state-path.sh --no-link active.yaml`'s resolved live path.
2b. `git ls-files -v` on the lane's `docs/leadv2/active.yaml` shows the `S` (skip-worktree) flag.
3. BEFORE (attach-to-existing-branch site): same reproduction via the second `worktree add` form.
4. AFTER (attach-to-existing-branch site): same symlink assertion, exercised through the actual `cmd_ensure` fallback path (branch pre-exists with no worktree dir, `LEADV2_LANE_RESURRECT_GUARD=0` to bypass the unrelated WORKTREE-RESURRECTOR-02 gate — the branch-exists-but-not-live refusal is a different, already-tested concern).
5. Negative/no-op control: a branch that never tracked `docs/leadv2/active.yaml` (plain `main` lineage) is left with no file at all after `cmd_ensure` — proves the fix doesn't fabricate a phantom file.

`LEADV2_STATE_BASE` is sandboxed per-fixture (`<fixture>/state-base`) throughout — never touches the real `~/.claude/leadv2-state/`.

### `bash -n` output
```
$ bash -n plugins/leadv2/scripts/leadv2-lane-worktree.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh && echo OK
OK
```
(also verified with `/bin/bash -n`, the bash 3.2 binary, per the mission's "run the suite" instruction — both pass.)

### Full suite output (single run)
```
PASS: 0: bash -n .../leadv2-lane-worktree.sh
PASS: 1: BEFORE (raw git worktree add, no degrade helper) -- frozen plain file resurrected, exactly the defect
PASS: 2: AFTER (fresh-branch site) -- frozen file replaced by symlink to the live registry (active.yaml)
PASS: 2b: AFTER (fresh-branch site) -- git update-index --skip-worktree applied
PASS: 3: BEFORE (raw git worktree add, attach site) -- frozen plain file resurrected
PASS: 4: AFTER (attach-to-existing-branch site) -- frozen file replaced by symlink to the live registry
PASS: 5: branch never tracked active.yaml -- left untouched (no phantom file created)
test-lane-worktree-registry-pointer: 7 passed, 0 failed
```

### 10 consecutive runs — exit codes
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

## Mutation control (negative control) via `leadv2-mutation-control.sh`

Mutated the guard line inside `degrade_frozen_registry_copy()`'s body:
```
[[ -e "$frozen" && ! -L "$frozen" ]] || return 0
```
→
```
return 0  # MUTATED-guard-always-returns
```
i.e. the helper now unconditionally no-ops — exactly "does half the fix and returns success anyway," the anti-pattern the mission warns against — proving the suite catches THAT specific failure mode.

Invocation (from the real worktree root, base = merge-base with `main`):
```
$ LEADV2_LANE_START_SHA=5603835a1a0b166ec8b782a312d22059e91a2fbe bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
    plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh \
    plugins/leadv2/scripts/leadv2-lane-worktree.sh \
    's/\[\[ -e "\$frozen" && ! -L "\$frozen" \]\] || return 0/return 0  # MUTATED-guard-always-returns/' \
    docs/handoff/WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01/mc-task
MUTATION-CONTROL ok suite=... file=... red_line=FAIL: 2: got symlink target='' want='.../active.yaml' ... diff_hash=4a6e32877c08ec30532c432a650cf6222a446645bd5981c510d23356fe140b0f lane_diff_hash=72c29dc651baba90f729c468a91257d94fae8a8f281139ce7b60a56616333203
rc=0
```

Artifact (`mutation-control/20260904T054422Z-73304.txt`):
```
suite=plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh
file=plugins/leadv2/scripts/leadv2-lane-worktree.sh
anchor=s/\[\[ -e "\$frozen" && ! -L "\$frozen" \]\] || return 0/return 0  # MUTATED-guard-always-returns/
baseline_rc=0
mutated_rc=1
red_line=FAIL: 2: got symlink target='' want='...active.yaml' (stderr: Preparing worktree (new branch 'worktree-TASK-FRESH')
diff_hash=4a6e32877c08ec30532c432a650cf6222a446645bd5981c510d23356fe140b0f
lane_diff_hash=72c29dc651baba90f729c468a91257d94fae8a8f281139ce7b60a56616333203
```

- `baseline_rc=0` — suite is green on the unmutated scratch snapshot.
- `mutated_rc=1` — suite goes red under the mutation.
- `restored_rc=0` — confirmed separately by re-running the suite in this actual worktree (the mutation-control tool operates only on a scratch snapshot, never on the real file, so the real file was never mutated to begin with; re-ran the suite here after the mutation-control invocation to prove the real tree is still green): `restored_rc=0`.
- **The mutated line was printed back and confirmed changed** (`grep -n "MUTATED-guard" ...leadv2-lane-worktree.sh` inside the scratch copy showed `331:  return 0  # MUTATED-guard-always-returns` — real semantic change, not whitespace).

**Which assertions went red**: I additionally applied the same mutation to a throwaway full scratch copy (outside the mutation-control tool, for visibility) and ran the whole suite directly. Because `degrade_frozen_registry_copy()` is the SHARED helper both creation sites call, disabling its guard breaks the fix for BOTH sites at once — assertions **2, 2b, and 4** (all three "AFTER" assertions that exercise the fix) go red, while **0, 1, 3, 5** (bash -n, both BEFORE reproductions, and the no-op control) stay green:
```
PASS: 0 ... PASS: 1 ...
FAIL: 2: got symlink target='' want='.../active.yaml' ...
FAIL: 2b: expected skip-worktree flag 'S', got 'H' (git ls-files -v)
PASS: 3 ...
FAIL: 4: got symlink target='' want='.../active.yaml' ...
PASS: 5 ...
test-lane-worktree-registry-pointer: 4 passed, 3 failed
```
This is the correct/expected shape for a shared-helper mutation (not a single-assertion result) — exactly the right set of assertions (all and only the ones dependent on the mutated code path) went red, and no unrelated assertion (BEFORE reproductions, bash -n, no-op control) was affected.

## What I left alone
- `leadv2-dispatch-code.sh` — untouched, per explicit instruction (another session owns it).
- `tests/run-all.sh` / `EXTRA_SUITE_MAP` — untouched (off-limits); see "False premise" section above for the consequence (no automatic re-select on unrelated future edits to `leadv2-lane-worktree.sh`).
- `docs/leadv2/` (live runtime state) and `main` — untouched.
- The overlapping intent between my explicit symlink+skip-worktree logic and `leadv2-state-path.sh`'s own non-`--no-link` migration behavior — flagged above as a review point, not resolved by unifying them (mission explicitly wants the resolve-only `--no-link` call plus manual control of the fail-loud path).

DELIVERABLE_COMPLETE
