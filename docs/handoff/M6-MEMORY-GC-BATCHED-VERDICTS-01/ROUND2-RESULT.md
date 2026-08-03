# M-6 round 2 result

Overall: **BLOCKED** — the mechanism was replaced and verified, but the final guarded live batch found no entry that can honestly be archived. Haiku proposed one completed-project entry as `spent`; code changed it to `live` because the source itself still contains explicit unresolved tails. The requested non-empty spent set therefore does not exist under the acceptance rules. The live index is restored byte-for-byte and no state marker remains.

## Acceptance status

1. **BLOCKED** — the live dry-run emitted all 142 per-entry verdicts and projected 20,890 bytes / 150 lines, under the derived cap, but its effective spent set is empty. The only model-spent proposal was rejected by the unresolved-work guard. Forcing a non-empty set would archive a record that still changes future work.
2. **BLOCKED** — without a valid non-empty spent set there is no final apply archive to accept. A preliminary real apply exposed contradictory model rationales and was immediately audited and restored; it is recorded below as rejected evidence, not a green result.
3. **BLOCKED** — the valid-apply precondition from item 2 was not met. The no-op state path itself was exercised on the preliminary live run and in the focused test, but it is not counted as acceptance after an invalid semantic archive.
4. **PASS** — restore on the real live directory reproduced the independent pre-GC index exactly: both SHA-256 values are `85e870ca84c0118063eee7273ea000329aed320c94dda6a885493f8bcfc7afe2`, and `diff_exit_code=0`.
5. **PASS** — installed Claude Code 2.1.220 embeds a `MEMORY.md` loader limit of 25,000 bytes and 200 lines. The live index measured 20,890 bytes / 150 lines = 139.267 bytes/line, so the line equivalent is `min(200, floor(25000 / 139.267)) = 179`. Bytes are the authoritative cap.

## Changed paths

- `plugins/leadv2/prompts/memory-gc-verdict.md`
- `plugins/leadv2/scripts/leadv2-memory-gc.sh`
- `plugins/leadv2/scripts/leadv2-memory-index-gc.py`
- `plugins/leadv2/skills/leadv2-memory-gc/SKILL.md`
- `plugins/leadv2/tests/test-memory-index-gc.sh`
- `ROUND2-RESULT.md`

Implementation commit: `b0afa996e002f122cfaa55ee6d049189a6436628`

Unrelated pre-existing worktree paths were not staged or changed by this task.

## Raw final live dry-run output

Command:

```text
LEADV2_MEMGC_TIMEOUT=300 bash plugins/leadv2/scripts/leadv2-memory-gc.sh \
  --memory-dir /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory \
  --project-root /Users/kostiantyn.vlasenko/Projects/persona-engine \
  --model haiku
echo "exit_code=$?"
sed -n '1,300p' /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/memory-gc-report.md
```

Output:

```text
memory-index-gc: dry-run report /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/memory-gc-report.md
exit_code=0
# Memory index GC plan

llm: available (model=haiku)
read-cost cap source: embedded MEMORY.md loader config in /Users/kostiantyn.vlasenko/.local/share/claude/versions/2.1.220
configured maximum index read cost: 25000 bytes; loader line limit: 200
measured current index read cost: 20890 bytes / 150 lines = 139.267 bytes/line
derived line cap: min(200, floor(25000 / 139.267)) = 179
projected post-GC index: 20890 bytes / 150 lines (at or under configured read cap: yes)
spent entries: 0
spent set: (empty)

## Per-entry verdicts
- e0001 user_profile: live [immune=user_type] — User profile for a senior engineer; always relevant to session communication style and depth expectations
- e0002 feedback_priority_ladder_autonomous: live [immune=unresolved_work] — Standing founder directive on autonomous task-picking priority ladder (protected_by_code)
- e0003 feedback_claude_codex_only_routing: live [immune=standing] — Standing founder override: Claude+Codex only routing, no GLM/Kimi (protected_by_code)
- e0004 feedback_no_glm_workaround_above_80: live — Standing rule to avoid GLM workarounds above 80% quota; fall back to Sonnet clean
- e0005 feedback_talk_to_founder_plain_russian: live — Standing communication rule with founder: Russian, plain product language, never code identifiers
- e0006 feedback_decisions_via_askuserquestion_variants: live [immune=unresolved_work] — Standing rule to surface decisions via AskUserQuestion with concrete variants (protected_by_code)
- e0007 feedback_verify_text_claims_against_engine_labels: live [immune=standing,multi_pointer_index_line,unresolved_work] — Standing rule to verify text-classification against engine labels before shipping fix (protected_by_code)
- e0008 feedback_separate_fix_blast_radius: live — Standing rule: label fix scope (repo/global/plugin) before executing; get explicit confirmation
- e0009 feedback_topic_form_diversity_is_priority_1: live [immune=unresolved_work] — Standing #1 founder priority: posts/comments on diverse topics, form, criticism, redraft; zero repetition (protected_by_code)
- e0010 feedback_llm_budget_abundant_use_more: live — GLM quota abundant (~1% used); use 10x more for persona quality; cost not a constraint
- e0011 feedback_quality_via_prompt_not_provider_glm_workhorse: live — Quality depends on prompt/system not provider tier; tune on GLM the intended workhorse
- e0012 feedback_offload_more_codex: live [immune=multi_pointer_index_line] — Offload work to Codex to cut Opus burn; lead runs Opus by choice (protected_by_code)
- e0013 feedback_codex_tier_default_is_standard: live [immune=standing] — Codex standard tier default; top tier only for adversarial review of risky diff with named justification (protected_by_code)
- e0014 feedback_workflow_agent_model_explicit: live — Workflow agent() calls must set model explicitly or silently inherit lead Opus and burn quota
- e0015 feedback_lead_bypasses_the_router: live [immune=unresolved_work] — Router works; lead must dispatch code via leadv2-dispatch-code.sh not direct Agent() spawn (protected_by_code)
- e0016 feedback_audit_discovery_is_haiku: live — Repo audits and cruft-classification = discovery/haiku-tier work, not sonnet
- e0017 feedback_watchdog_every_bg_spawn: live — Pair every critical bg spawn with Monitor watching deliverable-file mtime (protected_by_code)
- e0018 feedback_our_own_logs_lie_zero_when_stderr_is_swallowed: live — Logs lie zero when stderr swallowed via 2>/dev/null; measure at emitter not journald (protected_by_code)
- e0019 feedback_diagnosis_read_error_first: live [immune=multi_pointer_index_line] — Diagnosis: read component error log + walk pipeline to first zero before theorizing (protected_by_code)
- e0020 feedback_spacing_model_derived_not_4h: live [immune=unresolved_work] — Spacing derived from working-hours/volume not fixed 4h; publish_time=executed_at not created_at (protected_by_code)
- e0021 feedback_derive_alert_thresholds_from_config: live — Alert threshold must derive from engine config (spacing floor + buffer), never picked round number
- e0022 feedback_count_by_ny_working_day: live — Count posts/comments PER NY WORKING DAY not rolling 24h; filter by confirmed_at not created_at (protected_by_code)
- e0023 feedback_flag_on_but_artifact_missing: live [immune=standing,multi_pointer_index_line,unresolved_work] — Flag=1 doesn't mean feature works; verify enabling artifact exists before fixing (protected_by_code)
- e0024 feedback_status_field_is_intent_not_fact: live [immune=standing,multi_pointer_index_line] — Status field is intent at spawn, not fact; verify liveness by log mtime or kill -0 (protected_by_code)
- e0025 feedback_lead_runs_e2e_itself: live [immune=unresolved_work] — Lead must E2E test every shipped feature itself before accepting subagent green (protected_by_code)
- e0026 feedback_deploy_is_autonomous_never_wait: live [immune=standing,multi_pointer_index_line] — Engine deploy is lead's autonomous decision never gated on founder (protected_by_code)
- e0027 reference_tasks_yaml_intent_keyed_not_title: live [immune=standing,unresolved_work] — tasks.yaml rows key on `intent` not `title`; never prune by title field (protected_by_code)
- e0028 feedback_verify_persona_tables_by_slug: live — Verify persona tables by SLUG not UUID before declaring producer dead
- e0029 feedback_verify_publish_by_mediaid_not_status: live [immune=unresolved_work] — Respiro publish success = context.media_id present AND status lifecycle; status=confirmed alone is false-zero (protected_by_code)
- e0030 feedback_enumerate_before_filtering: live [immune=unresolved_work] — Enumerate distinct values live before filtering; narrow filter produces confident wrong answer (protected_by_code)
- e0031 feedback_opus_subagents_allowed_important: live — Opus subagents ARE allowed for important work (protected_by_code)
- e0032 feedback_quality_invariants_not_just_flow: live — Repeated-block cluster = generation disease first hypothesis, not just gate saturation (protected_by_code)
- e0033 feedback_persona_not_working_check_runmode_first: live — Persona 'not working'? Check RUN_MODE=prod and last action_log run_mode=prod media_id first
- e0034 feedback_phantom_blocked_meta_scopes: live [immune=unresolved_work] — Don't assume Threads feature blocked; verify live token scope and official endpoint (protected_by_code)
- e0035 feedback_comment_supply_discovery_and_quality: live [immune=unresolved_work] — Comment targets must be WIDE; discovery is subagent job; low-engagement targets filter out (protected_by_code)
- e0036 feedback_lifecycle_visual_sync_on_close: live [immune=multi_pointer_index_line] — lifecycle-visual.html must sync at every task close without reminders (protected_by_code)
- e0037 feedback_runner_draft_failed_two_causes: live [immune=multi_pointer_index_line,unresolved_work] — runner_draft_failed has two root causes (LLM-call vs redraft-rejection); disambiguate via context (protected_by_code)
- e0038 feedback_probes_beat_agent_fanout: live [immune=standing,multi_pointer_index_line,unresolved_work] — Never fan out agents to ask 'is X alive'; run the node's evidence command; liveness is arithmetic (protected_by_code)
- e0039 feedback_features_must_be_tenant_generic: live [immune=standing] — STANDING: every feature must work for arbitrary new client, not just respiro-brand hand-authored (protected_by_code)
- e0040 reference_two_prompt_assemblers_v3_dead: live — Two prompt assemblers exist: V3 dead in prod, V4 live in daemon.sh+v4-runner.sh
- e0041 reference_voice_files_are_skip_worktree_db_rendered: live — Voice files skip-worktree DB-rendered; git copy stale; never git-edit voice-dna.md (protected_by_code)
- e0042 project_learning_governance_rebuild: live [immune=unresolved_work] — Learning governance rebuild open: grounding gate ships but learning doesn't improve output yet (protected_by_code)
- e0043 feedback_tasks_yaml_format_preserving_edits: live — Edit tasks.yaml ONLY via leadv2-tasks-lib.sh bash funcs, never yaml.dump (causes 550-line churn)
- e0044 feedback_keep_three_four_lanes_in_flight: live [immune=unresolved_work] — Hold 3-4 independent lanes in flight; serialize only on file overlap (protected_by_code)
- e0045 feedback_verify_the_premise_before_dispatching: live [immune=unresolved_work] — Backlog row premise can itself be stale; verify before dispatching lane on it (protected_by_code)
- e0046 feedback_batch_multitask_workflows: live [immune=multi_pointer_index_line] — Founder authorizes /leadv2 to take MULTIPLE queue tasks per cycle via parallel workflows (protected_by_code)
- e0047 feedback_fix_all_full_flow_diverge: live — Big multi-bug initiatives: fix everything at once, single master plan, run full leadv2 flow (protected_by_code)
- e0048 feedback_zero_confirmation_prompts: live [immune=multi_pointer_index_line] — Zero confirmation prompts from agents; founder approves all (protected_by_code)
- e0049 feedback_dispatch_regardless_of_context: live — Child sessions out-of-process; never hold dispatch on lead's own context level
- e0050 feedback_soak_adaptive_watchlist: live — SOAK monitoring must ALWAYS adapt to current work; live watchlist file not frozen probe list
- e0051 feedback_ff_main_before_spawning_agents: live — Fast-forward local main to origin/main BEFORE spawning any diagnosis agent
- e0052 feedback_deferred_actions_go_in_ledger: live [immune=standing,multi_pointer_index_line] — Deferred actions go in scheduled-decisions.md same turn or lost; VPS job executes (protected_by_code)
- e0053 feedback_shadow_gate_must_test_enforce_path: live [immune=standing] — STANDING: shadow-green ≠ enforce-ready; pre-flip interlock must assert new-mode artifact in shadow (protected_by_code)
- e0054 feedback_migration_review_must_apply: live [immune=standing] — STANDING: migration review must dry-run apply to scratch Postgres; DDL-safety only surfaces at apply (protected_by_code)
- e0055 feedback_nothing_lost_ship_truth_ledger: live — Derive shipped state from git+VPS+.env, never memory; work lost at four identifiable stages
- e0056 feedback_stop_rederiving_fundamentals: live — Check reference memories FIRST before re-deriving system fundamentals; stop re-discovering facts
- e0057 feedback_keep_task_list_visible_track_all: live [immune=multi_pointer_index_line,unresolved_work] — Keep live tracked task list visible, surface frequently; all tasks matter (protected_by_code)
- e0058 feedback_no_parallel_git_agents_shared_tree: live [immune=standing,multi_pointer_index_line] — STANDING: agents edit FILES only, never git; lead commits all sequentially with staged-path guard (protected_by_code)
- e0059 feedback_mission_hint_scope_contamination: live [immune=standing] — STANDING: mission-hint must contain ONLY that task's scope; contaminated hint makes child execute wrong task (protected_by_code)
- e0060 feedback_subagent_death_resume_protocol: live [immune=standing] — STANDING: dev subagents die at ~160-250K tokens; commit+report per item, resume once, narrow finisher (protected_by_code)
- e0061 feedback_stale_supervisor_markers_block_workers: live [immune=unresolved_work] — Stale supervisor markers (SUPERVISOR-MODE.on) block ALL spawns; don't stack overrides, fix actual state (protected_by_code)
- e0062 project_supervise_v2_shipped: live [immune=unresolved_work] [model=spent overridden] — protected by code immunity: unresolved_work
- e0063 project_persona_prompt_identity_split: live [immune=multi_pointer_index_line,unresolved_work] — Voice prompt carries two incompatible identities (named vs anonymous); timeline file never loads (protected_by_code)
- e0064 project_dispatch_reliability_20260724: live [immune=unresolved_work] — Dispatch reliability: STALL_MAX fixed, A7 wired, codex-recursion guard still has false-kill hole (protected_by_code)
- e0065 project_glm_quota_costlog_writer: live [immune=unresolved_work] — GLM cost_log has LLM writer (step 1 done); llm_run path uncovered (protected_by_code)
- e0066 project_sd20_demo_mirror_key_miss: live [immune=unresolved_work] — Demo-mirror key rotated 2026-07-16; follow-up unresolved: systemd unit needed for VPS reboot
- e0067 project_three_doors_into_threads: live — Three independent Threads doors (Graph API / mobile cookies / browser); name door before blaming auth
- e0068 project_like_follow_engagement_writes: live [immune=unresolved_work] — Likes phantom-ok AND same-door has_liked=true yet post shows zero; follows break at handle→user_id (protected_by_code)
- e0069 project_fact_verification_packaging: live [immune=unresolved_work] — Founder decision: VERIFICATION base-tier (our liability), RESEARCH-GRADE drafting paid add-on; Tavily
- e0070 project_hallucination_reward_loop: live [immune=unresolved_work] — Verstappen fabrication published; grounding gate deployed hard-block but NOT proven on organic post (protected_by_code)
- e0071 project_voice_fidelity_to_90_think_task: live [immune=orphan_index_line] — Voice fidelity task (orphaned entry; protected_by_code); assume live per protection rule
- e0072 project_f1_post_learning_track: live — Verstappen/F1 post learning baseline pinned 2026-07-12; re-probe live to show before→after delta
- e0073 project_comment_quality_learning_loop_dead: live [immune=multi_pointer_index_line,unresolved_work] — Comment learning loop dead: bandit learns on noise, topic-diversity steering leaks into comments (protected_by_code)
- e0074 project_comment_invocation_death_rootcause: live [immune=unresolved_work] — Comment confirmed→learned freeze root: post-cycle scoring starved by V4 cutover + systemd SIGTERM (protected_by_code)
- e0075 project_camp_stage4_seam_cutover: live [immune=unresolved_work] — CAMP-STAGE4 seam live 2026-07-10/11; blocked on founder Cloudflare actions for public exposure (protected_by_code)
- e0076 project_campaign_platform_track: live [immune=unresolved_work] — Campaign platform on persona engine; repo split done 2026-07-09; spec canonical (protected_by_code)
- e0077 project_knowledge_mine_findings: live [immune=unresolved_work] — KNOWLEDGE-MINE-01 surfaced 78 lost items = 11 P0 bugs; proof layer-2 self-learning dead (protected_by_code)
- e0078 project_knowledge_strategy_second_brain: live [immune=unresolved_work] — Knowledge strategy: fix distillation drain + GC ephemera + unified retrieval over curated core (protected_by_code)
- e0079 project_partnership_negotiation: live [immune=unresolved_work] — 3-way partnership Vlasenko+Bukhtiar+Lena; founder 51%+control, 4yr vesting; TG negotiation active (protected_by_code)
- e0080 project_commerce_fleet_pilot: live [immune=unresolved_work] — Commerce fleet pilot 10 accs UA 30d; $285 cost-recovery; awaiting client decision (protected_by_code)
- e0081 project_runtime_disconnect_disease: live [immune=unresolved_work] — Runtime-disconnect disease: write paths ship without read-and-act bridge (beliefs/experiments/voice)
- e0082 project_agent_learning_loop_truth: live [immune=unresolved_work] — Agent learning loop open: reflect_log phantom, insights orphan, real lever=config_control_mode (protected_by_code)
- e0083 project_single_login_northstar: live — Single-login north-star: user logs in ONCE each for cookie and API, recurring relogins unacceptable
- e0084 project_client_console_build_now: live [immune=standing,multi_pointer_index_line] — STANDING: client console build NOW; persona onboarding + preview + BYOK dashboard (protected_by_code)
- e0085 project_ai_radar_and_t1_t10_backlog: live [immune=unresolved_work] — /ai-radar shipped; T1-T10 plugin-improvement backlog from deep-dive queued (protected_by_code)
- e0086 reference_truth_query_action_log: live — Before querying action_log use scripts/truth-query.sh; five wrong answers from hand-rolled queries
- e0087 reference_offpath_draft_failure_and_draft_error: live [immune=unresolved_work] — Off-path draft rc=1+empty: context.draft_error is real surface; LLM_FALLBACK=none rare cause (protected_by_code)
- e0088 reference_oauth_token_direct_messages_api: live [immune=unresolved_work] — Subscription OAuth token IS usable for direct Messages API (corrects stale 'blocked' belief) (protected_by_code)
- e0089 project_byok_single_key_no_fallback: live — BYOK architecture: one client key only, never fallback backend
- e0090 project_codex_workspace_write_not_fullaccess: live [immune=unresolved_work] — Codex on danger-full-access all 4 repos by informed founder choice (risk accepted) (protected_by_code)
- e0091 project_active_personas: live — Only respiro-brand active (VPS 204.168.169.186); Nik + Cascina destroyed
- e0092 project_respiro_named_founder_persona_seed: live [immune=multi_pointer_index_line] — Respiro IS named founder-persona Andrew; interest-graph includes real multi-domain interests (protected_by_code)
- e0093 reference_post_starvation_cadence_bypass: live [immune=multi_pointer_index_line] — Post starvation root: PE_REPLY_BYPASS_CADENCE=1 disabled cadence floor; fix order documented (protected_by_code)
- e0094 project_server_ops: live — VPS topology: respiro-vps only live (Nik/Cascina destroyed)
- e0095 project_infra: live [immune=unresolved_work] — Infrastructure: GitHub, Supabase (eu-west-1), Hetzner VPS, Qdrant, FastEmbed, Vercel, Paddle, CF
- e0096 project_supabase_shared: live — Supabase multi-tenant by design on one project; respiro-brand only persona
- e0097 project_web_platform: live — Next.js 16 + Tailwind v4 + shadcn v4 + Supabase Auth + Stripe stack
- e0098 project_vps_access: live [immune=multi_pointer_index_line] — VPS access: decrypt SSH key from DB, tunnel URL
- e0099 project_glm_5_2_1m_context: live [immune=multi_pointer_index_line,unresolved_work] — GLM-5.2 live with 1M token context; build for 1M-default model-agnostic (protected_by_code)
- e0100 project_threads_mobile_login_architecture: live — Threads mobile login: cookies.enc AES-256-CBC encrypted, Barcelona app_id in headers
- e0101 project_respiro_runs_v4_recovery_deadcode: live [immune=unresolved_work] — Respiro runs V4 path; run-agent.sh fixes can be dead code; verify producer path (protected_by_code)
- e0102 project_flywheel_self_learning: live [immune=unresolved_work] — Flywheel-01 shipped: scorecard ON, harness ON, shadow-apply OFF (waiting for data) (protected_by_code)
- e0103 reference_skill_body_not_eager: live [immune=multi_pointer_index_line] — Skill bodies cost nothing until invoked; frontmatter is entire eager surface (protected_by_code)
- e0104 reference_engine_cadence_and_cycle: live [immune=unresolved_work] — Engine cycles ~hourly not 5min; 55-58min apart; flag flip picked up next cycle start (protected_by_code)
- e0105 reference_reader_greps_need_external_roots: live [immune=unresolved_work] — Repo grep false-negatives; use docs-truth-inventory.sh or exact-path matching (protected_by_code)
- e0106 reference_engine_flags_registry: live [immune=multi_pointer_index_line,unresolved_work] — PE_* flags registry snapshot 2026-07-12; always verify live on VPS .env (protected_by_code)
- e0107 reference_burst_caps_persona_override_wins: live — Burst caps from personas/<slug>/safety-overrides.json override timing-config.json
- e0108 reference_learning_loop_architecture: live [immune=multi_pointer_index_line,unresolved_work] — Thompson bandits in action_bandits, composite_reward from 6h engagement backfill (protected_by_code)
- e0109 reference_engagement_browser_door_table: live [immune=unresolved_work] — Likes/follows log to persona_engagement_actions NOT action_log
- e0110 reference_health_timbre_is_the_live_map: live — health.timbre.fyi IS lifecycle-visual.html; YAML badges hand-authored drift
- e0111 reference_recommended_pillars_is_a_gate: live [immune=multi_pointer_index_line,unresolved_work] — recommended_pillars is enforcement gate not nudge; out-of-plan structurally unclaimable (protected_by_code)
- e0112 reference_account_session_origin_geo: live — Session login-origin geo baked into cookies, persists forever; mint through stable proxy
- e0113 reference_memory_hygiene_system: live [immune=unresolved_work] — Memory HOT cap ~100 lines; COLD archive; global guard installed 2026-06-23
- e0114 reference_audit_personas_tool: live — /audit-personas runs 30 probes; lead reads JSON and judges divergences
- e0115 reference_hook_agent_type_schema: live [immune=multi_pointer_index_line,unresolved_work] — PreToolUse hook: agent_type key=subagent, absent=lead; discriminator for lead-only (protected_by_code)
- e0116 reference_redispatch_needs_four_stores_cleared: live — Rewritten brief never reaches resumed lane; redispatch needs FOUR stores cleared
- e0117 reference_claude_scripts_is_a_mixed_directory: live [immune=standing] — STANDING: ~/Projects/leadv2 is single source; fix once in canonical (protected_by_code)
- e0118 reference_leadv2_plugin_repo: live [immune=multi_pointer_index_line] — leadv2 multi-copy: canonical ~/Projects/leadv2; runtime ~/.claude/plugins/local (protected_by_code)
- e0119 reference_codex_workspace_scoping: live [immune=unresolved_work] — Codex jobs need four config keys per workspace
- e0120 reference_lane_liveness_and_monitor_sandbox: live [immune=multi_pointer_index_line,unresolved_work] — Monitor sandboxed out of docs/handoff; liveness=log mtime; use Bash cron pulse (protected_by_code)
- e0121 reference_strategist_volume_is_static_arithmetic: live [immune=multi_pointer_index_line] — Strategist '48 comments' = ceil(cap×0.8) not decision; activity_plan frozen 14d (protected_by_code)
- e0122 reference_leadv2_deploy_branch_naming_mismatch: live — Phase 6 deploy: EnterWorktree→worktree-X but deploy-merge.sh expects task/X; manual branch
- e0123 reference_tasks_yaml_mapping_shape: live [immune=unresolved_work] — tasks.yaml is MAPPING {total_open, tasks:[]}, not bare list (protected_by_code)
- e0124 reference_persona_identity_canonical: live — Slug=canonical identifier everywhere; UUID only in personas.id PK (protected_by_code)
- e0125 reference_postgrest_jsonb_patch_replaces: live [immune=multi_pointer_index_line,active] — PostgREST PATCH jsonb REPLACES whole value not merges; read-merge-write (protected_by_code)
- e0126 reference_comment_cap_live_source_is_db: live [immune=multi_pointer_index_line,unresolved_work] — Live comment cap 60/day from DB personas.config; safety-overrides.json inert (protected_by_code)
- e0127 reference_storybloq_studied: live [immune=multi_pointer_index_line] — Storybloq studied 2026-06-17; dead-end for engine; three patterns adapted to leadv2
- e0128 reference_threads_barcelona_app_id: live — Threads Barcelona app_id 238260118697367 required for Path B; NOT Instagram 567067343352427
- e0129 reference_m3_repo_topology: live [immune=unresolved_work] — m3 has TWO dirs: m3 (code repo, active) vs m3-market (leadv2 control, NOT git) (protected_by_code)
- e0130 reference_fable_sunset_20260707: live [immune=multi_pointer_index_line] — Fable AVAILABLE; reach for hard tasks or explicit founder request (protected_by_code)
- e0131 project_glm_finish_guard: live [immune=multi_pointer_index_line] — GLM finish-guard in leadv2; user-scripts sync filters it; edits need MANUAL copy
- e0132 reference_cloudflare_token_pe_health: live [immune=multi_pointer_index_line] — Cloudflare token at ~/.config/cloudflare/pe-health-token; use for timbre.fyi work (protected_by_code)
- e0133 reference_voice_v2_fire_evidence_path: live [immune=multi_pointer_index_line] — voice_v2 fires via context.inject_provenance.voice.branch='v2_active' on assembly rows (protected_by_code)
- e0134 feedback_forward_questions_never_wait_architect_decides: live [immune=standing,multi_pointer_index_line,unresolved_work] — STANDING: forward child questions immediately; >15min→architect decides autonomously (protected_by_code)
- e0135 feedback_no_usd_cost_metric: live — Never report spend USD; report rate-limit window usage (5h/weekly %) (protected_by_code)
- e0136 feedback_quota_ceilings_per_provider: live — Per-provider quota ceilings with higher review ceiling: glm 80/90, codex 90/95, claude 95 (protected_by_code)
- e0137 feedback_supervise_broad_status_format: live [immune=unresolved_work] — Supervise broad-status format approved: table + content quality read (protected_by_code)
- e0138 feedback_never_end_turn_on_a_promise: live [immune=standing,multi_pointer_index_line,unresolved_work] — STANDING: never end turn on promise; tool call in same turn or don't say it (protected_by_code)
- e0139 feedback_status_as_markdown_table: live [immune=standing,unresolved_work] — STANDING: every supervisor status as markdown table (lane/what/who/state/on-disk) (protected_by_code)
- e0140 feedback_never_hardcode_arm_exclusion: live [immune=standing,multi_pointer_index_line,unresolved_work] — STANDING: never hand-exclude provider arm; quota/task/complexity decide (protected_by_code)
- e0141 reference_kimi_channel_tokenrouter: live [immune=unresolved_work] — kimi arm (TokenRouter) free code-writer; shipped 2026-07-31; live-proven; traps documented (protected_by_code)
- e0142 reference_prefill_path_never_sources_bandits: live [immune=unresolved_work] — Prefill drafter out-of-scope for bandit fns; lazy-self-source in isolated subshell (protected_by_code)
- rejected_verdict: e0062 project_supervise_v2_shipped immune_violation
```

Raw report SHA:

```text
53c126a2c3c5f9c79e619755107969952df0e74d1ba4e602a43db49a0632b8ac  /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/memory-gc-report.md
```

## Raw rejected preliminary apply evidence

This was a real model call with no verdict fixture. It proved the archive machinery, but review found that several reasons contradicted the archived source, so the run was restored and the code gained the unresolved/composite-line guards before the final dry-run above.

```text
memory-index-gc: applied 8 spent entries; index 19828 bytes / 142 lines; archive /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/archive/gc-20260803T132505335075Z
exit_code=0
project_persona_prompt_identity_split: Archived/closed as of 2026-07-26; identity conflict already resolved.
project_dispatch_reliability_20260724: Dispatch reliability diagnosed 2026-07-24; root causes (STALL_MAX, A7) fixed and deployed.
project_sd20_demo_mirror_key_miss: SD-20 key rotation incident resolved 2026-07-16; demo-mirror now has correct key.
project_comment_invocation_death_rootcause: Incident root cause diagnosed 2026-07-15; V4 scoring timeout fixed, comment queue unstuck.
project_knowledge_mine_findings: One-time knowledge mine 2026-06-15; lessons encoded in 16 tasks and separate rule memories.
project_commerce_fleet_pilot: Commerce fleet pilot deferred May 2026 without client decision; no active momentum for 3+ months.
project_agent_learning_loop_truth: Agent learning loop diagnosed 2026-06-07; phantom tables clarified, real lever identified.
reference_storybloq_studied: Storybloq evaluated 2026-06-17; dead end for persona-engine, 3 ideas adapted in leadv2.
```

Contradicting raw index lines that caused rejection:

```text
- [Archived / closed](project_persona_prompt_identity_split.md) — resolved/shipped/superseded. Also: [diversity-console](project_diversity_console_live_20260708.md), [plugin-review-fix](project_plugin_review_fix_01.md), [posts-blocked-5layer](project_posts_blocked_5layer_20260613.md)
- [Dispatch reliability 2026-07-24](project_dispatch_reliability_20260724.md) — STALL_MAX 2→6+A7 done; codex-recursion still dead
- [SD-20 demo-mirror key miss](project_sd20_demo_mirror_key_miss.md) — fixed; systemd unit owed
- [Comment invocation-death root cause](project_comment_invocation_death_rootcause.md) — SIGTERM-starved; V4 stderr not in journald
- [Knowledge Mine Findings](project_knowledge_mine_findings.md) — 11 P0 + 7 P1 bugs; 16 tasks
- [Commerce Fleet Pilot](project_commerce_fleet_pilot.md) — awaiting decision
- [Agent Learning Loop Truth](project_agent_learning_loop_truth.md) — FIX open
- [Evaluated externals — rejected](reference_storybloq_studied.md) — dead-end. Also: [external-repos](reference_external_repos_evaluated_reject.md)
```

## Raw archive audit, no-op, restore, and diff

```text
--- audit ---
{
  "archived_entries": 8,
  "entries_with_reason": 8,
  "empty_reasons": 0,
  "missing_archived_index_lines": 0,
  "missing_reason_lines": 0,
  "immunity_query": {
    "standing": 0,
    "user_type": 0,
    "opt_out": 0,
    "active": 0,
    "orphan_index_line": 0,
    "total_violations": 0
  }
}
audit_exit_code=0
--- rerun ---
memory-index-gc: no-op (index already classified at current sha256; 19828 bytes, derived line cap 179)
rerun_exit_code=0
--- restore ---
restored gc-20260803T132505335075Z
restore_exit_code=0
--- diff ---
diff_exit_code=0
```

Independent pre/post restore hashes and final state:

```text
85e870ca84c0118063eee7273ea000329aed320c94dda6a885493f8bcfc7afe2  /tmp/round2-persona-MEMORY.cffc2f86.pre
85e870ca84c0118063eee7273ea000329aed320c94dda6a885493f8bcfc7afe2  /Users/kostiantyn.vlasenko/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/MEMORY.md
diff_exit_code=0
state_absent_exit_code=0
```

## Raw regression output

```text
py_compile_exit_code=0
bash_n_exit_code=0
PASS test-memory-index-gc
focused_test_exit_code=0
git_diff_check_exit_code=0
```

The focused test uses a fake model only as a regression fixture, not as acceptance evidence. It covers one-call batching; invalid/missing reasons; model failures; all required immunity classes; ACTIVE matching; unresolved and composite-line guards; exact archived index lines; one-line reasons; independent audit; no-op rerun; and byte-exact restore.
