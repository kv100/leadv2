verdict: APPROVE
next_action: review_round_2

Implemented a LANE_WRITES-derived, deterministic class floor that hard-refuses a `--task-class` downgrade instead of the pre-existing silent re-escalation.

- Added `leadv2_admission_writes_class`/`leadv2_admission_writes_gate` (refuse on downgrade, rc 3) to `lib/leadv2-admission-class.sh`; wired into `leadv2-dispatch-code.sh` at two points (post-admission, post-prepass).
- Founder-visible sidecar (`class-floor.yaml`) + `leadv2-broad-status.sh` alert renderer for item 3; close-time recompute functions for item 4 built and tested but NOT wired into the real close path (`leadv2-dispatch-product-close.sh` is out of `LANE_WRITES` scope).
- Census correction: brief's pointer to `leadv2-lane-class.py` was wrong (that file computes lane liveness, not task class) — not used.

Full: full.md
