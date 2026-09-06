# dispatch-1d023eee — docs-only: duplicate-caller-race 69422 1788699688

## Scope

Docs-only lane. Deliverable: verification that
`plugins/leadv2/docs/duplicate-caller-race.md` (128 lines) is an accurate
consolidation of the dedup design in `plugins/leadv2/scripts/leadv2-dispatch-code.sh`.
No product code changed.

## Verification (spot-checks against live tree)

- Knobs and defaults confirmed in script: `PENDING_TTL=${LEADV2_DISPATCH_PENDING_TTL_S:-30}`,
  `CONFIRMED_TTL=${...CONFIRMED_TTL_S:-7200}`, `OUTCOME_LEDGER`, `EVIDENCE_ATTRIBUTION`,
  `CHECKPOINT_CUTOFF` (all default 1), and the built-in `EVIDENCE_EXCLUDE_RE`
  (locks / bus-offsets / active.yaml) at `leadv2-dispatch-code.sh:725-737`.
- The `9>&-` lock-fd-not-inherited defense-in-depth idiom appears at the launcher
  call sites and is called out in the FIX PASS 4 header block (:152-164, :639-640).
- All four regression suites named by the doc exist in
  `plugins/leadv2/scripts/tests/`: test-dispatch-duplicate-caller-race.sh,
  test-leadv2-dispatch-outcome-ledger.sh, test-dispatch-ledger-partial-close.sh,
  test-dispatch-retry-dead.sh.
- Doc's own "Note on mission strings" explains this lane's mission prefix; the
  pid/epoch suffix (69422 1788699688) exists only to make the sig8 unique.

## Result

Doc verified against the live script — no drift found, no edits needed.
