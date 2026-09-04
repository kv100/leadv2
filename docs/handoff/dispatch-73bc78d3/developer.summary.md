verdict: APPROVE-candidate
next_action: review_round_2

Round 11: added a real hermeticity assertion + chained EXIT/INT/TERM repair trap on the real `docs/leadv2/questions` inode in test-status-surface.sh, and fixed a second `trap ... EXIT` that was silently clobbering the first.

- Standalone runs never actually touched the real path (already env-sandboxed via NEW_SB), but there was no proof and no repair path — now both exist.
- RED control: forced a mid-run retarget → assertion FAILED, trap still repaired the real symlink → reverted → GREEN, 92/0.
- `tests/run-all.sh` already reconciled with main — no change needed.

Full: full.md
