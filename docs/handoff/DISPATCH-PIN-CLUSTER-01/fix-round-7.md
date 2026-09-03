# DISPATCH-PIN-CLUSTER-01 — round 7: merge refused, five items

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-lane-guard.sh,plugins/leadv2/scripts/lib/leadv2-admission-class.sh,plugins/leadv2/scripts/leadv2-dispatch-ledger.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh,plugins/leadv2/scripts/tests/test-close-chain.sh,plugins/leadv2/scripts/tests/test-scope-gate.sh,tests/run-all.sh,docs/handoff/DISPATCH-PIN-CLUSTER-01/

Full report: `docs/handoff/DISPATCH-PIN-CLUSTER-01/review-r6.md`. HEAD is `636e680`.

**N4, N5 and N6 are correct and were re-derived on the production path by the reviewer. Do not
touch them.** Everything below is what blocks the merge.

## [Critical] C-1 — the cluster's headline fix is inert in all three consumer repos

`lib/leadv2-lane-guard.sh` is a NEW file. `persona-engine`, `m3-market` and `respiro-ios` reach
the plugin through a per-file symlink farm, and a file that did not exist when the farm was built
has no link there. So on those repos the `source` fails, every dispatch entry point emits a source
error on stderr, and the dirty-lane pin and lane-containment check — the entire point of this
cluster — are silent no-ops. The scripts survive only because none of them sets `-e`.

The fix is already written in a sibling lane; copy its shape. `DISPATCH-CLOSE-GATE-01` at
`leadv2-dispatch-code.sh:462-467` resolves a lib next to the script, falls back to
`${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/…`, and guards the
source with `[[ -f … ]] &&`. I ran that dispatcher from `persona-engine` myself: rc=0. Apply the
same resolution to every `source` this lane adds, in every script that adds one.

Prove it the way the reviewer asked: from a consumer-topology checkout, `type -t lv2_lane_dirty`
must print `function` with **zero stderr**. Add a suite that fails when a sourced `lib/` file is
unreachable from a consumer repo — this is the second lane today to ship this exact defect, so it
needs a guard, not another one-off fix.

## [High] H-1 / H-2 — the ledger's read gate is now weaker than the merge base, and the file
documents both answers at once

`leadv2-dispatch-ledger.sh:159` dropped `pass_unlanded` from `dispatch_terminal_exists()`. That
function gates the deferred-retry reaper at `leadv2-dispatch-code.sh:1206` and `:1369`. Under the
merge base a `pass_unlanded` sig8 was reaped; under this HEAD it is not, so it falls through to
retry — while `dispatch_ledger_write_terminal:329` `exit 2`s every terminal that retry could ever
record. The lane can be re-dispatched and can never terminate in the ledger. That is the defect N3
named, moved one function over.

Restore `pass_unlanded` at `:159`, or justify the removal and cover it. Either way the two comments
must stop contradicting each other: `:150-153` calls a `pass_unlanded` row retryable, `:330-331`
calls it a durable write-once human-action state. One file, two opposite claims, and the code
implements both.

Then add the test that does not exist: no suite asserts the `exists` rc for a `pass_unlanded` row
(`grep -n exists` over `test-dirty-lane-never-lands.sh` and `test-close-chain.sh` returns nothing),
so nothing guards the arm that actually changed.

## [High] H-3 — `both-sites-use-constant` no longer counts

Restore the counting form, or replace it with a behavioural control that goes RED on the real
divergence. Make `lib/leadv2-lane-guard.sh:93` conform, or document in the file why it must not.

## [High] H-4 — the scope-gate pre-image is anchored to the wrong thing

Its "pre-image" differs from the live file by a single comment line, so the gate compares the fix
to itself. Re-anchor it to the merge base `5d1a5d7`. This matters beyond N7: I used that suite's
`13 green-pre-fix` as the C2 baseline, and a pre-image that is the post-image makes that number
meaningless.

## [Medium] M-1 — `round6-red/` is not verbatim

Re-file each artifact as the verbatim output of the production command, with the anchor match count
and the GREEN revert included. N5's control is an `eval` of a `sed`-extracted line rather than the
production path; N4's artifact does not show what the run did.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no control mutating a scratch copy; no `git show HEAD:` pre-image.
- An artifact must assert its own outcome. A `roundN-red/` file recording a passing run is a hard
  failure of the round.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`.
- Commit before you stop.

## Done means

`type -t lv2_lane_dirty` printing `function` with zero stderr from a consumer-topology checkout,
plus a suite that fails when a sourced lib is unreachable there; `pass_unlanded` restored at `:159`
(or covered and justified) with a test asserting its `exists` rc and the two comments reconciled;
`both-sites-use-constant` counting again; the scope-gate pre-image anchored to `5d1a5d7`; and
`round6-red/` re-filed as verbatim production output. Then say in `report.md`, in one line, whether
merging is now safe in all three consumer repos and on what evidence.

## Round-7 note (added by the lead after the first attempt stopped early)

The first worker on this round produced no code change and stopped at the close gate with
`selfcheck_failed: falsification:test-lane-placement-pin.sh:test_failed`. A suite that is red before
your change is the work, not a reason to stop. Diagnose that failure, fix it as part of C-1, and
carry on with the rest of the round.

## Round-7 continuation (lead, second attempt also stopped after C-1)

C-1 is DONE and verified — keep it. Sourcing `lib/leadv2-lane-guard.sh` from a consumer checkout
now yields `type -t lv2_lane_dirty` = `function`, close-chain is 18/0, and I committed that work as
`6686f17` after the worker went quiet with it uncommitted.

Everything else in this brief is still outstanding: H-1/H-2 (`pass_unlanded` at
`leadv2-dispatch-ledger.sh:159`, plus the two contradicting comments and the missing test on the
`exists` rc), H-3 (`both-sites-use-constant` counting again), H-4 (re-anchor the scope-gate
pre-image to `5d1a5d7`), and M-1 (verbatim `round6-red/` artifacts, committed with `git add -f`).

Start with H-1: as it stands the ledger's read gate is weaker than the merge base, which is the
remaining merge blocker.
