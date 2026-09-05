arms: opus
fanout: 1/1 degraded=false launched=1 pool_ok=3 source=pool reason=none excluded=codex=author,glm=ok:81,kimi=excluded:safety,sonnet=ok:12
verified: 0/5 reason=single_arm_pool
status: fail
critical: 1
high: 4
medium: 6
low: 3
reviewer_says: do_not_merge
findings_source: finding_lines
findings:
- [Critical] plugins/leadv2/scripts/leadv2-dispatch-code.sh:6024 — _deliver_plan_into_lane is called before the ensure block assigns WORK_ROOT, so it no-ops on every ensure-created lane and the feature never fires
- [High] plugins/leadv2/scripts/lib/leadv2-lane-guard.sh:6 — _PC_BOOTSTRAP_PREFIX_RE double-escaped ('\\\\.claude') never matches, so the ledger grades bootstrap-symlink-only lanes dirty and downgrades landed to pass_unlanded/refused
- [High] plugins/leadv2/scripts/lib/leadv2-lane-guard.sh:61 — lv2_lane_containment_violation attributes any new main-checkout path to this lane; concurrent lanes, the lead session and hooks write there (.claude/settings.json, docs/tasks.yaml…
- [High] plugins/leadv2/scripts/lib/leadv2-admission-class.sh:333 — task-class.yaml is written last-writer-wins, so a later Light dispatch of the same founder task overwrites a Heavy record and the \"floor\" is not monotonic
- [High] plugins/leadv2/scripts/leadv2-dispatch-code.sh:26 — 
omitted: low=3
report: docs/handoff/dispatch-DISPATCH-PIN-CLUSTER-01/review-opus.md
