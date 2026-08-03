# QUESTION-DELIVERY-OWNERSHIP-01 — lane questions must reach their own lead (ownership + push delivery)

Repo: ~/Projects/leadv2 (canonical plugin). Founder order 2026-08-03: "вопросы не доходили до лидов… не только ownership… разобраться и поправить" — both layers, one task.

LIVE EVIDENCE:
- Lane questions land as q-*.yaml in ~/.claude/leadv2-state/<repo>/questions/ via leadv2-ask.sh; the ONLY delivery today is the pending-questions-inject hook, which fires on UserPromptSubmit — an autonomous lead session with no founder input NEVER sees them (starvation). Today q-ca1e1147 (asked 08:54Z) was answered by a FOREIGN session because its owner never woke.
- Question rows carry no owning-session/lead tag, so any session's hook surfaces all pendings and any lead may answer any question (wrong ownership model).

REQUIREMENTS:
1. OWNERSHIP TAG: leadv2-ask.sh stamps each question with owner fields at write time: owner_session (best available stable id: $CLAUDE_SESSION_ID or the asking process's session file), owner_task (task_id/sig8 of the lane asking), asked_repo. Backward-compatible: readers must tolerate old rows without the fields.
2. FOREIGN-ANSWER RULE in leadv2-reply-router.sh: answering a question whose owner_session differs from the caller's is allowed ONLY when the question is older than LEADV2_Q_FOREIGN_MIN_AGE_S (default 1200s) — younger foreign questions get a refusal with the owner id printed. An explicit --force flag overrides (logged).
3. PUSH DELIVERY (no founder input needed):
   a. The product-close waiting loop (leadv2-dispatch-product-close.sh pc_await_worker_exit — it already polls every 10s while its lane runs) checks for unanswered questions belonging to ITS task each log-interval and emits a `question_pending task=<id> qid=<qid> age=<s>` decision line — this reaches the lead session's existing watchers/journal without any new daemon.
   b. Offline surfacing parity with scheduled-decisions: extend the existing pending-questions-inject hook (or a sibling SessionStart hook) so a NEW session start also lists unanswered questions older than 10 min with their owner tags — not only UserPromptSubmit.
4. NON-GOALS: no new daemons/services, no Monitor-tool assumptions inside the plugin, no changes to ask/answer yaml schema beyond additive fields, no supervisor-loop changes.
5. TESTS: extend/create the relevant suite with stubbed state dir: (a) ask stamps owner fields; (b) reply-router refuses young foreign answer, allows old foreign, allows own always, --force logged; (c) old-row (no owner fields) tolerated by router and inject; (d) product-close waiting loop emits question_pending for its own task's unanswered q (stub) and NOT for other tasks'. Register in run-core-offline.sh.

ACCEPTANCE: bash -n (bash5 + /bin/bash 3.2); focused suites green; run-core-offline.sh green vs current-main baseline (verify the suite count on THIS main first — it grew today). Report per-requirement status. Do NOT commit.
Rollback: git checkout of touched files.
