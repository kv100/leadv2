verdict: REVISE
next_action: review_round_2

Fixed a real false-miss: `leadv2_active_register`'s refresh path re-printed a foreign (fanout "f-...") session_id, which the caller's strict "s-..." regex never matched — a genuine write reported as `active_register_miss ... rc=0`.

- Restamped session_id on every refresh + added a bash-level guard that returns rc=7 with a stderr diagnostic on any output-shape mismatch, instead of silent 0.
- New suite `test-active-register-miss.sh`: mutation control shows baseline_rc=0 → mutated_rc=7 (exact pre-fix shape reproduced) → restored_rc=0. 10/10 clean runs.
- dispatch-code.sh fix (off-limits, not landed) documented in full.md.

Full: full.md
