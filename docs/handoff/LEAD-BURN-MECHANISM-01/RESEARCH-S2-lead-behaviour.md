# Round 3 / S2 — the lead's own emitted tool-call volume

Arm: architect (research + analysis). Date: 2026-09-12. Inputs: the S2 mission numbers (one
5,304-response lead session) plus a fresh measurement of three real lead sessions in
persona-engine (13,013 assistant responses; script `/tmp/s2-toolshape.py`, probes below).

## 0. Verdict in five lines

1. **45% of the lead's tool_use mass is mission briefs it hand-writes** — `SendMessage` bodies
   (median 2.2 KB, 721 of them, 329/332 distinct) plus `Write` to `/tmp` (240 files, avg 2.5 KB)
   plus `Agent` prompts (avg 2.7 KB). No hook can remove them; they are the lead's own words.
2. **The heredoc hook relocates, it does not reduce.** Same bytes move from a Bash `command` to a
   Write `content`; the blocked instance costs an extra corrective turn (~+130 tok). In-session
   heredoc reuse is 1 of 430, so "file by path" saves nothing on first emission.
3. **The largest untouched lever is not bytes, it is response count.** Every response re-sends the
   whole context; batching 30% of turns cuts the ~190x re-read multiplier by ~15-20% at zero
   capability cost, and Anthropic ships the exact prompt line that raises batching without a gate.
4. Sub-agent isolation is measured (Anthropic: tens of thousands of tokens in, 1-2k out) and its
   failure mode is documented (vague brief → duplicate work / gaps). The break-even in lead-context
   terms is ~2.5k tokens of exploration; almost every recon here clears it.
5. **One recommendation:** a capped four-field brief contract (objective / files / acceptance /
   boundaries, pointers instead of restatements) enforced by a template and a cost-ledger *log*,
   never a deny. Estimated −80 tok/response of context growth (−28% of tool_use input).

---

## Half A — what the field has established

Every claim carries its source. Numbers are quoted from the source, not derived.

### A1. Anthropic, "Effective context engineering for AI agents" (Sep 2025)
Source: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

Concrete recommendations, verbatim (WebFetch 2026-09-12):
- Tool design: "One of the most common failure modes we see is bloated tool sets that cover too
  much functionality." — "If a human engineer can't definitively say which tool should be used in a
  given situation, an AI agent can't be expected to do better."
- Just-in-time: "agents built with the 'just in time' approach maintain lightweight identifiers …
  and use these references to dynamically load data into context at runtime using tools." Hybrid
  is endorsed: "retrieving some data up front for speed, and pursuing further autonomous exploration
  at its discretion." Claude Code is named as the hybrid example (CLAUDE.md up front, glob/grep JIT).
- Sub-agents: "Each subagent might explore extensively, using tens of thousands of tokens or more,
  but returns only a condensed, distilled summary of its work (often 1,000-2,000 tokens)."
- Compaction and structured note-taking (memory outside the window) are the two named long-horizon
  techniques.

What it does NOT say: nothing about the agent's *own* emitted tool inputs as a cost class. The
guidance is entirely about what comes *in* (tool results, retrieval, sub-agent returns).

### A2. Anthropic, "Effective harnesses for long-running agents" (Nov 2025)
Source: https://www.anthropic.com/engineering (post by Justin Young, 2025-11-26); mirror summary
https://businessdatasolutions.github.io/ai-wiki/sources/2025-11-26-anthropic-effective-harnesses-long-running-agents

Recommendations: an initializer agent writes the feature list / progress file / git baseline once;
each later session reads the progress artifact, works one feature, commits, and updates the
artifact. The mechanism for cross-window continuity is **a file the agent reads, not a message the
agent re-writes**. This is the primary-source backing for "pointer, not restatement".

### A3. Anthropic, "How we built our multi-agent research system" (Jun 2025)
Source: https://www.anthropic.com/engineering/multi-agent-research-system (WebFetch 2026-09-12)

- "agents typically use about 4× more tokens than chat interactions, and multi-agent systems use
  about 15× more tokens as chats." Token usage "explains 80% of the variance" in performance; the
  rest is "tool call frequency and model selection".
- A sub-agent brief must contain "an objective, an output format, guidance on the tools and sources
  to use, and clear task boundaries." Without them "agents duplicate work, leave gaps, or fail to
  find necessary information" (the "research the semiconductor shortage" example).
- Effort scaling: "Simple fact-finding: 1 agent with 3–10 tool calls; direct comparisons: 2–4
  subagents with 10–15 calls each; complex research: 10+ subagents."
- The lead "synthesizes these results and decides whether more research is needed — if so, it can
  create additional subagents." That sentence IS the documented re-ask path: re-asking is a new
  spawn, never an inline re-derivation.

### A4. Anthropic, "Writing effective tools for agents" (Sep 2025)
Source: https://www.anthropic.com/engineering/writing-tools-for-agents

- "Tools can consolidate functionality, handling potentially multiple discrete operations (or API
  calls) under the hood … handling frequently chained, multi-step tasks in a single tool call."
- "every token in a tool response is a token not available for reasoning"; `response_format:
  concise|detailed`, pagination defaults (~50 items), truncation, and *error messages that steer
  the agent to the cheaper path* are the named techniques.
- Consolidation is driven by "tracking tool calls" to find repeated workflows — i.e. by
  measurement of the agent's call log, which is exactly what this round is doing.

### A5. Anthropic, "Introducing advanced tool use" (Nov 2025)
Source: https://www.anthropic.com/engineering/advanced-tool-use ; Claude Code tracking issue
https://github.com/anthropics/claude-code/issues/12836

- Tool Search Tool: definitions loaded on demand, "77K to 8.7K tokens (85% reduction)".
- Programmatic Tool Calling: tools orchestrated from Python in a sandbox, "43,588 to 27,297 tokens,
  a 37% reduction", "eliminating 19+ inference passes". The mechanism is that intermediate results
  never enter the model's context — the same mechanism as sub-agent isolation, without the spawn.
- Companion post "Code execution with MCP": 150K → 2K (98.7%) on a tool-heavy workflow.
  Independent reproductions cited by https://particula.tech/blog/code-execution-mcp-token-reduction-pattern
  (78.5% with GPT-4.1; 58%→92.8% scaling with tool count).
- Claude Code issue #12836 (open) records that these betas are **not** wired into Claude Code — so
  for this harness the lever is unavailable except as "write one script, run it by path".

### A6. Anthropic, token-efficient tool use
Source: https://docs.claude.com/en/docs/agents-and-tools/tool-use/token-efficient-tool-use ;
https://claude.com/blog/token-saving-updates

"Requests save an average of 14% in output tokens, up to 70%" — on by default for Claude 4+. This
is the one lever that shrinks the tool_use *input encoding* itself; it is already applied, so the
289 tok/response measured here is post-optimisation. No further gain from this class.

### A7. Parallel tool use — model, harness, or prompt?
Source: https://platform.claude.com/docs/en/agents-and-tools/tool-use/parallel-tool-use

- Parallel tool use is on by default; `disable_parallel_tool_use: true` inside `tool_choice` turns
  it off. So the *harness* is not the limiter (Claude Code issue #64237 asks for a way to turn it
  OFF, confirming it is on).
- Anthropic's documented prompt line for Claude 4+: "For maximum efficiency, whenever you need to
  perform multiple independent operations, invoke all relevant tools simultaneously rather than
  sequentially. Prioritize calling tools in parallel whenever possible." And the guard line: "Only
  batch tool calls that are independent of each other."
- The doc's own framing is that prompting "increase[s] the likelihood" — so the residual
  one-at-a-time behaviour is the *model's* choice under an unprompted default, and it is
  prompt-addressable without a gate. This matches the S2 measurement that 42% of next-calls are
  argument-dependent (structurally unbatchable) and ~30% are batchable but only 0.55% batched.

### A8. LLMCompiler (ICML 2024) — planning a call DAG in one pass
Source: https://arxiv.org/abs/2312.04511 ; https://github.com/SqueezeAILab/LLMCompiler

"up to 3.7× latency speedup, cost savings of up to 6.7× and accuracy improvement of up to ~9%
compared to ReAct"; "cost reductions of 4.65× and 2.57× compared to ReAct and OpenAI's parallel
function calling". Cost falls because "the system can plan entire execution sequences in single
LLM calls rather than requiring constant back-and-forth". That is the formal statement of "fewer
responses, not fewer bytes" — the cost driver is the number of model invocations, each of which
re-reads the prefix.

### A9. Sub-agent cost and its failure mode, third-party measurements
Sources: https://www.mindstudio.ai/blog/claude-code-subagents-cost-tokens ;
https://www.tembo.io/blog/claude-code-subagents ;
https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them

- MindStudio: agent teams "roughly seven times more tokens than a standard Claude Code session"
  because each teammate "gets loaded with a standard set of injected context every time. None of
  that is shared or cached against your main session." — this is the spawn floor (~8-9k here,
  56k for a worker session start in the same repo).
- Anthropic's when-to-use post: isolation pays "when subtasks generate high context volume (more
  than 1000 tokens) but most of that information is irrelevant to the main task", and for
  "lookup or retrieval operations that require filtering before use".
- Tembo/ClaudeWorld: the sub-agent "receives only task-relevant context (~500 tokens) rather than
  the full conversation history" — the loss side: everything session-resident that is not in the
  brief is invisible to the worker. UNVERIFIED: no public source measures a parent re-ask rate;
  the only quantified failure is Anthropic's qualitative "duplicate work / gaps".

### A10. Prompt caching changes the arithmetic of the 190x re-read
Source: https://platform.claude.com/docs/en/build-with-claude/prompt-caching ;
https://technspire.com/en/blog/anthropic-prompt-caching-pricing-mechanics

Cache reads are billed at 0.1× base input; writes at 1.25× (5-min) or 2× (1-hour). UNVERIFIED for
this harness: that Claude Code places cache breakpoints such that the conversation prefix is
served from cache on every turn (it is the widely reported default, not probed here). If it does,
the 190x re-read is ~19x in dollars but still 190x in *context occupancy* — which is what drives
compaction cadence and therefore the 153k cold-return floor. Levers must therefore be scored on
two axes: bytes added (drives compaction) and responses emitted (drives both).

### A11. Claude Code's own Bash-avoidance instruction and why it fails
Sources: https://github.com/anthropics/claude-code/issues/21696 ;
https://github.com/anthropics/claude-code/issues/39979 ; https://github.com/anthropics/claude-code/issues/34992

The system prompt says "Avoid using Bash with the find, grep, cat, head, tail, sed, awk, or echo
commands". Issues #21696 / #39979 document that the model still reaches for Bash, "especially
after context compaction when the dedicated-tool preference gets compressed away"; #34992 documents
that the Explore sub-agent's prompt *contradicts* the parent's on this point. Two lessons for
this repo: (1) a prompt-level preference decays across compaction unless re-injected; (2) an
agent that has Bash uses it for everything — the S2 mix (90,272 of 120,449 calls) is the general
case, not a local pathology.

---

## Half B — this lead, measured

### B0. Fresh measurement (3 persona-engine lead sessions, 13,013 responses)

Probe: `python3 /tmp/s2-toolshape.py <3 jsonl>` on
`39fff1b4…`, `fe5013c6…`, `123266e0…` (the three transcripts with the most `SendMessage` calls).

| tool | calls | input bytes | bytes / response | what it is |
|---|---:|---:|---:|---|
| Bash | 5,095 | 3,349,150 | 257 | 23.5% of command bytes are heredoc bodies (430 calls, 8.4%); 13.5% inline python; 13.6% in commands ≥2 KB (140 calls, 2.7%); 21.8% of calls are <200 B but only 4.9% of bytes |
| SendMessage | 721 | 1,791,374 | 138 | hand-written mission briefs to sibling sessions `s1..s4`, `f1`, `persona-engine-*`; median 2,202 B, p90 2,904 B; 329 of 332 sampled prefixes distinct — not templated |
| Write | 514 | 1,654,105 | 127 | 240 to `/private/tmp` (590 KB, avg 2,459 B — briefs and scratch scripts); 187 to `docs/handoff` (718 KB, avg 3,839 B); 47 writes (9%) are byte-identical repeats |
| Agent | 50 | 142,413 | 11 | avg prompt 2,704 B |
| Edit | 70 | 100,226 | 8 | |

Heredoc reuse inside a session: **1 repeat in 430** (1,405 of 676,900 bytes). Cross-session
reuse: UNVERIFIED (not measured).

Composition transfers to the S2 session (289 tok/response): Bash 102 → ~24 tok/resp is heredoc
body, ~14 inline python; Write 68 → ~26 tok/resp to `/tmp`, ~32 to `docs/handoff`; SendMessage 95
is briefs. **Briefs (SendMessage + Write-to-tmp + Agent prompts) ≈ 125-135 tok/response, ~45% of
all tool_use input.**

### B1. What `SendMessage` bodies are, and what replaces them

Sample (first 220 chars of three bodies from `39fff1b4`):
```
Ты s3. Лид — сессия Leadmain. Твоя работа ниже; ПОСЫЛКА ХЕНДОФФА ИСПРАВЛЕНА, читай до конца … ЧТО В ХЕНДОФФЕ БЫЛО НЕВЕРНО (проверено мной 2026-09-06 по docs/tasks.yaml): …
Ты s4. Лид — сессия Leadmain. Твоя волна — В7 (самая большая, 14 строк из оставшегося 31). Три разведки подряд … ТВОИ СТРОКИ, по порядку: 1. `NESTED-AGENTS-AND-FORKS-01` …
Проверил твою работу — принято. `33e1c92c` на месте, 4 файла, rc=2 в `_as_assert_precedence` (строки 177, 191) …
```
They are (a) wave assignments that **restate** backlog rows already in `docs/tasks.yaml`, (b)
corrections of a handoff file the lead already wrote, (c) review verdicts that restate a diff.
Each is ~550 tokens, re-read ~190× → ~105k token-reads per brief in context occupancy.

Replacement, in order of saving:
1. **Pointer + four capped fields.** Objective (≤40 words), files/rows (paths and ids only — the
   worker reads `docs/tasks.yaml` itself), acceptance (≤3 bullets), boundaries (≤3 bullets). This is
   Anthropic's A3 list verbatim; the cap is the only addition. 550 → ~175 tok per brief.
2. **Corrections go into the file, not the message.** "ЧТО В ХЕНДОФФЕ БЫЛО НЕВЕРНО" belongs in
   `docs/handoff/<id>/mission.md` as an edit (Edit tool: only the hunk enters context) with a
   one-line message "mission.md corrected, re-read §X".
3. **Review verdicts are one line + a pointer** to the review artifact the reviewer already wrote.

### B2. The heredoc hook — reduces or relocates? (arithmetic)

Hook: `plugins/leadv2/hooks/leadv2-block-bash-heredoc.sh` — PreToolUse:Bash, denies when the
command is ≥2,048 bytes and contains a heredoc; the deny text says "Use the Write tool instead"
(lines 2-3, 34, 52-55). Its own rationale: "Heredocs >2KB in bash live in transcript forever."

A 3 KB heredoc, unblocked:
| item | tokens |
|---|---:|
| Bash tool_use input (command body) | ~750 |
| result | ~50 |
| **total added to context** | **~800** |

The same 3 KB, blocked and redirected:
| item | tokens |
|---|---:|
| blocked Bash tool_use input (still emitted, still in context) | ~750 |
| deny message (tool_result) | ~60 |
| corrective response: Write tool_use (content + path + JSON overhead) | ~780 |
| Bash to run it by path + result | ~70 |
| **total added to context** | **~1,660** |

So on the blocked instance the hook **doubles** the cost; on instances where the lead pre-empts it
by writing the file first, it is a pure relocation (~780 vs ~750 — the Write JSON envelope is
marginally larger). The `Write` body lives in the transcript exactly as long as the Bash body
would. The only situation where it reduces anything is a script re-run later by path (second run
~30 tok instead of ~750) — and in-session heredoc reuse is 1 in 430. Net: **relocates, plus a tax
of ~+900 tok on each denial**; at 2.7% of Bash calls ≥2 KB the ceiling of that tax is ~3-4
tok/response — small, but negative. It also collides with the write-guard (memory
`write-guard-vs-heredoc-workflow`): large Writes are blocked too, producing 2-4 KB heredoc
*chunks*, each with its own envelope — more calls, more bytes, same content. Verdict: the hook is
not a lever; its deny should become a log line (or be removed), see L4.

### B3. Bash inline scripts → file-by-path

Heredoc bodies are 23.5% of Bash bytes (~24 tok/response in the S2 session); inline python is
13.5% (~14 tok/response, mostly a subset). A file called by path costs: the file's authoring
(same bytes, once) + ~30 tok per invocation. With in-session reuse at 0.2%, moving a one-shot script
to a file is the relocation of B2. Saving exists only for *recurring* scripts promoted into the
plugin (committed once, never re-emitted): UNVERIFIED cross-session, but the S2 mix (analysis
one-liners over transcripts, yaml surgery, registry probes) suggests a recurring core. If one third
of heredoc bodies are recurring: ~8 tok/response. Cost: a script library that must be *discoverable*
(a listing costs floor tokens every session) and that *drifts* (the 2026-07-29 copy-drift defect is
exactly this failure class).

### B4. Ranked levers

Baseline: 289 tok/response of tool_use input; ~190 re-reads per response before compaction.
"Saved" is context growth per response; the second column is the response-count effect, which
multiplies everything.

| # | lever | mechanism (no deny) | tok/resp saved | responses saved | capability / risk cost |
|---|---|---|---:|---:|---|
| L1 | **Capped four-field brief** for SendMessage / Agent / tmp-mission Writes; pointers to `docs/tasks.yaml` rows and handoff files instead of restating them | brief template in the spawn skill and the wave protocol; PostToolUse *log* of brief size into `costs.yaml` (no block); template re-injected by `post-compact-reground` because prompt preferences decay across compaction (A11) | **~80** (121 × 0.68) | 0 | Workers lose the lead's inline nuance; Anthropic's documented failure is duplicate work / gaps (A3). Mitigation is the pointer: the nuance goes into the handoff file once, via Edit, not into every message. Risk of under-specified briefs on Heavy tasks — cap should scale with class. |
| L2 | **Batch independent calls** — add Anthropic's exact parallel-tool-use line to the lead's prompt and to `post-compact-reground`; pair with "Only batch tool calls that are independent" | prompt-level; documented to "increase the likelihood" (A7); the harness already allows it | ~0 direct | **−15-20%** (30% batchable; 42% argument-dependent is the hard floor) | Batched dependent calls fail together; Claude Code runs mutating tools sequentially anyway (UNVERIFIED). Effect on the 190× multiplier is proportional: −15-20% of *all* re-reads, and per-response fixed overhead (~68 tok user-side + text) per merged turn. |
| L3 | **Corrections and verdicts as Edit + one-line pointer**, never as a message body | convention in the wave protocol; Edit puts only the hunk in context | ~15 (subset of the 95, the correction/verdict class) | 0 | None material; the artifact is on disk and the worker re-reads it, which costs the *worker's* context, not the lead's. |
| L4 | **Turn the heredoc deny into a log** (or remove the hook) | hook exits 0 and appends size to the cost ledger | ~3-4 (removes the corrective-turn tax) | +0.6% fewer (no corrective responses) | Loses nothing: the hook never reduced bytes (B2). |
| L5 | **Promote recurring inline scripts into committed plugin scripts** (transcript stats, yaml surgery, registry probes) | measure cross-session heredoc dedupe first; promote only the top-N | ~8 (if ⅓ recurring; UNVERIFIED) | 0 | Script drift and discoverability; each listed script costs floor tokens forever. Do not promote one-shots. |
| L6 | **Delegate brief expansion** to a haiku worker from a ~300 B seed (only for briefs >1.5k tok) | Agent(haiku) writes `mission.md`, returns one line | up to ~20 more on top of L1 for the tail | 0 | Paraphrase fidelity; +~8.5k spawn floor per brief paid once in the worker. Break-even vs L1 only when the brief is long; not a first move. |
| — | Spawn for exploration (already the rule) | — | keeps ~10k-token explorations out of the lead at ~2.5k-token break-even (680 tok prompt + 1-2k return vs. inline) | — | 1,157 spawns × ~8.5k = ~9.8M tokens in 18 days paid once; the failure is re-ask via re-spawn (A3), which is bounded by L1's four fields. |

Sum of L1+L3+L4+L5 ≈ 105 tok/response (−36% of tool_use input, −24% of total context growth),
plus L2's −15-20% on the multiplier. All are prompt/template/log mechanisms; none blocks a call.

### B5. What is NOT a lever
- Token-efficient tool use (A6) is already on; the 289 is post-optimisation.
- Programmatic tool calling / tool search (A5) are not in Claude Code (issue #12836).
- "Be more careful": inadmissible per the mission rule; every row above names its mechanism.
- Blocking gates: the S2 measurement (375 denials → one- or zero-tool corrective responses, never
  batched) is reproduced by the B2 arithmetic — a deny always adds a response.

### B6. The one recommendation

**L1, the capped four-field brief with pointers.** It addresses the single largest mass (45% of
tool_use input), it is Anthropic's own brief spec (A3) with a cap added, it needs no gate, it
survives compaction if `post-compact-reground` re-injects the template, and its failure mode
(under-specified brief) is the one the field has already characterised and bounded. Estimated
−80 tok/response of context growth; cost: some Heavy-task briefs need a class-scaled cap.

---

## Sources
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- https://www.anthropic.com/engineering (Effective harnesses for long-running agents, 2025-11-26) ; https://businessdatasolutions.github.io/ai-wiki/sources/2025-11-26-anthropic-effective-harnesses-long-running-agents
- https://www.anthropic.com/engineering/multi-agent-research-system
- https://www.anthropic.com/engineering/writing-tools-for-agents
- https://www.anthropic.com/engineering/advanced-tool-use ; https://github.com/anthropics/claude-code/issues/12836 ; https://particula.tech/blog/code-execution-mcp-token-reduction-pattern
- https://docs.claude.com/en/docs/agents-and-tools/tool-use/token-efficient-tool-use ; https://claude.com/blog/token-saving-updates
- https://platform.claude.com/docs/en/agents-and-tools/tool-use/parallel-tool-use ; https://github.com/anthropics/claude-code/issues/64237
- https://arxiv.org/abs/2312.04511 (LLMCompiler)
- https://www.mindstudio.ai/blog/claude-code-subagents-cost-tokens ; https://www.tembo.io/blog/claude-code-subagents ; https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them
- https://platform.claude.com/docs/en/build-with-claude/prompt-caching ; https://technspire.com/en/blog/anthropic-prompt-caching-pricing-mechanics
- https://github.com/anthropics/claude-code/issues/21696 ; https://github.com/anthropics/claude-code/issues/39979 ; https://github.com/anthropics/claude-code/issues/34992

Probe artifacts: `/tmp/s2-toolshape.py` run on the three persona-engine transcripts named in B0;
heredoc-dedupe and Write-destination probe run inline (outputs quoted in B0).
