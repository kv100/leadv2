verdict: APPROVE
next_action: review_round_2

Fixed `leadv2_active_mark_finished` to actually release a lane's writeset/lane-cap claim on finish, verified rc=0 by re-read.

- `stale: true` reused (existing skip-convention) instead of removing the row; row stays readable for lane-heartbeat's terminal status.
- rc=9 on a lost write (verified via post-write re-read); rc=4 not-registered now checked before rc=8 recovered-refusal.
- New suite `test-mark-finished-releases-writeset.sh`: 4/4 green; negative control (scratch-only mutation) goes red.

Full: docs/handoff/PLUGIN-MARK-FINISHED-NO-RELEASE-01/report.md
