# PROVIDER-AB-WEEK-01 — one week of honest A/B between the paid code arms (founder decision 2026-09-02)

**Class:** Standard. **Repo:** leadv2 plugin (applies to every adopted repo). **Owner:** lead.
**Due:** 2026-09-09 — report + subscription decision (SD row `SD-PROVIDER-AB-WEEK-01` in persona-engine
`docs/leadv2/scheduled-decisions.md`).

## Question the founder wants answered
Are three paid subscriptions (Claude max_20x, GLM Max, Codex) needed, or is one of GLM / Codex enough?
Today's evidence is muddled: review gates do not consistently record the AUTHOR arm, so a 14-day census
could not separate "GLM wrote it" from "GLM reviewed it". Live quotas 2026-09-02 09:20Z: GLM Max 1%/5%
used (idle), Codex Plus 100% used / 0 credits (worker arm dead all night), Claude max_20x 2%/20%,
Claude team 19%/10% (free to the founder, under-used).

## Build (small, plugin-native)
1. `leadv2-review-run.sh` writes `author: <arm>` and `author_model: <model-id>` into every
   `review-gate.md` header and `review-findings.json` (it already receives `--author`). Suite + negative
   control. EXTRA_SUITE_MAP row proven.
2. `leadv2-dispatch-code.sh` journals `ab_assignment task=<id> arm=<glm|codex|sonnet-team> class=<c>`
   once per task: Standard/Light tasks alternate arms round-robin (per class, not per round — a fix-round
   stays on the arm that authored round 1 unless the arm is unavailable, which is itself a data point:
   journal `ab_unavailable arm=<a> reason=<quota|peak_hours|lock_busy|transport>`). Heavy/safety keep
   the existing rules.
3. `plugins/leadv2/scripts/leadv2-provider-ab-report.sh`: reads ledgers + gates across the adopted repos
   (persona-engine, m3-market, respiro-ios, leadv2) and prints per arm: tasks, rounds-to-PASS (median),
   high+critical per review, wall time spawn→terminal, unavailable events, and NO dollar figures (quota
   windows only, per `feedback-no-usd-cost-metric`).
4. Sonnet workers routed to the Claude team login where the dispatcher supports account selection;
   if it does not, file that as its own row and report why.

## Done when
- gates carry `author:`; `ab_assignment` lines in the journal for every Standard/Light dispatch; report
  script runs green on today's data; SD row references the script as its GO-condition query.
