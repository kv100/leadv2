verdict: APPROVE
next_action: review_round_2

Fixed: `source leadv2-active-registry.sh` leaked its `set -euo pipefail` into leadv2-broad-status.sh, so errexit killed the beat via the EXIT trap the instant the render step failed — before the existing degraded-artifact/ready-line fallback ever ran.

- Added `set +e` right after the source (line ~69); also stamped the render-failure LOG_FILE line with `$BEAT_AT` not `$(_now_iso)`.
- test-beat-stamp-agreement.sh: 5p/1f → 6p/0f. RED/GREEN + both round-1/round-2 mutation controls proven.
- test-broad-status-duty.sh confirmed pre-existing red on HEAD (23p/15f); fix closes 5 T9b assertions, zero regressions (28p/10f after — remainder is unrelated live-loop timing/doc-wording tests).

Full: full.md
