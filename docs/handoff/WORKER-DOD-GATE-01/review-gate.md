arms: opus
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:100,glm=author,kimi=excluded:safety,sonnet=ok:39
verified: 0/4 reason=single_arm_pool
status: fail
critical: 1
high: 3
medium: 0
low: 0
findings_source: finding_lines
findings:
- [Critical] plugins/leadv2/scripts/lib/leadv2-dod-gate.sh:277 — check (b) mutation sub-check binds diff_hash to review.diff, which is produced after the worker exits — no worker can ever satisfy it, so any brief with a paste+mutation line is…
- [High] plugins/leadv2/scripts/lib/leadv2-dod-gate.sh:455 — gate emits its cause ONLY via cat of out_md; neither call site mkdir -p's the out dir, so rc=1 with empty stdout yields review-gate.md reason=dod_unknown (the REVIEW-GATE-IS-MUTE-0…
- [High] plugins/leadv2/scripts/lib/leadv2-dod-gate.sh:44 — fix-round-1 finding 1 only half-fixed — empty-file creation, 100%% rename and mode-only change of a runtime-state path emit no ---/+++ lines and still pass check (d) rc=0 (live-p…
- [High] plugins/leadv2/scripts/leadv2-helpers.sh:77 — _LEADV2_DOD_GATE_CONTRACT_MISSION has zero consumers repo-wide, so the gate hard-refuses rounds for a contract never delivered to any worker; the comment claiming it is consumed is…
omitted: low=7
report: docs/handoff/dispatch-WORKER-DOD-GATE-01/review-opus.md
