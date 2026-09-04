verdict: APPROVE
next_action: continue

Built the worker->lead durable inbox + notifier and wired it at the events the census actually supports; the "finished/died/control-failed/silent/round-cap" call sites live outside LANE_WRITES scope (census correction, not implemented around).

- New: `leadv2-inbox.sh` (append/drain, flock-atomic, placed at the shared base ABOVE the per-repo control-plane root so persona-engine/m3-market/respiro-ios/leadv2 share one inbox), `leadv2-notify-lead.sh` (always exits 0), `test-lead-worker-channel.sh` (12/12 green, mutation-kill proven RED->revert->GREEN).
- Wired: question-asked (ask-lead.sh, leadv2-ask.sh), admission-refusal `lead_session_lane_cap` (leadv2-dispatch-code.sh), broad-status beat now drains + renders unread rows.
- NOT wired (out of LANE_WRITES scope, named plainly): lane finished/died (`dispatch_ledger_write_terminal` lives entirely in leadv2-dispatch-ledger.sh, never called from leadv2-dispatch-code.sh), control-failed (leadv2-phase8-assert.sh), silent-past-threshold (leadv2-lane-liveness.sh), review-round-cap/gate-refusal (workflow layer, not .sh). Also NOT wired: 6 other `dispatch_refused` reasons in leadv2-dispatch-code.sh beyond `lead_session_lane_cap` (writeset_conflict x2, writeset_unknown x2, not_shape_eligible, diagnostic_mission_missing_evidence, router_v2_unavailable, duplicate_task_signature x2) — scope decision, see full.md.
- Lead->worker: verified via ListAgents myself (this session IS addressable as `lead-worker-channel-01-70`), wired nothing new per the brief's own correction (SendMessage success≠delivery, human-approval-gated).
- Incident: a test bug leaked one dummy row into the REAL `~/.claude/leadv2-state/lead-inbox.jsonl`; fixed the test; couldn't delete the stray row myself (harness blocked it as sensitive) — harmless, safe to `rm` or ignore.

Full: full.md
