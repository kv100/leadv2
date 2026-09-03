# Verdicts — Orca, OmniRoute, CLAUDEX LOOP, herdr

Companion to `repos.md`. DeepSeek Harness covered separately by another agent. Sources: GitHub
READMEs/docs fetched live 2026-09-03 (WebSearch + WebFetch, no repo cloned locally — no local
source-tree grep was possible in this pass, so line numbers are not cited, only file paths named
in the fetched docs).

---

## Orca — `github.com/stablyai/orca`

Real repo, real code (Electron desktop app, TS). "ADE" for running Codex/Claude Code/OpenCode/Pi
each in an isolated git worktree with side-by-side diffs and cherry-pick merge.

| mechanism | their file | do we have it | take/don't/already-have | why |
|---|---|---|---|---|
| stable worktree-id registry (maps repo → persistent worktree id across restarts) | `src/main/git/worktree.ts` | yes — `active.yaml` row per task-id + worktree path | already-have | Same idea, different storage; no gain from copying. |
| ownership metadata (project/worktree/tab/pane/focus/layout) held in the **Electron main process** | main process state (no separate daemon file named in docs) | no — we have no single-process holder either | don't-take | Same defect class we have: ownership lives in the launching app's process, so it does not survive that process dying. Orca is a GUI app tied to being open, not a headless daemon. Adopting this teaches us nothing D1 doesn't already know. |
| liveness verdict (alive/dead) | not documented anywhere reachable (README + 3 doc pages + GitHub search turned up zero liveness/heartbeat code, only stale-Chromium-singleton-lock handling for the *app itself*, not for worktrees) | yes — `leadv2-lane-state.sh:alive()` (PID + `ps -o lstart=` birth-time match) plus a separate worktree-mtime signal | already-have (and more principled) | We could not find any Orca liveness algorithm to compare against — it appears they don't solve this problem at all, they just don't let the worktree disappear from the UI. |

**Verdict:** Orca is not a source for D1–D3. Its worktree registry solves *inventory* (which
worktrees exist), which we already have; it does **not** solve *ownership* or *liveness*
independent of a launching process — if anything it has the identical single-point-of-failure
we're trying to remove (Electron main process ≈ our lead session). Our planned D2 (single
liveness verdict by worktree write-age, not a status field) is already ahead of anything
documented for Orca. Do not delay D1–D3 waiting to "learn from Orca" — there is nothing there to
learn on this specific question. (herdr, below, is the one that actually has an answer.)

---

## OmniRoute — `github.com/diegosouzapw/OmniRoute`

Real repo, MIT, real code. Self-hostable gateway: one endpoint → 352 providers, 150+ claimed
free, 1200+ models, "RTK + Caveman" compression, 19 routing strategies, built-in MCP server.

**Founder's direct question — is this our freepool?** Partially, and the difference is the part
that matters. Both are a health-gated pass-through arm sitting in front of third-party capacity
rather than a first-party model. But OmniRoute's "free" tier is **pooled/shared third-party
free-tier keys** ("key pools with fair-share quotas", "Quota-Share routing... split a shared
account's quota fairly across pooled keys") plus some keyless pre-wired providers — i.e. it
inherits *other vendors'* ToS and ban risk at pool scale, the same risk class our freepool arm
already isolates behind `health_gated: true` / `leadv2-freepool-gate.sh` / `capability_floor:
bulk_only`. It is **not** an Anthropic-capacity substitute: none of its "free" tokens are Claude
Max seat capacity, so it does nothing about the 2026-09-15 Max 20x→5x downgrade specifically —
that's a different resource (our own Anthropic subscription), and no gateway pools that.

| mechanism | their file/doc | do we have it (freepool) | take/don't/already-have | why |
|---|---|---|---|---|
| pooled third-party free-tier keys, fair-share quota split | README "Quota-Share routing" | no — our freepool proxies one arm (`freepool-coder.sh`), not a multi-provider pool | don't-take | Pooling other people's shared free-tier keys at scale is exactly the ban-risk our `health_gated`/`untrusted: true` flags exist to fence off; widening exposure to 352 providers multiplies that risk for a resource that doesn't touch our actual bottleneck (Claude capacity). |
| 3-layer self-healing: circuit breaker (408/5xx trip), cooldown (exp. backoff, anti-thundering-herd), model lockout (429) | README architecture section | partially — we have `health_gated` gate + quota ceilings + cost-demotion sort in `leadv2-route-arbiter.sh`, no explicit circuit-breaker/cooldown state machine | take (the pattern, not the code) | Our freepool gate is a single pass/fail check per dispatch; an explicit breaker+cooldown state machine would make a flaky freepool arm degrade more gracefully instead of binary gate flips. Worth a small dev task, not urgent. |
| 4-tier fallback cascade (Subscription → API → Cheap → Free) | README | yes, conceptually — our ladder is glm → codex → sonnet → freepool with `capability_floor` | already-have | Same shape, different labels. |

**Verdict:** OmniRoute is a real, working gateway, not vaporware — but it answers a different
question than the one the founder is actually facing on 09-15. It's a volume/cost play for
*other-provider* bulk work (comparable in spirit, larger in scope, and riskier than our freepool
arm because it pools third-party keys across 352 providers instead of one gated arm). It is
**not** a relief valve for the Claude Max seat downgrade — nothing in it touches Anthropic
capacity. Don't adopt the pooled-key model; optionally lift the circuit-breaker/cooldown pattern
into `leadv2-freepool-gate.sh` later as a reliability improvement, unrelated to the 09-15 date.

---

## CLAUDEX LOOP — `github.com/chaseai-yt/claudex-loop`

Real repo, real Claude Code plugin/skill. Four phases: Recon → Interrogate → Codex adversarial
review of `PLAN.md` (round-capped, `MAX_ROUNDS`) → optional Build, where you pick the builder and
"the opposite model inspects the finished code."

| mechanism | their file | do we have it | take/don't/already-have | why |
|---|---|---|---|---|
| invariant: "whoever made the thing never checks the thing" — build-time inspector is always the model that did NOT author the artifact | `skills/codex-build` + phase-3 description | yes — our critic always reviews Phase-5 output regardless of who wrote it (architect/GLM/Codex/Sonnet), and Codex cross-checks the plan in Phase 2 | already-have | We already enforce authorship-independent review at both plan and build stages; this is the substance of their "swap." |
| literal role-swap (planner becomes builder, builder becomes reviewer) | none found — confirmed **not present** | n/a (fixed roles: architect plans, critic reviews, Codex is 2nd-brain) | don't-take (nothing to take — it doesn't exist) | Fetched content is explicit: "There is no symmetrical swap where both models both plan and build... the assignment doesn't flip — the inspector is always the model that didn't author the artifact." "Swap jobs" in the marketing line is role-*reversal-of-scrutiny*, not role-*reversal-of-function*. Our fixed-role triad (architect≠critic always) already satisfies the same invariant without needing the word "swap." |
| round-capped adversarial plan hardening before code exists | Phase 2, `MAX_ROUNDS` | yes — our Phase 2 (architect + Codex + critic → `context.yaml`) | already-have | Same shape. |

**Verdict:** The marketing line overstates the mechanic. There is no real role-swap — Codex never
becomes the builder that a Claude-authored plan gets judged by turning into a critic; it's a
fixed pattern of "the non-author always inspects," which our Phase-2/Phase-5 split already
implements. Nothing to adopt.

---

## herdr — `github.com/herdrdev/herdr`, herdr.dev

Real repo, real code, Rust, Apache-2.0 (relicensed from AGPL-3.0-or-later at v0.8.0). Not a
coding-agent itself — a **persistent background runtime/daemon that owns terminal sessions** for
existing agent CLIs (Claude Code, Codex, Cursor, 21+ others), independent of any client
connection: "a background server; the terminals live inside it," sessions "continue after you
disconnect... close the lid, drop the network, or restart the machine," and status per pane
(working/blocked/idle) is visible without attaching. Socket API + plugin marketplace for
agent-to-agent coordination (agents can split panes, start each other).

| mechanism | their file | do we have it | take/don't/already-have | why |
|---|---|---|---|---|
| session ownership held by an independent daemon process, not the launching client | herdr core (Rust daemon; specific source path not resolved in this pass — README/docs only, no local clone) | **no** — our lane's only owner is the lead session; when the lead dies, the lane has no independent process keeping it alive/tracked | **take (architecture, needs a deeper source read before committing to D1)** | Direct architectural answer to `CONTROL-PLANE-HAS-NO-OWNER-01`: decouple lane execution/tracking from the lead session's lifetime by putting ownership in a standing daemon — exactly the gap D1 ("single writer for lane state") is trying to close by other means (a shared `active.yaml` + lock, still no independent owner *process*). |
| per-pane status classification (working/blocked/idle) surfaced without polling | herdr docs | no — we infer lane state from phase + `ps`/mtime after the fact | take (concept) | Would remove the class of false "no_work"/false-dead verdicts PLAN.md already logs, if lane state were pushed by an owner process instead of inferred. |
| liveness algorithm internals (PID vs. heartbeat vs. socket keepalive) | not found in README/docs fetched | — | unresolved | Two WebFetch passes on herdr.dev and the README turned up the daemon-ownership *shape* but not the actual liveness check; needs a real clone/source read of the Rust source before this becomes a D2 implementation, not just a direction. |

**Verdict:** herdr is real and licensed permissively (Apache-2.0), and it is the one repo in this
set that actually answers the question Orca was expected to answer. It doesn't touch our
worktree/quota/routing specifics, but its core design — a standing daemon that owns agent
sessions so they survive the launching client's death — is the missing piece under D1
("single writer for lane state") and would remove the launching-session-dependency that causes
lanes to die with the lead session today. Recommend a follow-up task: clone `herdrdev/herdr` and
read the actual session-ownership/liveness source (not just docs) before deciding whether to
adopt its daemon pattern directly or just its shape for our own D1–D3 implementation. This is a
"take the idea, verify the mechanism" call, not a take/don't-take on marketing copy alone — the
one gap in this pass is that I read docs, not the Rust source, for the liveness internals.
