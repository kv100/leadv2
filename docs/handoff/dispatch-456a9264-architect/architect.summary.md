verdict: APPROVE
next_action: continue

Design closes the lost-increment race inside `_review_state_write`/`_review_roundcap_read` via a guarded-sourced `lv2_lock_wait`; fixes 4 (not 2) hardcoded escalation paths; adds the rc=8 arm; drops the dead fallback; specs one deterministic lock test.

- "One lock around read+increment+write" is not literal: gate read (:1001) and increment (:1141/:1470) sit ~140 lines apart. Locked the two functions instead.
- Residual: gate TOCTOU stays — two concurrent lanes can still pay `max + 1` rounds.
- Engine is self-contained (:11), so the lock lib needs a guarded source + no-op stub.

Full: architect.full.md
