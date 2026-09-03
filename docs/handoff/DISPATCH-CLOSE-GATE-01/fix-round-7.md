# DISPATCH-CLOSE-GATE-01 — round 7: the merge made your own guard suite RED

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-lib-source-guarded.sh,docs/handoff/DISPATCH-CLOSE-GATE-01/

**Round 6 passed review (`review-r6.md`, 8/9) and is merged to `~/Projects/leadv2` main as
`baae58e`. Keep all of it — nothing in round 6 is under question.** First: rebase this lane onto
`main` (same filesystem, no fetch needed: `git rebase main`), because the two findings below only
exist post-merge.

On merged main your structural guard suite is **1 pass / 3 fail**, and it is right to be red.

## [Critical] a real unguarded-fallback site arrived from another lane

`plugins/leadv2/scripts/leadv2-broad-status.sh:107-109` sources
`${SCRIPT_DIR}/lib/leadv2-alarm-dedupe.sh` with an `[[ -f ]]` guard but **no canonical
fallback**. That is the exact half-fix that killed three lanes today: in a consumer repo
(`persona-engine`, `m3-market`, `respiro-ios`) the symlink farm has no entry for a NEW `lib/`
file, so the `[[ -f ]]` is false and the feature silently degrades — here, the broad-status
transition dedupe stops deduping and every poll emits a beat.

The comment at `:104-106` calls pass-through "R2, intentional". Decide and say which:

- if pass-through is genuinely intended, the site still needs the canonical fallback first
  (`${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}/plugins/leadv2/scripts/lib/...`) so
  pass-through only happens when the lib is absent from BOTH roots, or
- if it is not intended, fix it the same way as the three dispatch-code sites.

Either way the file must stop being a violation of your own suite. Prove it: run the suite,
paste it, then strip the fallback again and show that site named RED.

## [High] the control asserts on the first violation, not on its own file

The PORTABLE_LOCK control failed with
`stripped fallback NOT detected as plugins/leadv2/scripts/leadv2-dispatch-code.sh:460, got:
plugins/leadv2/scripts/leadv2-broad-status.sh:109`. The control compares against the FIRST
reported violation, so any unrelated pre-existing violation anywhere earlier in sort order breaks
all three controls at once — and a control a stranger's commit can flip is not a control.

Make each control search the full violation list for its own `file:line` and assert presence,
not position. Then re-run all three strip-and-restore controls and paste each RED naming its own
file.

## [Medium] the round-4 artifact left over from review-r6

`review-r6.md` item 5: the `round4-red` artifacts were honestly retitled, but the
`--scope changed` rerun-to-completion was never filed. File it now with its exit code, or state
in `report.md` that it cannot complete and why (the `/tmp/leadv2-core-offline.lock` note from the
HOOK-OUTPUT-CAP lane may apply).

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file,
  RED, revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

`test-lib-source-guarded.sh` green on top of merged main with all three controls proven RED
individually, and `leadv2-broad-status.sh` either fixed or explicitly justified with the
canonical fallback in place.
