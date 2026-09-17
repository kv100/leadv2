# INJECT-DEDUP-ANCHOR-KIND-STRING-MISMATCH-01 — lane report

Suite: `plugins/leadv2/scripts/tests/test-inject-dedup.sh`
Boundary for every count below: 14 cases max, 300 s wall ceiling, macOS Darwin 25.6.0, worktree
lane branch `worktree-b61a1f31d0fe`, baseline commit `c2b627a7`.

## Verdict: STALE TEST (production was already correct)

The production code never had a `thread-anchor` hash kind that went missing. It had one that was
**renamed**, and the suite was never updated:

- `git show ede1aff9` ("retire open threads ledger") changed the idle-path caller from
  `_inject_dedup_gate("thread-anchor", payload.get("session_id"), thread_out, root, leadv2_dir)`
  to `_inject_dedup_gate("idle-anchor", ..., idle_out, ...)` — now at
  `plugins/leadv2/hooks/leadv2-task-anchor.sh:811`.
- The other live caller is `_inject_dedup_gate("task-anchor", session_id, full_body, root, leadv2_dir)`
  at `leadv2-task-anchor.sh:1026`.
- The reader/writer, `_inject_dedup_gate` (`leadv2-task-anchor.sh:426`), builds the hash filename
  from the caller-supplied kind: `hash_path = os.path.join(state_dir, f".inject-hash.{key}.{kind}")`
  (`:443`). There are exactly two callers and neither passes `thread-anchor`, so
  `.inject-hash.<key>.thread-anchor` is never written by any code path.

Therefore the suite's `.inject-hash.${SESSION_ID}.thread-anchor` expectation (old
`test-inject-dedup.sh:97`) was stale, not the hook. **No production defect exists** in the kind
string; nothing was changed in the hook.

## What the fix actually touched (suite only)

Investigating past the mission's single case found the rename damage was wider than line 97 —
the suite still grepped the retired marker phrase everywhere:

1. **Kind string (the mission's case):** `:97` `.inject-hash.${SESSION_ID}.thread-anchor` →
   `.idle-anchor`.
2. **Marker phrase:** the hook's marker is now `"<task-anchor>idle anchor unchanged; the block
   above still governs.</task-anchor>"` (`leadv2-task-anchor.sh:814-815`, also renamed in
   `ede1aff9`), but 13 greps in the suite still matched the pre-rename `"thread anchor
   unchanged"`. Every *negated* check (G0/G1/G4/G5/G6/R2/G5b-flip) was passing **vacuously** —
   the marker could never contain a string that no longer exists — and the positive checks
   (G2->G3, R2-setup, G5b-setup) failed because of it. All 13 renamed to `"idle anchor
   unchanged"`.
3. **G4's superseded premise:** G4 changed `open-threads.md` and expected a full re-inject.
   `build_idle_anchor` (`leadv2-task-anchor.sh:209`) no longer reads `open-threads.md` — its only
   mutable content is the nearest-due line from the project-local renderer
   `.claude/hooks/scheduled-decisions-nearest.sh` (`nearest_due_line`, `:185-206`; the doc itself
   was deleted in `ede1aff9`). G4 was green-before only because its negated grep was vacuous.
   G4 now stubs the renderer, fires (full), and asserts that changed renderer output re-injects
   fully. The dead `open-threads.md` fixture was removed and the G5b isolation comment updated.

No assertion was deleted, loosened, or `|| true`d. The vacuous negations became real negations —
strictly tighter, not wider.

## Counts

| State | Result |
|---|---|
| Before (baseline `c2b627a7`) | PASS=10 FAIL=4 (G2->G3, G5 setup, R2 setup, G5b setup) |
| After suite-only fix | **PASS=14 FAIL=0** |

The delta from 14 cases vs the census's 14 (10+4): the census counted the same suite; case count
did not change, the harness prints one `pass`/`fail` per case regardless of setup/inner split.

## Negative controls

Pre-mutation presence was asserted in both cases (`assert s.count(target)==1` printed `mutated`
only on success); the mutation was applied inside the hook function body **in the lane worktree**,
not a scratch copy, and reverted with `git checkout --` after each run.

### Control 1 — marker text (targets the phrase rename)

Mutation: `leadv2-task-anchor.sh` marker `idle anchor unchanged; ` → `idle anchor MUTATED; `.

```
[TEST] FAIL: G2->G3 failed: first=[<task-anchor>
[TEST] FAIL: R2 setup: expected a marker before compaction, got a full re-inject
[TEST] FAIL: G5b setup failed: expected marker on unchanged fire, got: <task-anchor>idle anchor MUTATED; the block above still governs.</task-anchor>
[TEST] Results: PASS=11 FAIL=3
```

Reverted → `PASS=14 FAIL=0`.

(An earlier attempt mutated the string into invalid Python; the hook crashed and the suite went
red 9/5. That red is discarded as a syntax-crash artifact, not a behavioural control — the valid
mutation above is the recorded control.)

### Control 2 — G4's content lever (targets the renderer premise)

Mutation: in `nearest_due_line`, `line = r.stdout.strip(); return line or None` →
`r.stdout.strip(); return None  # MUTATED` (renderer output ignored ⇒ idle body constant ⇒ G4's
content change is invisible).

```
[TEST] FAIL: G4 failed: got marker after content changed: <task-anchor>idle anchor unchanged; the block above still governs.</task-anchor>
[TEST] Results: PASS=13 FAIL=1
```

Reverted → `PASS=14 FAIL=0`.

## Final self-check

- `bash -n plugins/leadv2/scripts/tests/test-inject-dedup.sh` → clean (`syntax-ok`).
- Final full-suite run after revert: `PASS=14 FAIL=0` (pasted above).
- Production files touched: **none** (`git checkout --` verified; only the suite + this report are
  in the commit).

## Filed observations, not fixed here

- The `T//` doubled slash remains cosmetic as pre-measured (`leadv2-temp.sh:22`); untouched.
- `test-inject-dedup.sh:2` and `:67` still speak of "thread-anchor injection" / grep for
  `open-threads.md` in G2->G3's first-fire check (`== *"open-threads.md"* || -n "$first_out"` —
  the `-n` makes it vacuous). Comment-level only; left for a doc-lint lane.
