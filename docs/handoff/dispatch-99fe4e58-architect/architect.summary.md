verdict: REVISE
next_action: continue

Both reds are one cause — the suites are non-hermetic; ambient `LEADV2_LANE_START_SHA` / `LEADV2_DISPATCH_LANE_WRITES` leak into the fixtures. Both pass in a clean shell.

- Reproduced each red by exporting one var; evidence matches selfcheck byte-for-byte.
- Probe must emit `unknown`, not `0`, when no base resolves — fail open.
- Round-1's "`_pc_diff_base` is nested" comment is false: top level at :1735.

Full: architect.full.md
