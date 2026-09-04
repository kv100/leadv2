verdict: APPROVE
next_action: deploy

# developer.summary.md

`tests/test-status-surface-fast-names.sh` is green on Linux (ubuntu:24.04) and macOS; fix already committed at a5de5862, independently re-verified this session.

- Root cause: BSD-first `stat -f %m ... || echo 0` in `leadv2-status-surface.5s.sh` (8th instance of the TWELVE-LINUX-ONLY-SUITES-01 pattern); `stat -f` "succeeds" as a filesystem dump on GNU, poisoning `PAYLOAD_AGE`.
- Fix: new `_stat_mtime()` OS-switch helper, both call sites updated.
- Negative control reproduced independently in a fresh ubuntu:24.04 container (isolated snapshot, not the live worktree): mutant → 9 passed/3 failed, byte-identical to CI's failure signature; revert → 12 passed/0 failed.

Full: developer.full.md
