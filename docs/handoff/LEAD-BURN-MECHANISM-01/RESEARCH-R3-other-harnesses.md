# Other harnesses: context mechanisms worth copying

The best opportunity is to stop the lead from generating and retaining large tool-call bodies. Copy artifact references, reusable operations, and isolated exploration into the existing plugin architecture. Do not replace the harness on the strength of a cache-hit percentage. DeepSeek and Codex both contain real context-management mechanisms; neither establishes that switching would lower this lead's total cost.

Evidence cutoff: 2026-09-11. DeepSeek source is pinned to `c291e7961a515f6d7af9304e7fd1d257929aef26`; Codex to `c62d191c4c8c0cab7045fca6efc399197334bb6c`; Continue to `5522c6f44ca0ac3528b37244818fbfa39b5af470`. Other links identify the fetched documentation or source; moving branches are not release guarantees. The local measurements below are inputs from [the R3 mission](M3-R3-other-harnesses.md), not independently reproduced measurements. No other research arm's files inform this report. **UNVERIFIED: installed lead/worker versions, enabled settings, and attainable production savings.**

**Cost model and limits of the estimates**

The mission gives a 157,216-token startup floor, 146,092-token post-compaction floor, 296,785-token mean request, and approximately 467,627-token ceiling. Tool-use inputs cause 66% of growth, versus 18% for tool results and 7% for prose. The three named input-body categories total 1,402,000 tokens: Bash 539k, messages 502k, and file writes 361k.

For a token prevented from entering the parent, approximately 190 subsequent rereads are avoided under the supplied average. Thus removing 1k retained tokens avoids approximately 190k replayed input tokens; removing 10k avoids 1.9M. These are traffic estimates, not dollars or demonstrated task-level savings. They assume unchanged subsequent turns, placement, compaction behavior, and task quality. Worker work, fresh-prefix charges, summary generation, and re-reads must be subtracted. The 190 multiplier is an average, not a constant for every token.

An output filter removing 60–90% of **all** tool results would remove 10.8–16.2% of growth, not 60–90% of the bill. That is already optimistic because many results are not filterable shell output. By contrast, preventing one quarter of the named tool-input bodies would remove 350.5k newly retained tokens, approximately 66.595M rereads under the same average. That is a sensitivity calculation, not a forecast that one quarter is redundant. Newly authored code still has to be generated somewhere.

The 98.9% cache-read **bill share** is not a cache-hit **token ratio**. Caching discounts repeated input; it does not make that input free. Even perfect removal of post-compaction history cannot eliminate an unchanged 146k bootstrap. Treat prompt-floor reduction and history-growth reduction as separate interventions.

| Harness / system | Actual context mechanism | Portable to this setup? | Plausible local effect; not a measured saving |
|---|---|---|---|
| DeepSeek Harness | Durable log separate from model-visible history; threshold compaction; cached-prefix summarization | Yes: accounting and artifact discipline. Exact history replacement requires runtime control | Accounting alone saves zero; each 10k removed from retained history avoids about 1.9M rereads |
| Codex CLI | Model-dependent context limits; local or remote compaction replaces history | Yes in existing workers; opaque remote state is provider-specific | Lower retained worker context; zero automatic reduction of Claude lead bootstrap |
| Aider | Ranked tree-sitter symbol map, normally about 1k tokens, with selected files loaded separately | Yes | Replacing a 20k code inventory with 1,024 tokens saves 18,976/request, about 12.1% of the 157k floor if that inventory is actually in it |
| OpenHands | Threshold-triggered rolling summary, initial and recent events retained | Yes as bounded phase handoffs; exact condenser requires runtime control | If 100k history becomes 10k with 100 calls left, 9M gross replay tokens avoided |
| Cline | Independent research contexts; relevant paths returned | Yes | A 20k exploration reduced to a 1k parent result avoids about 3.61M parent rereads, before worker overhead |
| Amp | Explicitly supplied child context, final summary; fresh-thread handoff | Yes | Same isolated-exploration arithmetic; no published universal factor |
| Goose | Summary replaces active model context while full UI history survives | Yes as artifact plus bounded handoff | Same conditional 9M phase example; unchanged bootstrap remains |
| Roo | Summary, then reversible sliding-window hiding as fallback | Partly; exact visibility control belongs to runtime | Can remove old input bodies too; no trustworthy percentage from message-count truncation |
| Continue CLI | Budget includes tools/system/output reserve; summary replaces history | Yes: complete budget accounting | Measurement alone saves zero; prevents planning against a falsely small history-only count |
| SWE-agent | Last-N observation masking, batched updates, tagged retention | Pre-ingestion equivalent yes; retrospective masking needs runtime control | Result-only ceiling: 18% of growth before markers/recovery; cache misses can offset it |
| Kilo | Old result pruning beyond 40k recency; anchored summary plus recent tail | Partly | Same result-only ceiling; no evidence that it attacks our 66% input-body share |
| Anthropic code execution / artifact pattern | Pass values and artifact handles outside model text; reuse functions | Yes | 10k body replaced by 200-token reference: 9.8k less growth, about 1.862M rereads avoided |

**DeepSeek Harness: useful engineering, not evidence of low token consumption**

The official repository confirms MIT licensing, Node.js entry points, and developer-preview status. Its agent loop repeatedly sends derived session messages plus visible tool schemas; every accepted event enters durable history before the next step. Plugin modularity does not itself shorten requests. [D1, D2]

There are three distinct mechanisms that descriptions of “session logs” can conflate:

- Session persistence stores append-only JSONL, optionally Zstandard-compressed. This is storage compression, not model-token compression. [D3]
- The session surface is a projection: replacement events shadow old ranges for model input while the audit history survives. Compaction can therefore replace entire old interactions, including tool-call arguments, without deleting their evidence. [D4]
- The current `session-log-deepseek` plugin uploads incremental canonical log suffixes through `dsh_session_log`, disabled by default. Its README explicitly places this field outside model messages and declares zero model-input-token and KV-cache effect. It is not a magic history-compression protocol. [D5]

`compaction-basic` defaults to pressure at 80% of the routed model's context window, retaining a recent tail budget of 16%; the summary output cap defaults to 8,192 tokens. Selection preserves balanced tool-call/result boundaries. The package explicitly cannot reduce system prompts, tools, the session prefix, or a single indivisible huge tool call. Its optional pruner uses character counts: above 8,192 code points, retain 4,096 at the head and 1,024 at the tail plus a marker. Missing details in the middle are a real failure mode. [D6–D9]

The summarizer's implementation is more interesting: it reuses the conversation's tools and leading messages, then appends the summarization directive at the end. That preserves a warm prefix when the same route/provider can reuse it. Replacing the system prompt with “you are a summarizer” would destroy that alignment. This saves expensive cache misses on the auxiliary call; it does not reduce the number of cached tokens the ordinary lead keeps replaying. [D10]

**What “20M tokens, two turns, 100% cache” actually establishes.** The exact anecdote appears in MindStudio's August 14 account of an ISS-tracker task, including roughly 240k output tokens and 35 minutes. **UNVERIFIED: the underlying run's exact token buckets, provider invoice, model, and number of model calls; no attributable raw session trace is supplied by that account.** It is an anecdote to explain, not a recommendation source. A user turn can contain many model/tool steps; two turns do not mean two model requests. [D2, D13]

The first-party instrumentation defines disjoint uncached-input, cache-read, cache-write, and output buckets. Cache-hit percentage is cache-read divided by the sum of the three input buckets, excluding output; it is cumulative across the session. Historical UI code rounded to an integer. DeepSeek's own August 19 change note explicitly records that 99.5% could previously appear as 100%, and changes the Web display to retain enough decimals to distinguish near-full hits. The anecdote predates that note. This makes rounding a plausible explanation, not proof of what happened in that run. Twenty million processed tokens can include repeated copies of the same context; the figure is not 20M unique tokens nor a 20M context window. [D11, D12]

**Portable mechanism:** separate durable evidence from the small model-facing handoff, with exact usage buckets. **Saving:** zero from a meter alone; potentially 1.9M rereads per 10k excluded from subsequent parent context. **Failure:** a summary can omit unresolved obligations; prefix-preserving auxiliary calls still require ownership of the request envelope. **Verdict: steal this mechanism.** Copy the artifact/handoff discipline into the plugin; do not assume a Claude hook can install DeepSeek's history projection or control native compaction requests. The exact DeepSeek runtime plugin is not drop-in, and its telemetry-only log uploader offers **nothing here** for token reduction.

**Codex CLI: real compaction, but a growing base prompt**

The 400,000 figure is documented for GPT-5.3-Codex; it is a model context capacity, not a universal CLI hard cap or promised compaction threshold. The official configuration reference exposes `model_context_window` and `model_auto_compact_token_limit`, plus a threshold scope of `total` (default) or `body_after_prefix`. That scope distinguishes complete context from growth after the carried prefix; it does not remove that prefix's cost. Use the selected model's metadata and the actual worker version, not a remembered number. [C1, C2]

OpenAI's agent-loop explanation describes replacement of the previous input list and the remote `/responses/compact` representation, including opaque encrypted state. The pinned implementation also has a local summary path: it selects recent user messages within a 20k budget, restores chronological order, adds a summary, and replaces history. Initial context is reinjected according to whether compaction occurs mid-turn or before a turn. The pinned remote-v2 path separately builds and installs compacted history. Do not describe the local 20k rule as the remote endpoint's universal contract. [C3–C5]

Issue #18345 is a reporter's comparison, not a controlled benchmark. The displayed counters are worth reconstructing:

| Version | Displayed input, excluding separately shown cache | Separately shown cached input | Derived total prompt traffic | Displayed output |
|---|---:|---:|---:|---:|
| 0.115.0 | 60,290 | 570,368 | 630,658 | 3,105 |
| 0.116.0 | 50,392 | 333,056 | 383,448 | 2,504 |
| 0.121.0 | 83,231 | 673,664 | 756,895 | 2,963 |

Between 0.116.0 and 0.121.0, the displayed total rises from 52,896 to 86,194, about 63%; reconstructed prompt traffic rises about 97.4%, and cached input about 102.3%. The displayed total excludes the separately printed cache bucket. Reasoning is reported separately but should not be added again to completion totals. Maintainer comments attribute baseline growth to additional built-in tools/extensions and say base-token minimization remains a priority. The issue is closed; this does not prove a defect was fixed or that downgrading is the correct mitigation. [C6]

Issue #19001 requests RTK integration; it does not establish that Codex ships RTK. A contributor reports 10,387 commands with estimated output volume reduced from 32.96M to 11.02M tokens, 66.6%. These are before/after filter counters, not an end-to-end agent bill or coding-quality benchmark. The same discussion documents broken machine-readable semantics in PATH shims, raw-command bypasses, and missing evidence of task-quality preservation. At our 18% result-growth share, transferring that 66.6% reduction to every result would remove only about 12% of growth. [C7]

**Portable mechanism:** put explicit worker context budgets and full token accounting around existing Codex dispatches. **Saving:** conditional reduction in worker request size and retained history; no direct reduction to the Claude lead's 157k bootstrap. **Failure:** premature compaction increases recovery turns; built-in prompt changes can erase gains; subscription usage is not derivable from token totals alone. **Verdict: steal this mechanism.** Keep using Codex as a worker, record version/model and all usage buckets, and compare task completion plus total cost before changing limits. The encrypted OpenAI compaction item itself is provider-specific and cannot be copied into Claude messages.

**Aider: a small structural map replaces speculative whole-file reads**

Aider's repo map supplies file names, important definitions, and signatures; graph ranking selects relevant symbols. Tree-sitter extracts tags and PageRank orders them. The documented default is about 1k tokens (`1024` in source). This is not a hard universal ceiling: source includes an eightfold no-files expansion parameter, context headroom, and an approximate budget-fitting tolerance. Added editable files still enter context in full; the map does not replace code needed to implement or verify a change. [A1, A2]

Generating the map costs local parsing/ranking work rather than a summarizer-model call. Sending it still costs input tokens on requests. A map saves only the code inventory or speculative reads it displaces. If the startup floor is predominantly instructions, hooks, or schemas, the map alone saves none of that floor; adding one without deleting displaced material increases it.

**Portable mechanism:** a task-ranked, budgeted symbol map with exact file/line retrieval on demand. **Saving:** illustrative 20k inventory replaced by 1,024 tokens removes 18,976/request; a 50k inventory would remove 48,976. Neither removable inventory size is established here. **Failure:** graph ranking misses dynamic dispatch, generated code, configuration, or a low-centrality critical function. **Verdict: steal this mechanism.** Use the existing graph-first discovery interface where it can supply the equivalent; a new map implementation is not established as necessary.

**Other harnesses with documented mechanisms**

**OpenHands.** Its default LLM condenser retains initial events and recent exchanges while summarizing older history after an event-count threshold. The official evaluation reports late-session per-turn costs below half the baseline and 54% versus 53% mean solve rate on its tested SWE-bench subset. These are vendor results, not a proof of a 50% saving on our already-compacting lead; event limits also do not bound one huge event. [H1, H2] **Portable mechanism:** phase-boundary handoffs retaining goals, failures, next action, and artifact references. **Saving:** 100k old history replaced by 10k for 100 remaining requests would avoid 9M gross rereads, less summarization and recovery. **Failure:** early constraints disappear; the 146k floor remains. **Verdict: steal this mechanism.**

**Cline.** Documented research subagents have independent context/token budgets and return relevant file paths; their costs roll into total task cost. The fetched feature documentation limits these agents to read-only work and excludes MCP/browser use. That limitation is specific to Cline's implementation, not a reason to strip required tools from our dispatched workers. [H3] **Portable mechanism:** a small research contract returning a bounded finding plus source locations. **Saving:** 20k inline exploration replaced by a 1k result excludes 19k from the lead, about 3.61M future rereads. **Failure:** the parent must reopen files, and short tasks may cost more after startup overhead. **Verdict: steal this mechanism.**

**Amp.** Each specialist starts from explicit delegated instructions/context rather than the full conversation; the parent sees the final summary. Documentation also describes fresh-context handoffs. Subagents cannot communicate with each other or receive mid-task guidance in that documented design. [H4, H5] **Portable mechanism:** pass the minimum sufficient task packet, not a full-history fork. **Saving:** the same conditional exploration example; no measured 15–20x total-cost reduction is published there. **Failure:** dependencies known only to the parent are omitted, causing re-asks or wrong work. **Verdict: steal this mechanism.**

**Goose.** Auto-compaction defaults to 80% of context and is configurable; earlier conversation remains visible to users while the active model context uses a summary. [H6] **Portable mechanism:** retain full evidence in artifacts while a new phase receives a bounded summary. **Saving:** the conditional OpenHands 9M example, not a Goose benchmark or an argument to adopt its threshold. **Failure:** visible history can create a false expectation that the model still knows every detail. **Verdict: steal this mechanism.**

**Roo.** Source attempts summarization and falls back to hiding roughly half the eligible visible messages, retaining the first and tracking a reversible truncation marker. It uses a 10% window buffer plus output reservation. This is broader than observation-only filtering: old tool-input bodies can leave the request too. [H7] **Portable mechanism:** preserve the audit log independently of the active request projection. **Saving:** unknown without sizes and lifetimes of hidden messages; half the messages does not mean half the tokens. **Failure:** truncation can remove unresolved constraints, and message-pair counts do not prove semantic completeness. **Verdict: only works if you switch harness** for this exact automatic visibility mechanism, or obtain an equivalent supported history-control interface; artifact-based handoffs remain separately portable.

**Continue CLI.** Its budget calculation counts system text and tool definitions, reserves model output plus a capped buffer, and invokes summarization. The compacted history preserves the system message and summary. Its overflow recovery prunes from the latest history before summarization, a consequential potential loss of the current instruction. This is CLI source evidence, not a claim about every Continue IDE mode. [H8] **Portable mechanism:** budget the complete outgoing request and reserve room for the recovery operation. **Saving:** zero directly; makes the expensive fixed floor visible and avoids futile compaction of non-history overhead. **Failure:** wrong token estimates or removing the newest task loses continuity. **Verdict: steal this mechanism**, but not its latest-message pruning policy.

**SWE-agent.** `LastNObservations` masks older results, retaining the first observation and configured tagged exceptions. The source explicitly warns that changing old history breaks prompt caching and offers a `polling` interval to batch changes. `ClosedWindowHistoryProcessor` removes superseded file views. [H9] **Portable mechanism:** retire stale observations in batches, preserving exact evidence outside context. **Saving:** result-only maximum 18% of our growth before marker/recovery cost; it does not remove the dominant tool-call inputs. **Failure:** cache rebuilds and lost diagnostics can outweigh reductions. **Verdict: steal this mechanism** as pre-ingestion bounded results plus retrievable raw artifacts; do not assume a plugin can rewrite Claude's old messages.

**Kilo.** Documentation combines an anchored summary, recent verbatim turns, and pruning of completed tool outputs outside a 40k-token recency window. It also counts outgoing system instructions and tools before requests. [H10] **Portable mechanism:** bounded recent working set with explicit recovery references. **Saving:** the same 18% result-growth ceiling for pruning alone, with no published local quality/cost result. **Failure:** a needed older result disappears while its large invocation remains; reconstructed summaries can drift. **Verdict: steal this mechanism** at the result-admission/handoff boundary; exact retrospective pruning requires runtime support.

**Sub-agent isolation: the 15–20x claim has a denominator problem**

A first-person repository proposal reports five production-data commands with approximately 15–30k raw tokens becoming 800–1,000 parent tokens including spot checks: roughly 19–30x less new parent context. It reports one omitted item in a 33-tag inventory, no fallback observed during its testing, and explicitly says total parent-plus-child token use is roughly unchanged for the immediate operation. It supplies no repeat-run denominator or measured rate of later parent re-asks. Its “no quality regression” claim is therefore stronger than the supplied evidence. [S1]

Anthropic's production research account reports 90.2% higher internal-evaluation performance with an Opus lead and Sonnet subagents, but about 15x the tokens of ordinary chats; single-agent workflows consumed about 4x chats. That is not a 15x saving or a same-task multi-agent-versus-single-agent cost comparison. The useful engineering advice is to let children persist outputs and return references, avoiding repeated coordinator copying. [S2]

Here the long-lived lead changes the economics: a 19k exclusion can avoid 3.61M later parent rereads even if the first exploratory operation costs the same. A 157k worker floor reused for 20 steps would itself cost 3.14M input tokens before worker growth, so copying the entire lead bootstrap into a child can erase much of that benefit. **UNVERIFIED: actual worker floor and reread distribution in this lane.**

Use a break-even calculation rather than a universal multiplier: parent downstream saving is approximately `remaining parent rereads × net context excluded`; compare its price-weighted value with **incremental** worker cost over inline execution, dispatch overhead, summary cost, and expected recovery cost. If recoveries happen with probability `q` and cost `R`, include `q × R`. There is no defensible published `q` for our workflow.

**Portable mechanism:** bounded isolated exploration plus artifact-backed findings and a resume handle. **Saving:** the conditional 3.61M parent-reread example; no established 15–20x task-cost saving. **Failure:** omitted negative findings, constraints, or source evidence force another exploration. **Verdict: steal this mechanism.** Claude Code documents separate subagent contexts, scoped tools, and resumable custom/general-purpose workers; its documented built-in Explore and Plan agents are one-shot. Custom-agent startup can still load project instructions. Measure the actual child prompt before claiming isolation is cheap. [S3]

**Industrial and academic measurements that change the ranking**

**Programmatic data passing and reusable functions.** Anthropic's code-execution example moves a fetched transcript directly into another API call via a variable instead of having the model reproduce the transcript in the next tool's arguments. It also persists functions for reuse. The published 150k-to-2k, 98.7% example concerns on-demand tool exposure in that illustrative setup, not our whole bill. [S4] **Portable mechanism:** reusable operations taking paths/IDs and returning bounded evidence handles. **Saving:** replacing a 10k copied body with a 200-token invocation avoids 9.8k retained tokens and about 1.862M rereads; a quarter-body sensitivity gives 66.595M rereads as above. **Failure:** having the lead regenerate the helper or giant heredoc every time merely moves the bloat; artifacts can also be stale or inaccessible. **Verdict: steal this mechanism.**

**The Complexity Trap, SWE-agent / SWE-bench Verified.** In version 2's Table 1, Qwen3-Coder's raw cost is $1.29/instance versus $0.61 with masking, a 52.7% reduction; solve rates are 53.4% and 54.8%. The abstract instead says 53.8% for raw: use the table and disclose the inconsistency. Gemini Flash thinking drops from 40.4% solved to 36.4% with masking and 31.4% with summarization, so “no accuracy loss” is not universal. The repository publishes reproducibility material and later hybrid results. [P1, P2] **Portable mechanism:** compare deterministic masking against summarization before paying for another model. **Saving:** no direct transfer of 52.7%; this paper's observation-heavy composition differs from our 66% generated-input growth. **Failure:** lost observations or extra steps reverse quality gains. **Verdict: steal this mechanism** as an evaluation baseline, not an instruction to mask every old result.

**TokenPilot, June 2026 preprint.** Its two layers stabilize prefixes/filter ingestion and batch eviction only after both completion evidence and lack of residual utility. PinchBench continuous-mode cost falls from $7.24 to $2.79, with overall score 79.2 to 81.3. Claw-Eval continuous-mode cost falls from $81.52 to $10.58, but score falls from 63.4 to 60.8; “competitive” is not identical quality. PinchBench category scores also move unevenly. Pricing-modeled benchmark costs are not our provider invoices. [P3] **Portable mechanism:** require evidence that a phase is finished and no longer needed before excluding its history. **Saving:** the bounded-phase arithmetic above, not a transferable 61–87%. **Failure:** its ingestion model treats intentional tool calls as high-utility and mostly filters environmental feedback, which misses our main cost category; full lifecycle eviction needs request control. **Verdict: steal this mechanism** as phase-handoff eligibility, not a new memory-management subsystem.

**The three changes worth designing into the plugin**

1. **Stop copying bodies through the lead.** Give reusable operations small parameters and pass worker-authored artifact paths plus hashes/identities. Return outcome, unresolved issues, and evidence locations. Keep one-time authoring cost visible; a “helper” rewritten on every turn has not solved the problem. This targets the 66% input-growth source directly. [S2, S4]
2. **Use narrow worker contexts for bounded exploration.** Pass the task, necessary constraints, and exact starting references; return a compact result and recoverable evidence. Resume the same worker for missing detail where possible instead of reloading its entire investigation into the parent. Count child startup and recovery before accepting a saving. [H3–H5, S1, S3]
3. **Load code and tool context on demand.** Replace a verified removable inventory with a small ranked map/catalog, then fetch exact symbols or tool schemas. Keep mandatory operating constraints explicit. This is the candidate that can lower the fixed floor, but only a floor census can establish how much is actually removable. [A1, A2, S4, C6]

Earlier phase compaction is a secondary control, not the first fix: the post-compaction floor is already 146k. Pure prose slimming targets only 7% of growth. Output filters deserve a smaller, measured trial with raw evidence recovery, not the lead position in this cost program.

For acceptance, compare the same completed tasks under the same model/version/provider: complete-request token buckets, new tool-input bodies, fixed prefix, parent and child traffic, compaction cost, retrieval/re-ask frequency, elapsed time, and final correctness. A high cache-hit percentage, a smaller displayed context, or a successful launch is insufficient. This is a proposed validation contract; no implementation or test suite was run in this analysis-only lane.

Switching harness can be justified by token economics only if measured savings at equal task quality repay migration and continued maintenance of the plugin layer, dispatcher, hooks, and routing; the evidence here does not demonstrate that condition.

**Sources and search coverage**

Every recommendation above has a fetched primary source. Repository issues are attributed observations, not maintainer guarantees; benchmark and vendor reports are not local measurements. D13 is retained solely to identify the requested anecdote and is not evidence for a mechanism recommendation.

- **D1.** DeepSeek AI, [README and license entry](https://github.com/deepseek-ai/deepseek-harness/tree/c291e7961a515f6d7af9304e7fd1d257929aef26).
- **D2.** DeepSeek AI, [agent-loop README](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/core/agent-loop/README.md).
- **D3.** DeepSeek AI, [JSONL persistence README](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/session/session-persistence-jsonl/README.md).
- **D4.** DeepSeek AI, [session subsystem and surface projection](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/docs/subsystems/session.md).
- **D5.** DeepSeek AI, [session-log-deepseek README](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/session/session-log-deepseek/README.md).
- **D6.** DeepSeek AI, [basic compaction README](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/compaction/compaction-basic/README.md).
- **D7.** DeepSeek AI, [compaction defaults and routed budgets](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/compaction/compaction-basic/src/config.ts).
- **D8.** DeepSeek AI, [compaction region selection](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/compaction/compaction-basic/src/region.ts).
- **D9.** DeepSeek AI, [tool-result pruning defaults](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/compaction/compaction-tool-result-pruner/src/config.ts).
- **D10.** DeepSeek AI, [summarizer request construction](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/compaction/compaction-basic/src/summarizer.ts).
- **D11.** DeepSeek AI, [usage-projection source](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/packages/llm/token-meter/src/usage-projection.ts) and [original cache-hit formula note](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/.agents/notes/archived/feature/2026-07-21-tui-footer-cache-hit-rate.md).
- **D12.** DeepSeek AI, [near-100% display correction, August 19, 2026](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/.agents/notes/archived/feature/2026-08-19-high-cache-hit-decimal-display.md).
- **D13.** MindStudio, [DeepSeek Harness account, August 14, 2026](https://www.mindstudio.ai/blog/deepseek-harness-agentic-coding), anecdote only; underlying trace unavailable.
- **C1.** OpenAI, [GPT-5.3-Codex model context capacity](https://developers.openai.com/api/docs/models/gpt-5.3-codex).
- **C2.** OpenAI, [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- **C3.** OpenAI, [Unrolling the Codex agent loop](https://openai.com/index/unrolling-the-codex-agent-loop/).
- **C4.** OpenAI, [local compaction source](https://github.com/openai/codex/blob/c62d191c4c8c0cab7045fca6efc399197334bb6c/codex-rs/core/src/compact.rs).
- **C5.** OpenAI, [remote-v2 compaction source](https://github.com/openai/codex/blob/c62d191c4c8c0cab7045fca6efc399197334bb6c/codex-rs/core/src/compact_remote_v2.rs).
- **C6.** OpenAI repository, [issue #18345 and maintainer comments, April 2026](https://github.com/openai/codex/issues/18345).
- **C7.** OpenAI repository, [issue #19001 and RTK measurements/limitations, April 2026 onward](https://github.com/openai/codex/issues/19001).
- **A1.** Aider, [repository-map documentation](https://aider.chat/docs/repomap.html).
- **A2.** Aider, [repo-map implementation](https://github.com/Aider-AI/aider/blob/main/aider/repomap.py).
- **H1.** OpenHands, Calvin Smith, [context-condensation evaluation, April 9, 2025](https://www.openhands.dev/blog/openhands-context-condensensation-for-more-efficient-ai-agents).
- **H2.** OpenHands, [SDK context-condenser documentation](https://docs.openhands.dev/sdk/guides/context-condenser).
- **H3.** Cline, [research-subagent documentation](https://docs.cline.bot/features/subagents).
- **H4.** Amp, [models and subagent context boundaries](https://ampcode.com/docs/models-and-subagents).
- **H5.** Amp, [context management and handoff](https://ampcode.com/guides/context-management).
- **H6.** Goose, [smart context management](https://goose-docs.ai/docs/guides/sessions/smart-context-management/).
- **H7.** Roo, [context-management implementation](https://github.com/RooCodeInc/Roo-Code/blob/main/src/core/context-management/index.ts).
- **H8.** Continue, [CLI compaction and complete-input budget](https://github.com/continuedev/continue/blob/5522c6f44ca0ac3528b37244818fbfa39b5af470/extensions/cli/src/compaction.ts).
- **H9.** SWE-agent, [history processors and cache warning](https://github.com/SWE-agent/SWE-agent/blob/main/sweagent/agent/history_processors.py).
- **H10.** Kilo, [context condensing and pruning](https://kilo.ai/docs/customize/context/context-condensing).
- **S1.** kLOsk/adloop repository, [issue #45: five-command observations and limitations](https://github.com/kLOsk/adloop/issues/45).
- **S2.** Anthropic, [multi-agent research production account, June 13, 2025](https://www.anthropic.com/engineering/multi-agent-research-system).
- **S3.** Anthropic, [Claude Code custom subagents, startup and resumption](https://code.claude.com/docs/en/sub-agents).
- **S4.** Anthropic, [code execution with MCP, November 4, 2025](https://www.anthropic.com/engineering/code-execution-with-mcp).
- **P1.** Lindenbauer et al., [The Complexity Trap, version 2, September 5, 2025](https://arxiv.org/html/2508.21433v2), especially Table 1 and limitations.
- **P2.** JetBrains Research, [reproducibility repository and updated findings](https://github.com/JetBrains-Research/the-complexity-trap/blob/main/README.md).
- **P3.** Xu et al., [TokenPilot, version 1, June 15, 2026](https://arxiv.org/html/2606.17016v1), especially Tables 1–2 and cost modeling.

Search coverage included more than 30 distinct web query executions, plus direct repository/API/raw-source fetches. A reproducible subset of distinct search strings is recorded here; search results themselves are not recommendation evidence:

| Search string | Primary-source destination / outcome |
|---|---|
| `deepseek-ai deepseek-harness session-log agent-loop cache hit rate 20M` | D1–D12 through official repository |
| `openai codex compaction "representative" context` | C3–C5 |
| `aider repo map token budget tree sitter` | A1–A2 |
| `site:openhands.dev context condenser cost 2x` | H1–H2 |
| `Roo Code intelligent context condensing sliding window` | H7 |
| `Goose context management compaction summarization threshold` | H6 |
| `site:docs.cline.bot context management subagents` | H3 |
| `Amp subagents context isolation handoff docs` | H4–H5 |
| `Continue context pruning tool response token budget` | Follow-up repository tree/source fetch produced H8 |
| `SWE agent observation masking history processor` | H9 |
| `Kilo context management condensing sliding window` | H10 |
| `"subagents" "15" "20" "tokens" reduction benchmark` | S1; did not establish total-cost multiplier |
| `Anthropic multi agent research system 15 times tokens` | S2 |
| `The Complexity Trap efficient agent observation masking 52% cost` | P1–P2 |
| `TokenPilot cache efficient context management agents 2606.17016` | P3 |
| `"Deepseek Harness" "20 million"` | Anecdote traced to D13; raw run remains unverified |
| `site:anthropic.com "code execution" "98.7"` | S4 |

The failed `deepseek-harness/main` tree lookup was resolved using the official repository's `master` default. The old Codex `compact_remote.rs` path was absent at the inspected head; current remote-v2 files were read instead. These path changes are why release-qualified statements and source pins matter.
