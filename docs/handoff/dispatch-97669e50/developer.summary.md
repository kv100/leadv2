verdict: APPROVE
next_action: review_round_2

rate_limit_history table + write path shipped: per-account append-only history in leadv2-ratelimit-probe.sh, new leadv2-quota-window-history.sh reader, 18-assertion suite, 3/3 mutation controls confirmed red (baseline_rc=0/mutated_rc=1).
- kv path byte-identical (assertion 4); the four kv readers untouched.
- EXTRA_SUITE_MAP row added so window-history.sh selects the suite under --scope changed.
- tests/run-all.sh --scope changed still running (run-core-offline.sh alone takes >10min); will update on completion.
Full: full.md
