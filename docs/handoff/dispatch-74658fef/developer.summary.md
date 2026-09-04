verdict: APPROVE
next_action: review_round_2

run-core-offline.sh now takes a flock (kills cross-run false reds), exposes
LEADV2_SUITE_SHARDS parallel sharding, and verifies per-suite TMPDIR
isolation. 3 commits, red-first each.
- item 1: flock + kill-switch + bounded wait
- item 2: TMPDIR isolation already existed; added override test hook + verify test
- item 3: round-robin shards, shards=1 byte-for-byte parity, shards_dump for testing
- item 4: sleep audit found no trivial-to-replace offenders (see full.md)
Full: developer.full.md
