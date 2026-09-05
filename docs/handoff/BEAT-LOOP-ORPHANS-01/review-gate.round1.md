arms: opus
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:lockout,glm=author,kimi=excluded:safety,sonnet=ok:20
verified: 0/5 reason=single_arm_pool
status: fail
critical: 0
high: 5
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh:170 — owner-check call is unguarded while the lib is sourced conditionally and every sibling call site uses `command -v` — a missing lib makes rc 127 kill the founder beat on iteration…
- [High] plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh:1 — transcript rule `*/docs/handoff/*|*-runs/*` never matches a real worker transcript (`~/.claude/projects/<munged>/<sid>.jsonl`), so headless workers fall through to `lead` — not `…
- [High] plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh:1 — case E7 asserts `~/.claude/projects/-Users-x/abc.jsonl -> lead`, enshrining the exact misclassification that produced the 53 measured orphans as expected behaviour
- [High] plugins/leadv2/scripts/leadv2-task-judge.sh:214 — census — headless `claude -p` spawners outside the four gated launchers (task-judge:214, session-runner:439) set neither LEADV2_WORKER_ARM nor LEADV2_SUBSESSION_ROLE, so mechanis…
- [High] docs/handoff/BEAT-LOOP-ORPHANS-01/build-attempt-1.diff:1 — claims-without-evidence — no report.md exists; the brief's mandated proof (suite green, NC1/NC2 pasted red, a real freepool run with clean `pgrep -f single-lead-beat-loop`) is en…
omitted: low=3
report: docs/handoff/dispatch-BEAT-LOOP-ORPHANS-01/review-opus.md
