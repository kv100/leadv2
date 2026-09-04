verdict: APPROVE
next_action: review_round_2

Fixed: a missing/unreadable diff file now degrades to an exhaustive round-1 review mission instead of producing no mission at all.

- Root cause: `leadv2-review-run.sh`'s WORKER-DOD-GATE-01 call ran even when the diff hash couldn't be computed; `lib/leadv2-dod-gate.sh` returned rc=2 (undetermined) for a missing diff, which review-run.sh turned into `exit 10` before ever reaching mission-write.
- Fix: scoped the DoD gate call to `REVIEW_DIFF_HASH_OK==1` only; the existing exhaustive-round-1 fallback and `.review-round.state`-skip logic already did the right thing once the gate stopped pre-empting them.
- Also fixed a pre-existing printf arg/format-spec mismatch, synced shellcheck exclusions, and relaxed one dead-reroute wiring check to match how product-close actually sources the shared lib — all pre-existing baseline red, unrelated to T12.
- All 3 target suites: 10/10 green each. Mutation control: baseline_rc=0, mutated_rc=1.

Full: full.md
