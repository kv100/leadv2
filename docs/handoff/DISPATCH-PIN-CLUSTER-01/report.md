Merging is safe in all three consumer repos on this HEAD (69b7b2d): C-1 (lane-guard
sourcing fallback), H-1/H-2 (pass_unlanded restored + comments reconciled), H-3
(both-sites-use-constant counting), H-4 (scope-gate pre-image byte-identical guard)
were all already fixed and committed by the prior round-7 attempts (6686f17, 15df704)
and were reconfirmed green this round; M-1's two named-broken artifacts
(n4-scope-changed-lane-guard.log, n5-terminal-ledger-killswitch.log) are now the
verbatim output of their production commands, with n4 committed via `git add -f`
(gitignored under docs/handoff/*/*).

Evidence:
- `type -t lv2_lane_dirty` = function, zero stderr, from a consumer-topology checkout
  (verified in 6686f17's commit message; not re-probed this round, no code changed).
- test-close-chain.sh: 18 passed, 0 failed.
- test-dirty-lane-never-lands.sh: PASS (includes the new H-1 exists-rc coverage for
  a pass_unlanded-only sig8, added in 15df704).
- test-scope-gate-orchestration-dirt.sh: 1 passed(red->green) [both-sites-use-constant],
  12 green-pre-fix, 0 failed, 0 could-not-run.
- tests/run-all.sh --scope changed with lib/leadv2-lane-guard.sh touched: all six
  EXTRA_SUITE_MAP-mapped suites PASS; the sole failure is run-core-offline.sh's own
  pre-existing baseline-red set (documented, unrelated to this lane, out of
  LANE_WRITES) — see round6-red/n4-scope-changed-lane-guard.log.

Left alone, out of this round's named scope: round6-red/n2-remove-dirty-death-pin.log
is a stale one-line ("rc=1") artifact with no RED/GREEN narrative. M-1's brief named
only n4 and n5 as broken; n2's underlying control (a later landed write cannot erase
the dirty-death pin) is exercised live and passing inside
test-dirty-lane-never-lands.sh itself, so the merge-blocking risk is not present —
only the standalone artifact is thin. Flagging for a future round rather than
scope-creeping into it here.
