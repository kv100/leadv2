# What the founder actually saw

Two different real, unrelated open-source releases exist and could be "codex's harness". Founder
said the word **"codex"** — that names one of them specifically.

## 1. OpenAI Codex Harness (`openai/codex`) — this is almost certainly what he meant

- Repo: [github.com/openai/codex](https://github.com/openai/codex), Apache-2.0, ~121k stars.
- The "Codex Harness" framework release (CLI `codex exec` + Codex SDK + App-Server) was announced
  **2026-08-21** — [OpenAI: "Unlocking the Codex harness: how we built the App Server"](https://openai.com/index/unlocking-the-codex-harness/),
  covered by [KuCoin news](https://www.kucoin.com/news/flash/openai-open-sources-codex-harness-framework-for-ai-agent-development)
  and [floatboat.ai](https://floatboat.ai/blog/codex-harness-open-source). Two weeks before the
  founder's comment — timing fits "I saw" fresh news.
- App-Server protocol doc: [github.com/openai/codex/blob/main/codex-rs/app-server/README.md](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md).
- The name literally contains "codex" and the coverage explicitly uses the word "harness"
  ("Codex Harness", "open agent harness") — [SitePoint: "Codex CLI: OpenAI's Open Agent Harness"](https://www.sitepoint.com/codex-cli-openai-agent-harness-installation-commands/).

**Conclusion: this is the one.** The founder named the product ("codex"), and this is the only
2026 release where OpenAI itself uses the word "harness" for something newly open-sourced.

## 2. DeepSeek Harness — a different, unrelated project (ruled out, but real)

- Repo: [github.com/deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness),
  MIT license, "everything is a plugin," built on the Cordis meta-framework — model adapter, tool
  registry, sessions, sandboxes, filesystems, loop, orchestration, UI all swappable plugins.
  Picked up 33k+ stars within hours — [thenewstack.io coverage](https://thenewstack.io/deepseek-harness-open-source-plugins/).
- This is the "everything-is-a-plugin / Cordis / MIT" object from our earlier unrelated research
  session. It exists, it's real, but the founder said "codex," not "deepseek" — nothing here
  points to DeepSeek being what he saw. Filed for completeness only; not analyzed further below.

---

# Mechanism comparison — Codex Harness vs our leadv2 orchestrator

| mechanism | their file/doc | what it solves | do we have it | verdict | why |
|---|---|---|---|---|---|
| Lane survives lead-session death | [app-server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md) — "the agent process itself persists independently of client connections… an active turn continues executing even if a client disconnects; reconnection via `thread/resume` reattaches to the in-flight turn." Threads stay loaded in-process for 60s after the last subscriber drops, so a reconnect doesn't even need a cold restart. | Exactly our #1 pain: `LANE-MERGE-SILENTLY-REVERTS-MAIN-01` / D4 in `docs/leadv2/PLAN.md` — "a dead worker's uncommitted diff is recovered automatically, not by the lead's hand (6 rescues today)." Their answer: the agent *process itself* is the durable thing, decoupled from the client (our "lead session"); a dropped lead is a client disconnect, not a worker kill. | No — our `leadv2-lane-state.sh` (`lane_reconcile`) treats a lane as dead the moment its `pid` fails `os.kill(pid,0)` or its worktree mtime goes stale, then tries to *recover the diff after the fact* (D4, not yet built). There is no notion of "the worker process outlives the client that spawned it." | **Take, but adapt — architecture change, not a port.** | Their model requires a long-lived server process the client attaches/detaches from (app-server). Our lanes ARE the worker process (a spawned `claude`/codex CLI under a worktree) — we can't literally decouple client from process the same way, but the *principle* (make lane liveness a property of the worker process's own durability, not of the lead session staying up) reframes D2–D4: instead of "detect death, then rescue," register the worker as independently supervisable (e.g. `disown`/`nohup` + a supervisor that owns reconnect, closer to `thread/resume`) so there's nothing to rescue. |
| Single append-only source of truth per unit of work + thin queryable index on top | Same README — "JSONL rollout files… source of truth… SQLite for complementary metadata (git info, project assignments, thread sections). Authoritative conversation history lives in JSONL rather than a unified database." | Our #2 pain: PLAN.md D1 — "all 24 paths / 9 stores route through it" (not yet true) — lane state is written from many call sites into many files. | Partial — `leadv2-lane-state.sh` already IS a single-writer API (`lane_register`/`lane_transition`/`lane_deregister`, one `active.yaml` + flock + atomic rename) with an append-only `lane_events` log per row. That's the right shape. What's missing is *universal adoption*: D1 says the 24 write paths across 9 stores don't all route through this lib yet. | **Already have the mechanism; take their discipline, not new code.** | We already built the Codex-shaped answer (one authoritative file, atomic writes, append-only event trail) in `leadv2-lane-state.sh` — verified by reading it directly. The gap isn't a missing mechanism, it's enforcement: D1 is exactly "make everyone use the one writer," which is what Codex's split (rollout=truth, SQLite=index, nothing else writes conversation state) enforces by having no other write path at all. |
| Quota-aware / cost-based model routing between providers | Same README, explicitly checked and absent: "no evidence of quota-aware routing or cost-based arbitration between models or providers… clients explicitly specify `model`… `model/list` returns available models but does not implement selection logic." Token budgets are only a user-facing per-thread ceiling, not a routing input. | Our #3 pain: PLAN.md 3.2 `CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01` — "arbiter sees a ceiling percentage but not remaining quota or the weekly reset date." | We have more than Codex here already — `leadv2-route-arbiter.sh` reads live quota JSON (`quota-live.sh`) per provider and sorts by a static `cost` field (`ecost()`), using `util()` (percent-used) only as a *cap* (`capped()` — refuse above ceiling) and a tie-breaker, never as the primary ranking key. | **Not available to take — this is a gap in BOTH systems.** | Confirmed by direct read of `leadv2-route-arbiter.sh`: `ok.sort(key=lambda c:(ecost(c),u[c['provider']],c['arm'],c.get('tier','')))` — `ecost` (static per-cell `cost`) dominates the sort; `u` (live utilization) only breaks ties and gates via `capped()`. Codex Harness has no routing/arbitration layer at all to study — clients hardcode `model`. 3.2 has to be solved on our own; nothing here to borrow. |
| Phases (turns/reviews) explicitly tracked to completion via a queue, not fire-and-forget | Same README — "Submission Queue / Event Queue pattern… When the model is done… the server sends `turn/completed` with the final turn state… Completed turns automatically start queued submissions; interrupted turns pause the queue." Reviews are their own turn-shaped phase: `review/start` → `enteredReviewMode` → … → `exitedReviewMode` → final `agentMessage`, with the same completion/interrupt semantics as any other turn. | Our #4 pain: review phases not landing (4 of 22 lanes reviewed) — no equivalent named row in PLAN.md yet, but it's structurally the same disease as D3 ("`no_work` on a lane holding a real diff") — a phase transition that's supposed to happen but silently doesn't, with no queue to notice the gap. | No — our review phase is dispatched as a one-shot call (`leadv2-review` workflow / critic agent invocation) with no submission-queue guarantee that a queued review actually fires, and no first-class `phase/completed` event a caller can await or that a supervisor can retry on absence. | **Take.** | Their explicit finding (via WebFetch of the README) that turn/review completion is a *queue event*, not an assumed side effect of dispatch, is the direct fix for "review was only had by 4 of 22 lanes": model our phase transitions (build→review→deploy) as queued submissions with an explicit `phase/completed` event the lead (or D2's liveness checker) can assert against, instead of dispatching review and trusting it happened.

---

# What to take first

**Take the queue-explicit phase-completion model first**, because it is the cheapest fix for the
worst-measured symptom (4/22 lanes reviewed — a near-total miss) and it slots directly into work
already planned: PLAN.md's D2 ("single verdict on liveness") and D3 ("terminal funnel with a death
check") are half of this pattern already — add the other half, an explicit `review_requested` →
`review/completed` (or `review/failed`) event per lane that `lane_reconcile` can check for absence
and retry, mirroring Codex's `turn/completed`/queued-submission semantics read directly from
`codex-rs/app-server/README.md`. Second priority is the lane-durability reframe (worker outlives
the lead client) since it structurally removes D4's 6-rescues-a-night problem rather than automating
the rescue. The single-writer discipline (D1) needs no new mechanism, just finishing what
`leadv2-lane-state.sh` already is. Quota-aware arbitration (3.2) stays entirely on us — Codex
Harness was checked directly and has nothing there to copy.
