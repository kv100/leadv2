verdict: APPROVE
next_action: review_round_2

Added `# run-all-triggers:` headers to the 12 suite files covering all 16 dark script→suite mappings; proven selected via `--scope changed` with a non-confounded negative control.

- 16/16 mappings registered (one source-script name in the mission was wrong — `leadv2-single-lead-beat.sh` doesn't exist; used real `leadv2-single-lead-beat-loop.sh`).
- Sweep: 267/387 suites repo-wide carry NO header at all (out of scope, reported only).
- Ran the 16 suites: green=7 red=5, all 5 pre-existing content failures unrelated to the header change — not fixed, not allow-listed.

Full: full.md
