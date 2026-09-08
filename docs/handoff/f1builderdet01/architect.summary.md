verdict: APPROVE
next_action: continue

False-green class detector built and proven on all 7 build-set cases (checked=17 caught=17 missed=0).

- `persona-engine/scripts/false-green-detector.py`: run-check, static-scan (6 shapes), field-census (writers vs readers, cases 11/12), vocab-census (case 2), negative-control.
- `persona-engine/tests/false-green/run-build-set.sh`: hermetic fixtures + honest controls.
- Real-tree probe flagged 6 review candidates; nothing committed, shared tree untouched.

Full: full.md
