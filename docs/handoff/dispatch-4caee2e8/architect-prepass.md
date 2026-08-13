# ARM-PRODUCES-NOTHING-01 — fix round 1: architect design

Lane worktree: `.claude/worktrees/621328a0` (branch `worktree-621328a0`). Resume, do not restart.
All line numbers below are the CURRENT worktree copy of
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` (1661 lines).

---

## 1. Root cause — measured, not theorised

**It is none of the three candidates in the mission. It is nesting.**

`pc_scope_diff() {` opens at **line 843** and its closing `}` is at **line 1216**.
Everything between is the *body* of `pc_scope_diff`, including — verified by a column-0
brace/opener balance scan over 843..1216:

| line | definition | pre-existing? |
|---|---|---|
| 880 | `_pc_realpath()` | yes |
| 889 | `_pc_git_diff()` | yes |
| 910 | `_pc_diff_base()` | yes |
| 932 | `_pc_lane_dirty()` | yes |
| **946** | **`_pc_stat_mtime()`** | **new (this lane)** |
| **958** | **`_pc_next_arm_in_chain()`** | **new** |
| **991** | **`pc_silent_arm_probe()`** | **new** |
| **1027** | **`_pc_arm_advance()`** | **new** |
| 1072 | `_pc_last_diff_base()` | yes |
| 1077 | `_pc_repo_diff()` | yes |

Line 879 — `source "${SCRIPT_DIR}/lib/leadv2-e2e-root.sh"` — is nested in the same body.

A nested function definition is a *runtime statement*: the inner names come into existence
only when the outer function is **invoked**. `pc_scope_diff` is invoked at **line 1277**.
The new probe is called at **line 1267** — ten lines earlier, in the same shell, top level.
Hence, verbatim:

```
leadv2-dispatch-product-close.sh: line 1267: pc_silent_arm_probe: command not found
```

This also confirms the mission's warning: on the rc0 branch (1267–1275) the script never
reaches 1277, so `_pc_arm_advance` (1272) would be `command not found` too, and
`_pc_stat_mtime` / `_pc_next_arm_in_chain` are undefined for the whole pre-1277 window.
`bash -n` is clean because nothing here is a parse error.

**Standing landmine (document, do not silently rely on):** every helper the file defines
between 843 and 1216 — including the `source` of `lib/leadv2-e2e-root.sh` that provides
`_lv2_e2e_resolve_root`, called at top level on line 1299 — is only available *after*
`pc_scope_diff` has run once. Any future top-level call placed before 1277 that touches one
of those names fails identically. The pre-existing code happens to be correct only because
its call sites all sit after 1277.

## 2. Second, independent defect — why Case 2 blocks a lane with real work

Case 2 is **not** collateral from the probe. It is a real pre-existing production bug that
the new suite exposed first.

- Case 2 runs with `WRITES_CSV=""` → `pc_scope_diff` takes the else branch at **1160**.
- **1162**: `repo_diff="$(_pc_repo_diff "${diff_root}")"` — called with **no pathspec**.
- `_pc_repo_diff` (1077) shifts off the repo and forwards `"$@"` (now empty) to
  `_pc_git_diff`, which runs `git add -N --` (no paths → no-op) then `git diff HEAD --`
  (no pathspec → **tracked changes only**).
- Case 2's lane work is a new **untracked** file (`$LANE/newfile.txt`). The diff comes back
  empty → **1166** sets `blocked_reason=unscopable_diff` → **1190** sees the lane dirty →
  `refused / unscoped_lane_work`, evidence `lane_root=lane dirty=1`. Exactly the observed row.

Verified in isolation: with the pathspec `.` present, the same
`GIT_INDEX_FILE=<copy> git add -N -- . && git diff HEAD -- . ':(exclude)docs/leadv2'
':(exclude)docs/handoff'` sequence emits the `new file mode 100644 newfile.txt` hunk. Without
it, nothing. `_pc_repo_diff`'s own header comment claims "tracked + untracked + deletions" —
the no-pathspec call site breaks that contract.

Production impact independent of this lane: any single-repo lane with no LANE_WRITES whose
deliverable is new files never `git add`ed is classified `refused/unscoped_lane_work` today.

## 3. Changes — scoped

### Change A (required) — hoist the four new helpers to true top level
Move, verbatim and with their comment blocks, lines **946–1064** (`_pc_stat_mtime`,
`_pc_next_arm_in_chain`, `pc_silent_arm_probe` incl. its two `_PC_SILENT_*` global
initialisers at 989–990, `_pc_arm_advance`) out of `pc_scope_diff`'s body to top level
**above line 843** (i.e. before `pc_scope_diff() {`).

Constraints on the move:
- Body text unchanged. Do not weaken the three rc0 conditions (no/zero-assistant stream AND
  not-fresh per `LEADV2_PC_SILENT_GROWTH_S` default 60 AND lane worktree clean), and keep
  every fail-OPEN return.
- Before moving, audit `_pc_arm_advance` (1027–1064) for calls to names defined **only**
  inside `pc_scope_diff` (`_pc_realpath`, `_pc_git_diff`, `_pc_diff_base`, `_pc_lane_dirty`,
  `_pc_last_diff_base`, `_pc_repo_diff`, and anything from `lib/leadv2-e2e-root.sh`). If it
  uses one, that dependency must be hoisted too, or `_pc_arm_advance` will fail the moment
  the probe returns rc0 — the mission's stated trap.
- `pc_silent_arm_probe` reads `_pc_lane_dirty` for condition (3). `_pc_lane_dirty` (932–940)
  is currently nested. **It must be hoisted with them** — hoisting the probe alone leaves
  condition (3) calling an undefined function inside a `$( )`/`if`, which silently degrades.
  Hoist 932–940 as well; it has no dependencies of its own beyond `git`.
- Do **not** move the call site at 1267 after `pc_scope_diff` — the probe's whole point is to
  classify before scoping, and Case 1's "no e2e_gate journal line" assertion locks that order.

### Change B (required) — give the whole-repo diff a pathspec
At line **1162**, pass an explicit pathspec so `add -N` and `diff` see untracked paths:
`repo_diff="$(_pc_repo_diff "${diff_root}" .)"`.
This is the minimum change that restores `_pc_repo_diff`'s documented contract. Do not touch
the `writes[]` branch (1103–1158) — that path already passes real paths and is covered by
`test-lane-diff-single-repo.sh`, which must stay green.

### Change C (required) — bash-3.2 rule compliance in the new suite
`tests/test-dispatch-silent-arm.sh` uses herestrings (`<<<`) at lines 80 and 120 (and any
sibling occurrences). The mission's rule list forbids `<<<`. Replace each with
`printf '%s\n' "$row" | grep -q ...`. (`<<<` does run on bash 3.2; this is rule compliance,
not a portability break — fix it anyway so the suite matches the stated constraint.)

### Explicit non-goals
- No fixture weakening. Case 2 keeps its untracked-file lane; it goes green because Change B
  makes the diff honest, not because the assertion was relaxed.
- No de-nesting of the pre-existing helpers (`_pc_git_diff`, `_pc_diff_base`,
  `_pc_repo_diff`, `_pc_realpath`, `_pc_last_diff_base`, the `source` on 879) beyond
  `_pc_lane_dirty`, which Change A needs. Their call sites are all post-1277 today.
- No change to `pc_scope_diff`'s verdict taxonomy, exit codes, `review-gate.md` wording, or
  ledger cause strings on any path other than the untracked-only whole-repo diff.
- No commit, no push, no merge, no `run-core-offline.sh`.
- `.env` reads only.

## 4. Files

| file | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | Change A (hoist 932–940 + 946–1064 above 843), Change B (line 1162 pathspec) |
| `plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` | Change C (`<<<` → `printf \| grep`) |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | already carries this lane's `advance-arm` / `LEADV2_DISPATCH_CANDIDATE_ARMS` / `lane-mission.md` work; touch only if the `_pc_arm_advance` audit above forces a contract change |

## 5. Risks

| risk | mitigation |
|---|---|
| Hoisting drags a helper that reads a variable `pc_scope_diff` sets (`diff_root`, `_pc_base_used`, `_PC_LAST_BASE_FILE`) | These are globals, not `local`s, but they are *unset* before 1277. Grep the hoisted bodies for them; the probe must depend only on `HANDOFF`, `_lane_root`, `LEADV2_PC_SILENT_GROWTH_S`. |
| Change B alters an already-shipped classification path | `test-lane-diff-single-repo.sh` is the regression lock — must be pasted green. Change B can only turn `unscopable_diff` into a real diff; it never manufactures a block. |
| Symlinked into three repos; a regression breaks dispatch everywhere | Both suites green + `bash -n` and `/bin/bash -n` on both scripts before any handback. |
| The same nesting trap recurs | Add a one-line comment above `pc_scope_diff() {` stating that its body defines helpers unavailable before its first invocation. |
| Concurrent-access surface | None introduced; the probe is read-only on `developer.stream.jsonl` and `git status` on the lane. |

## 6. Verification the implementer must paste in full
1. `bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` — all cases pass, zero failures.
2. `bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` — still green.
3. `bash -n` and `/bin/bash -n` on both scripts.
Do NOT run `run-core-offline.sh`.

## 7. acceptance

```yaml
acceptance:
  authored_at: 2026-08-04T16:45:00Z
  items:
    - surface: rendered_line
      observable: "The final line printed by `bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` reads `[TEST] 10 passed, 0 failed` (or the suite's full count with 0 failed), and no line anywhere in its output contains `command not found`."
    - surface: rendered_line
      observable: "In that same output, the Case 2 line reads `[TEST] PASS: Case 2: ledger row lands as before (regression lock, both gates off)` instead of the current `FAIL: Case 2: expected landed`."
    - surface: rendered_line
      observable: "The final line printed by `bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` still reports 0 failed."
    - surface: file_artifact
      observable: "In `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, the definitions of pc_silent_arm_probe, _pc_arm_advance, _pc_stat_mtime, _pc_next_arm_in_chain and _pc_lane_dirty all appear at column 0 ABOVE the line `pc_scope_diff() {`, and no `}` at column 0 sits between them and that line."
    - surface: log_line
      observable: "For a silent arm, the close gate's journal shows a review_gate decision line whose reason is arm_produced_nothing and terminal is no_work, with no e2e_gate line preceding it."
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh

DELIVERABLE_COMPLETE
