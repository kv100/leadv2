# Round 3 / S2 — the lead's own behaviour is the largest untouched lever

You are a research + analysis arm. Do not read other arms' files.

## The finding nobody is working

Decomposition of what grows the context in one 5,304-response lead session (bytes on disk / 4; the
books close to within 15% of measured growth):

| component | tokens | per response | share of growth |
|---|---:|---:|---:|
| **assistant `tool_use` inputs** | **1,532k** | **289** | **66%** |
| — Bash command bodies | 539k | 102 | |
| — SendMessage bodies | 502k | 95 | |
| — Write bodies | 361k | 68 | |
| tool results (all tools) | 420k | 79 | 18% |
| user-side text incl. injected reminders | 200k | 38 | 9% |
| assistant text | 160k | 30 | 7% |

**Two thirds of everything added to context is what the lead writes into its own tool calls**, and
every one of those tokens is re-read **~190x** before the next compaction. This is larger than tool
results, larger than the assistant's prose, and larger than any external tool can address.

Related measurements you may use:
- ~30% of turns are batchable (95% range 19-44%); only 0.55% actually are.
- Session-start floor: lead **153,228** median vs a worker in the *same repo* **~56,500**.
- Tool mix over 18 days, all sessions: `Bash` 90,272 · `Read/Write/Edit` 22,572 · `Agent` 1,157 ·
  `Skill` 72 · code-intel MCP 79.
- Measured against 375 permission denials: a `PreToolUse` deny produces a one-tool or zero-tool
  corrective response and **never** a batched one — so a gate that blocks a call costs tokens
  rather than saving them. Any recommendation you make must survive that fact.

## Your job — two halves, both required

### Half A: research (at least 8 distinct web searches, primary sources)

What has the field actually established about reducing an agent's *own* emitted tool-call volume?

- Anthropic's own guidance: "Effective context engineering for AI agents" and "Effective harnesses
  for long-running agents" — what do they say about tool design, batching, and just-in-time
  retrieval? Quote the concrete recommendations, not the philosophy.
- **Sub-agent context isolation as a cost mechanism.** The claim is 15-20x reduction on an
  exploratory step because the noise never enters the parent context. Find measured evidence and,
  more importantly, the **failure mode**: what gets lost, how often the parent re-asks, and what a
  spawn itself costs (here an agent body plus the subagent protocol is ~8-9k per spawn, and there
  were 1,157 spawns in 18 days).
- **Token-efficient tool design** — fewer, higher-level tools vs many primitives; what the evidence
  says about an agent that has `Bash` and therefore uses it for everything (90,272 of 120,449 calls
  here).
- Any published work on **batching / parallel tool calls** and why models emit one call at a time:
  is it the model, the harness, or the prompt? Measured here: the next call is chosen after the
  previous result in 42% of cases (argument-dependent), and roughly half the rest are
  decision-gated.
- Prompt or system-prompt patterns that measurably changed an agent's tool-call shape.

### Half B: analysis of this specific lead

Using the numbers above, say concretely what would change the 289 tokens/response of tool_use
input. Be specific and ranked, with an estimated saving each:

- `SendMessage` bodies are 95 tok/response — a third of the whole tool_use mass. What is that, and
  what would replace it?
- `Write` bodies are 68 tok/response, and there is a hook here that blocks large Bash heredocs and
  tells the lead to use `Write` instead — which moves the same bytes from one tool to another.
  **Does that hook reduce anything, or only relocate it?** Answer with arithmetic.
- Bash command bodies are 102 tok/response across 90,272 calls. What fraction is inline scripts
  (heredocs, `python3 - <<`) that could live in a file called by path instead — and what does a
  file-plus-path cost versus the inline body, counting the ~190x re-read?

## The rule

Every recommendation ends with an estimated tokens/response saved and **what it costs in
capability or risk**. A recommendation that amounts to "the lead should be more careful" is not
admissible unless you name the mechanism that makes it happen without a blocking gate — because
blocking gates are measured here to cost more than they save.

## Constraints

Analysis only. No installs, no `plugins/` edits, no code, no test suites. No destructive git.
Commit with `git commit -m "..." -- <your one path>`; do not push.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/RESEARCH-S2-lead-behaviour.md` — nothing else.

## Report back

Under 500 words: the research findings with sources, the ranked behaviour levers with tokens/
response saved, the verdict on the heredoc hook (reduces vs relocates), and the one recommendation
you would make if you could only make one.
