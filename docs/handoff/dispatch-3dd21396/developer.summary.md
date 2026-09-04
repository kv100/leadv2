verdict: NEEDS-INFO
next_action: continue

Root cause found, no fix applied (budget). `--scope changed` never narrowed core-offline
(always-on by design, unchanged today). Real cause: host load avg ~49 today (dozens of
concurrent lanes) blows up the 12-suite strictly-serial tail run after the 4 parallel
shards. Live-reproduced: 2 of 12 serial suites already >60s each right now.
Full: full.md
