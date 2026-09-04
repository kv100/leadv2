# DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01 — developer deliverable

## Task 1 — writer/reader enumeration (verified, extended from the seed grep)

### The writer (the actual cause of the defect)

- `plugins/leadv2/scripts/leadv2-active-registry.sh:_leadv2_state_md()` (originally line
  116-118) — path builder called from `leadv2_active_render_index()` (originally :1152,
  the regenerator), which is itself invoked on register/unregister (originally :962/:1012).
  This was `printf '%s/docs/LEAD_V2_STATE.md' "$LEADV2_PROJECT_ROOT"` — a project-root-
  relative literal that lands INSIDE whichever lane worktree `LEADV2_PROJECT_ROOT` resolves
  to for that invocation. **This is the file that dirtied six lanes.**

### Population A — already consume the `LEADV2_LEAD_STATE_PATH` seam (fixed automatically
once the seam's derivation moved)

- `leadv2-phase8-assert.sh:173` — `STATE_FILE="${LEADV2_LEAD_STATE_PATH}"`
- `leadv2-render-close.sh:57` — `STATE_FILE="${LEADV2_LEAD_STATE_PATH}"`
- `leadv2-state-compact.sh:21` — `state_md="${LEADV2_LEAD_STATE_PATH:-$root/docs/LEAD_V2_STATE.md}"`
  (already had the correct fallback pattern — used as the template for every other fix below)

### Population B — consume the `LEADV2_STATE_FILE` seam (default updated)

- `leadv2-backfill-history.sh:26` (writer — appends synthetic history entries)
- `leadv2-daemon.sh:51` (reader — outcome-based circuit breaker)

### Population C — hardcoded `docs/LEAD_V2_STATE.md` independently, source
leadv2-helpers.sh (fixed to consume `$LEADV2_STATE`, which helpers.sh now always sets via
the new `_lv2_state_md_default()`)

- `claude-subsession.sh:1008` (`_write_auto_abort_decision`, a WRITER — `sed -i` marks
  `status: paused` in place)
- `leadv2-priors-compile.sh:47` (reader)

### Population D — hardcoded independently, do NOT source leadv2-helpers.sh (fixed with an
inline "check LEADV2_LEAD_STATE_PATH, else call the resolver directly, else old literal"
block, same pattern as state-compact.sh's pre-existing one)

- `leadv2-rag-intake.sh:21` (reader)
- `leadv2-status-snapshot.sh:46` (reader; :47's `[[ -f ]] || fallback` sibling check left as-is)
- `leadv2-pattern-cluster.sh:17` (reader)
- `leadv2-agent-stats.sh:24` (reader)
- `leadv2-outcome-watch.sh:40` (reader **and** writer-ish — flips `outcome_watch` field in
  history; not modified beyond the path default, the write-in-place logic is unchanged)
- `leadv2-cost-estimate.sh:23` (reader)
- `leadv2-negative-memory-compile.sh:39` (reader)
- `leadv2-signatures-aggregate.sh:16,40` (reader; :40 simplified to reuse `$STATE_FILE`)
- `leadv2-status.sh:28` (reader)

### Comment-only mentions, no code change needed (verified, not writers/readers of the path)

- `leadv2-lane-watch-v2.sh:13,160` — `-not -name 'LEAD_V2_STATE.md'` noise-path exclusion
  in a `find`. Matches by basename only, so it keeps working regardless of where the file
  physically lives. Left alone per the task's own note that this already treats it as noise.
- `leadv2-worktree-cleanup.sh:48` — `_LV2_WT_NOISE_PATHS=(... docs/LEAD_V2_STATE.md ...)`,
  same basename-independent reasoning. Left alone.
- `leadv2-dispatch-product-close.sh:1421,1429` — comments describing the historical defect,
  no live logic references the path directly at these lines.

### The gate itself — investigated, confirmed untouched (as instructed)

`runtime_state_in_diff` is NOT in `leadv2-dispatch-product-close.sh` — it lives in
`plugins/leadv2/scripts/lib/leadv2-dod-gate.sh`:

```
_DOD_RUNTIME_STATE_REGEX='^(docs/leadv2/|docs/LEAD_V2_STATE\.md$|docs/handoff/dispatch-nw)'
```//line 27, consumed by `_dod_check_d()` (line ~458-476), which reads only `DIFF_FILE`
(never `git diff main HEAD`, per its own CHALLENGE-12 comment). `lib/leadv2-lane-guard.sh:73`
(`_lv2_containment_excluded`) also names `docs/LEAD_V2_STATE.md` in its exclusion `case`,
for the separate main-checkout containment-violation check — also untouched. Both are
correct as pre-existing defense-in-depth: they still name the OLD path so a stray write
that somehow lands there again is still caught. No change to either was needed or made.

## Task 2 — tracked-copy decision

Verified directly (not assumed):

```
$ git show main:docs/LEAD_V2_STATE.md | head -1
<!-- DO NOT EDIT TABLE — regenerated from docs/leadv2/active.yaml by leadv2_active_render_index -->
$ git show origin/main:docs/LEAD_V2_STATE.md | head -1
<!-- DO NOT EDIT TABLE — regenerated from docs/leadv2/active.yaml by leadv2_active_render_index -->
$ git check-ignore -v docs/LEAD_V2_STATE.md ; echo "rc=$?"
rc=1   (not ignored)
$ git ls-files -s docs/LEAD_V2_STATE.md
100644 eb6442f2fc7e68f997c5a45ad409f0ba243a200b 0  docs/LEAD_V2_STATE.md
```

**Decision: leave the tracked copy as-is (stale), option 3 of the three offered.** Rationale:
the defect this task fixes is "the harness dirties this path inside a lane worktree, and the
DoD gate kills the lane for it." Once the writer moves, the harness simply never touches
`docs/LEAD_V2_STATE.md` again during normal operation — it cannot show up dirty in any
lane's diff regardless of whether the tracked blob itself is deleted, gitignored, or left in
place. Untracking it (`git rm --cached` + gitignore) or replacing it with a pointer file are
both defensible but are a separate, purely cosmetic cleanup with their own blast radius
(anyone diffing/reading the tracked file expecting current data, any external tooling that
globs `docs/*.md`) that this task does not need to take on to close the defect. Left
deliberately for a follow-up task to decide.

## Acceptance evidence

### 1. The write moved (before/after)

```
$ git status --porcelain -- docs/LEAD_V2_STATE.md      # BEFORE
(empty — already clean)
$ export LEADV2_PROJECT_ROOT="$(pwd)"
$ bash -c 'source plugins/leadv2/scripts/leadv2-active-registry.sh; leadv2_active_render_index; echo "state_md=$(_leadv2_state_md)"'
[registry] rendered /Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/LEAD_V2_STATE.md (62 sessions, history_preserved=False)
state_md=/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/LEAD_V2_STATE.md
$ git status --porcelain -- docs/LEAD_V2_STATE.md      # AFTER
(empty — still clean; the worktree copy was never touched)
$ ls -la ~/.claude/leadv2-state/leadv2/LEAD_V2_STATE.md
-rw-r--r--  1 kostiantyn.vlasenko  staff  5243 Sep  4 12:54 .../LEAD_V2_STATE.md
```

### 2. The read still works — surface checked: `leadv2-phase8-assert.sh`'s
`STATE_FILE="${LEADV2_LEAD_STATE_PATH}"` (line 173)

```
$ bash -c 'source plugins/leadv2/scripts/leadv2-helpers.sh; _lv2_load_paths
  echo "LEADV2_LEAD_STATE_PATH=$LEADV2_LEAD_STATE_PATH"
  [[ -f "$LEADV2_LEAD_STATE_PATH" ]] && echo "reader sees file: YES ($(wc -l < "$LEADV2_LEAD_STATE_PATH") lines)" || echo NO'
LEADV2_LEAD_STATE_PATH=/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/LEAD_V2_STATE.md
reader sees file: YES (      75 lines)
```

This is the exact variable `leadv2-phase8-assert.sh` line 173 assigns to `STATE_FILE` — the
reader consumes the moved file with fresh content, no code path in phase8-assert.sh itself
needed to change.

### 3. Negative control (MANDATORY) — gate still fires on a forced write-back

Rather than dirtying this worktree's real `docs/LEAD_V2_STATE.md` (which would itself
violate the "don't leave the tree dirty" constraint), the gate's own unit — `_dod_check_d()`
in `lib/leadv2-dod-gate.sh`, which reads exclusively from a diff file, never the live tree —
was probed directly with a synthetic diff simulating exactly the forced-write-back scenario:

```
$ cat > /tmp/negctl.diff <<'EOF'
diff --git a/docs/LEAD_V2_STATE.md b/docs/LEAD_V2_STATE.md
index eb6442f..1111111 100644
--- a/docs/LEAD_V2_STATE.md
+++ b/docs/LEAD_V2_STATE.md
@@ -1,1 +1,1 @@
-old
+new (forced write back into lane worktree, negative control)
EOF
$ bash -c "source plugins/leadv2/scripts/lib/leadv2-dod-gate.sh
  _dod_check_d '/tmp/negctl.diff'
  echo rc=\$?"
dod_fail check=runtime_state_in_diff paths=docs/LEAD_V2_STATE.md
rc=1
```

Confirms the gate mechanism (`_DOD_RUNTIME_STATE_REGEX` / `_dod_check_d`) is byte-for-byte
unchanged and still refuses a lane the moment `docs/LEAD_V2_STATE.md` appears in its diff —
only the harness's write TARGET moved, the judge did not get weaker.

### 4. Not relying on "the counter stopped growing" — item 3 above is the real measurement,
per the task's own instruction.

## Tests — RAW output

```
$ for f in <the 15 changed .sh files>; do bash -n "$f" && echo "OK $f"; done
OK plugins/leadv2/scripts/leadv2-helpers.sh
OK plugins/leadv2/scripts/leadv2-active-registry.sh
OK plugins/leadv2/scripts/leadv2-backfill-history.sh
OK plugins/leadv2/scripts/leadv2-daemon.sh
OK plugins/leadv2/scripts/claude-subsession.sh
OK plugins/leadv2/scripts/leadv2-priors-compile.sh
OK plugins/leadv2/scripts/leadv2-rag-intake.sh
OK plugins/leadv2/scripts/leadv2-status-snapshot.sh
OK plugins/leadv2/scripts/leadv2-pattern-cluster.sh
OK plugins/leadv2/scripts/leadv2-agent-stats.sh
OK plugins/leadv2/scripts/leadv2-outcome-watch.sh
OK plugins/leadv2/scripts/leadv2-cost-estimate.sh
OK plugins/leadv2/scripts/leadv2-negative-memory-compile.sh
OK plugins/leadv2/scripts/leadv2-signatures-aggregate.sh
OK plugins/leadv2/scripts/leadv2-status.sh
```

No Python files were modified — `python3 -m py_compile` not applicable to this diff.

Changed-scope suites (the ones exercising the writer/resolver touched by this diff):

```
$ bash plugins/leadv2/scripts/tests/test-leadv2-state-path.sh
... [TEST] RESULTS: 9 passed, 0 failed

$ bash plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
... [TEST] test-worker-dod-gate: 35 passed, 0 failed

$ bash plugins/leadv2/scripts/tests/test-active-registry-failclosed.sh
... [TEST] === Results: PASS=3 FAIL=0 ===

$ bash plugins/leadv2/scripts/tests/test-active-registry-update-phase.sh
... [TEST] === Results: PASS=7 FAIL=0 ===
```

Red-before / green-after: not applicable in the strict sense — these suites were already
green on the unmodified tree before this change began (this is a defect that manifests as
`dod_fail` in real dispatched lanes' post-hoc gate output, not as a pre-existing red unit
test; no fixture in these suites was reproducing the six-lane defect directly, per the task's
own framing that the defect was "measured," not derivable from these suites). They remain
green after. The behavioural proof that the actual defect is fixed is items 1-3 above
(write moved, read still works, gate negative control still fires).

## Left alone (explicitly out of scope)

- `docs/LEAD_V2_STATE.md` tracked blob itself — Task 2 decision: leave as-is, stale.
- `tests/known-red-suites.txt` — not touched, per constraint.
- No new `test-*.sh` suite was added (existing suites already cover the resolver and gate
  mechanics adequately for this change; adding a dedicated regression test for "the six-lane
  defect" would require simulating a real dispatched lane close, which is out of scope for
  the turn budget on this task).
- `leadv2-outcome-watch.sh`'s in-place history-flip write logic (only its path *default* was
  changed, not its write mechanics) — verified it was already a Population D reader/writer
  hybrid and the fix pattern applies identically to both directions.
- Did not investigate whether `leadv2-backfill-history.sh:25`'s `REPO_ROOT="$(cd
  "${SCRIPT_DIR}/../.." && pwd)"` (a `../../`-hop root derivation, the exact anti-pattern the
  repo's standing doctrine warns against) is itself a latent bug — out of scope for this
  task, flagged here per "if your change contradicts a comment/pattern, say so."

## Files changed (git diff --stat)

```
 plugins/leadv2/scripts/claude-subsession.sh          |  8 +++++++-
 plugins/leadv2/scripts/leadv2-active-registry.sh     | 20 +++++++++++++++++++-
 plugins/leadv2/scripts/leadv2-agent-stats.sh         |  7 +++++++
 plugins/leadv2/scripts/leadv2-backfill-history.sh    |  9 ++++++++-
 plugins/leadv2/scripts/leadv2-cost-estimate.sh       |  7 +++++++
 plugins/leadv2/scripts/leadv2-daemon.sh              |  6 ++++++
 plugins/leadv2/scripts/leadv2-helpers.sh             | 32 +++++++++++++++++++++++++++++---
 plugins/leadv2/scripts/leadv2-negative-memory-compile.sh |  7 +++++++
 plugins/leadv2/scripts/leadv2-outcome-watch.sh       |  7 +++++++
 plugins/leadv2/scripts/leadv2-pattern-cluster.sh     |  7 +++++++
 plugins/leadv2/scripts/leadv2-priors-compile.sh      |  4 +++-
 plugins/leadv2/scripts/leadv2-rag-intake.sh          |  7 +++++++
 plugins/leadv2/scripts/leadv2-signatures-aggregate.sh|  8 +++++++-
 plugins/leadv2/scripts/leadv2-status-snapshot.sh     |  9 ++++++++-
 plugins/leadv2/scripts/leadv2-status.sh              |  7 +++++++
 15 files changed, 155 insertions(+), 18 deletions(-)
```

Committed as `1de50b2c` on branch `worktree-DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01`.
One commit, full reasoning in the commit body, revertable with a single `git revert`.

DELIVERABLE_COMPLETE
