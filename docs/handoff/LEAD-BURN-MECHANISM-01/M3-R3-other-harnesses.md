# Round 3 / R3 — deep research: what other harnesses do about context, and what to steal

You are a research arm. Do not read other arms' files. Deliverable at the bottom.

## Why this exists

The founder asked directly: «у нас так же были задачи изучить deepseek и codex харнесс, они вроде
достаточно эффективны в токенах и опен сорс стали». Answer it with evidence.

We run Claude Code as an orchestrating lead plus dispatched Codex / GLM / Claude workers. Measured
here:

- bill is **98.9% `cache_read`**; total cost = sum of context size over turns; average context
  296,785 per response
- session-start floor **157,216**, ceiling **~467,627**, post-compaction floor **146,092**
- **66% of context GROWTH is the agent's own `tool_use` inputs** — Bash command bodies 539k tokens,
  message bodies 502k, file-write bodies 361k over one session — *not* tool results (18%) and not
  assistant prose (7%)
- every token added mid-cycle is re-read **~190x** before the next compaction

That last decomposition is the important one: the dominant cost is what the agent *writes into its
own calls*, so a harness whose design reduces that is worth more to us than one that merely
compresses output.

## Your job

**Do at least 10 distinct web searches and READ PRIMARY SOURCES — actual READMEs, source files,
docs and issues in the repositories themselves**, not summaries. For each harness, find its
*context strategy*, not its feature list.

1. **`deepseek-ai/deepseek-harness`** (MIT, Node.js, "everything is a plugin", dev preview Aug
   2026). What exactly is its context strategy? Look for: the session-log plugin, the agent-loop
   plugin, any compaction or cache policy, and the live cache-hit-rate instrumentation it
   reportedly exposes. A reported run burned ~20M tokens in two turns with a 100% cache hit rate by
   the end — establish what that number actually measures. **Decide: is any mechanism portable to a
   Claude Code setup, or is the value only in replacing the harness?**
2. **`openai/codex` CLI.** Its context management: a reported 400K cap and a compaction that
   "replaces the input with a smaller representative list". Find the real implementation or docs.
   Read issue **#19001** (integrating RTK for shell-output filtering) and **#18345** (token usage
   regression v0.121.0 vs v0.116.0) — both reveal how Codex accounts for tokens. We already use
   Codex as a worker, so anything here is directly actionable.
3. **Aider's repo map** — the best-known just-in-time context design: a tree-sitter symbol map
   instead of file contents, sized to a token budget. What does it cost, what does it replace, and
   what would an equivalent be worth against a 157k floor?
4. **Other harnesses that publish a context strategy** — OpenHands, Cline, Roo, Goose, Amp,
   Continue, SWE-agent, Kilo. Report only the ones with a real documented mechanism (file maps,
   diff-only context, sub-agent isolation, symbol summaries, context pruning). Skip the ones whose
   only answer is "we call the model".
5. **Sub-agent context isolation as a cost mechanism.** The claim is 15-20x reduction on an
   exploratory step because the noise never enters the parent context. Find measured evidence, and
   find the failure mode — what gets lost, how often the parent has to re-ask.
6. **Anything academic or industrial with measured numbers** on context growth in long-horizon
   agents.

## The rule that makes this useful

Every entry ends with: the **one portable mechanism**, what implementing it here would plausibly
save against our numbers, its failure mode, and a verdict — **"steal this mechanism"**, **"only
works if you switch harness"**, or **"nothing here"**. A link dump is not the deliverable.

Weigh honestly: switching harness costs us the entire plugin layer, the dispatcher, the hooks and
the routing we have built. A mechanism worth copying is worth far more than a harness worth
admiring.

## Constraints

Analysis only. No installs, no `plugins/` edits, no code, no test suites. No destructive git.
Commit with `git commit -m "..." -- <your one path>`; do not push.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/RESEARCH-R3-other-harnesses.md` — nothing else.

## Report back

Under 500 words: the table (harness -> context mechanism -> portable yes/no -> what it would save
here), the top 3 mechanisms worth copying into our plugin, the honest answer on deepseek-harness
and codex specifically, and one sentence on whether switching harness is ever justified by token
cost alone.
