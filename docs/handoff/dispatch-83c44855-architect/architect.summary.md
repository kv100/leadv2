verdict: APPROVE
next_action: continue

Design wires post-spawn quota detection into existing seams: the `arm == kimi` hardcode at
dispatch-code.sh:2472 becomes a generic bounded early-verdict; its `return 7` already spills to
the next arm, so D3 lands in-window for free.

- D1: adapter status/log probe + provider-agnostic classifier → existing `_record_quota_lockout`
- D2: new `lib/leadv2-quota-error-parse.py`; floor 30min, ceiling 72h
- D3: in-window rc=7 spill; out-of-window via new subcommand + close-gate advance (phase 4)

Full: architect.full.md
