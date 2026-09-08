verdict: APPROVE
next_action: review_round_2

Fixed the last red assertion by re-keying a collapsed duplicate's surviving table to its resolved physical path.

- `leadv2-codex-config-prune.sh`: winner was previously the raw path spelling from the file, never rewritten to `realpath`, so on hosts where the raw path differs from its resolution (e.g. macOS /tmp→/private/tmp), the wrong spelling survived.
- Added `rewrite_header()`, applied only when a duplicate actually collapsed into a winner whose spelling ≠ resolved path — the sibling "conflicting live policies untouched" byte-identity assertion still passes.
- All 16 assertions in `test-codex-config-prune.sh` pass; negative control (dropping the resolution) reddened `count() == 1` as required, then was reverted.

Full: full.md
