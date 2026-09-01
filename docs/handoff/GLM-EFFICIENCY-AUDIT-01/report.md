# GLM Efficiency Audit — cache, thinking, model split

## 1. Capability table

| Capability | Z.AI docs (URL) | We do today (file:line) | Gap | Recommendation |
|---|---|---|---|---|
| Caching | Automatic/implicit, prefix-match; reported via `usage.prompt_tokens_details.cached_tokens` on the **native** `api/paas/v4` endpoint; hits cost ~20% of price. [cache](https://docs.z.ai/guides/capabilities/cache.md), [FAQ](https://docs.z.ai/help/faq.md). Anthropic-compat / Claude Code not mentioned. | Fresh mission prompt + fresh `claude -p` process per task, no session reuse (`glm-coder.sh:574-1196`). | Docs never confirm caching works over `api/anthropic`; our own last run shows `cache_read/creation_input_tokens: 0` (`glm-runs/260902-021625-CACHE-TRUTH-01-54ae/meta.yaml`) but `usage_is_estimate: true` — not proof of a miss. | One native-endpoint probe, same prompt twice, check `cached_tokens`. Ask Z.AI if cache applies via `api/anthropic`. |
| Usage telemetry | Native endpoint exposes real token/cache counts. | `journal.jsonl` shows `"usage":{"input_tokens":0,"output_tokens":0}` on every event; `meta.yaml`: `usage_source: stream_proxy`, `usage_is_estimate: true` (byte-count estimate). | Zero real accounting from Claude-Code path — confirmed live, not guessed. | Use Z.AI dashboard for cache/quota truth, not local logs. |
| Thinking | GLM-5.3/5.3-flash **force thinking on** (no disable); `reasoning_effort` = low/high/max, default max. [thinking-mode](https://docs.z.ai/guides/capabilities/thinking-mode.md), [thinking](https://docs.z.ai/guides/capabilities/thinking.md). Claude Code exposes `/effort`. [latest-model](https://docs.z.ai/devpack/latest-model.md) | No thinking/effort param anywhere in `glm-coder.sh`. Dispatcher computes `RESOLVED_EFFORT` but **drops it**: `leadv2-dispatch-code.sh:5100` `EFFORT-IS-NOT-WIRED-01`, emits `effort_dropped` every dispatch. | **Confirmed, self-diagnosed gap.** Every call runs forced-max reasoning regardless of task size. | Wire effort into `glm-coder.sh` spawn_args: `low` for papercuts/flash, `max` only for Heavy. |
| Model split | 5.3: 1M ctx/128K out, text-only, forced max reasoning. 5.3-flash: multimodal, 1M/128K, **3x quota** of 5.3, ~57 bench score at low cost, only tier with documented `reasoning_effort=low`. [5.3](https://docs.z.ai/guides/llm/glm-5.3.md), [5.3-flash](https://docs.z.ai/guides/vlm/glm-5.3-flash.md) | `arm=glm`→`glm-5.3` default; `arm=glm-flash`→`glm-5.3-flash` (`leadv2-dispatch-code.sh:5095-5119`), arm chosen by cost policy, not capability data. | `model-capability.yaml:167` flags all glm capability numbers as GLM-5.2-era, UNVERIFIED for 5.3 — comparison basis is stale; flash likely under-selected given 3x quota. | Refresh capability yaml from 5.3 pages; bias Standard/Light dispatch toward `glm-flash`. |
| Quota accounting | Per-**token**: `credits=(in*mult+cached_in*cached_mult+out*mult)/10,000`. Standard 15k/5h,66k/wk; Premium 35k/5h,155k/wk. Only 5.3/5.3-flash included; 50% off-peak discount outside Mon-Fri 14:00-18:00 SGT. [teamplan](https://docs.z.ai/devpack/teamplan.md) | `leadv2-quota-read.py` reads dashboard **percentage-of-window**, not raw credits (`:181-216`). | Local estimates can't reconcile against real credit formula/cache discount. | Non-blocking; keep using dashboard % for gating, stop treating local `usage_estimate_*` as cost ground truth. |
| Rate limits | Docs page requires dashboard login — could not fetch. | Only `GLM_TIMEOUT`/turn watchdogs, no explicit rate/concurrency enforcement. | UNVERIFIED. | Founder pulls numbers from `z.ai/manage-apikey/rate-limits` directly. |
| `[1m]` + auto-compact | Append `[1m]` to model name + `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000` for full 1M context. [latest-model](https://docs.z.ai/devpack/latest-model.md) | Neither used; `GLM_MODEL` is plain `glm-5.3`/`glm-5.3-flash`. | Long (45+ turn) Heavy dispatches may auto-compact well before the real 1M ceiling, losing prefix stability. | Trial `glm-5.3[1m]` + the env var on one long Heavy lane. |

## 2. Cache

**Structure**: `glm-coder.sh` puts fixed contract preambles (EVIDENCE/FOREGROUND/worktree pin) before the variable mission body — a stable prefix in principle. But each task dispatch is a brand-new `claude -p` process, never resumed/session-reused across tasks; only the 45+ turns *inside* one run share context.

**Measurability: no.** Confirmed live in `glm-runs/260902-021625-CACHE-TRUTH-01-54ae/`: every journal event has `usage:{input_tokens:0,output_tokens:0}`; meta.yaml labels the numbers `usage_source: stream_proxy`, `usage_is_estimate: true`. The Anthropic-compat/Claude-Code path never surfaces `cached_tokens` — cache-hit measurement is only possible via the Z.AI billing dashboard.

## 3. Thinking

Forced-on, max-effort by default, no off switch. The dispatcher already resolves a per-task-class effort value but discards it — `EFFORT-IS-NOT-WIRED-01`, `leadv2-dispatch-code.sh:5100`, journaled as `effort_dropped` on every GLM call. Result: papercut tasks pay the same reasoning-token cost as Heavy ones. Wiring effort (or routing to flash, whose `low` effort is documented) is the highest-leverage fix; exact savings UNVERIFIED pending an A/B.

## 4. Model split

Flash's 3x quota multiplier for near-comparable benchmark scores argues for making it the default arm on Standard/Light tasks, keeping `glm-5.3` for Heavy/architecture work. Routing plumbing already exists (`arm=glm-flash`); the gap is policy, not code.

## 5. Ranked recommendations

1. Wire `RESOLVED_EFFORT` into `glm-coder.sh` spawn_args. Evidence: `EFFORT-IS-NOT-WIRED-01` fires every dispatch. Effect: token savings on Light/Standard, magnitude UNVERIFIED.
2. Default Standard/Light dispatch to `glm-flash`. Evidence: docs' 3x quota claim. Effect: ~3x more tasks/window.
3. Refresh `model-capability.yaml` glm row (self-flagged stale at `:167`). Effect: routing decisions currently rest on wrong numbers.
4. Native-endpoint cache probe (same prompt x2, check `cached_tokens`). UNVERIFIED whether caching exists for GLM at all until run.
5. Ask Z.AI whether caching applies via `api/anthropic` — docs silent.
6. Trial `glm-5.3[1m]` + `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000` on one long Heavy lane.
7. Stop trusting local `usage_estimate_*`/`tokens_out`; they're byte-stream estimates, not real counts — use the Z.AI dashboard.
8. UNVERIFIED: rate/concurrency limits — dashboard page needs login, founder should pull directly.
