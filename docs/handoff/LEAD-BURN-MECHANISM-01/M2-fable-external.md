# Round 2 — fable: external tooling, adopt or reject, with arithmetic

Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF-02-WHERE-THE-TOKENS-GO.md` in this worktree
first; it carries the measurement and the constraints. If it is absent, stop and say so.

You are the fable arm. You produced round 1's corrected census and the batchable fraction; this
round is a different shape — a survey that must end in verdicts. Two other arms work the floor
and compaction halves; do not read their files.

## Your half

The founder asked directly whether external repos and tools that help with this exist, and
whether we should take them. Survey them and **decide**, against our measured numbers:

    floor per turn: median 125,277 tokens (range 59,876 - 277,454)
    ceiling:        ~467,000, hit by every session
    bill:           98.9% cached-context re-read; output is 0.28%
    turns:          ~30% batchable; 10.4% are duplicate bounded reads of one file

Categories worth covering, not exhaustive and not endorsed:

- MCP proxies / gateways that expose tool schemas lazily instead of preloading all of them.
- Tool-schema minimisers.
- Context-compression and transcript-summarisation tools.
- Retrieval-instead-of-preload approaches — this stack already runs two code-intel MCPs
  (`repowise`, `codebase-memory-mcp`) that are themselves this pattern, so judge them by the same
  standard you apply to anything new.
- Anything the founder would recognise from the ecosystem that attacks per-turn context cost.

## The rule that makes this useful rather than a link dump

**Every entry ends in adopt / trial / reject, with the arithmetic.** A tool that saves 5k of a
125k floor is a reject and must be written as a reject with the number, not listed neutrally. A
tool whose saving you cannot estimate is `trial` with the specific experiment that would decide
it, in one sentence.

Weigh honestly against what it costs us: a proxy in front of MCP is a new failure point on every
tool call; a compressor that drops detail causes the re-derivation the sibling arm is measuring;
an external service means our repo contents leave this machine, which for this founder's
repositories is a real cost and not a footnote.

**Check what we already have and do not use, first.** `ENABLE_TOOL_SEARCH` and deferred MCP tool
schemas already exist in this stack, and `repowise distill` is installed and was used zero times
by the lead. A saving already sitting unused beats a new dependency, and if the biggest win is
"turn on what is already here", that is the finding — say it in the first line.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/ANALYSIS-fable-external.md` — nothing else. No code, no
`plugins/` edits, no test suites, no installing anything.

## Report back

Under 400 words: the already-have-and-unused items first with their measured saving, then the
external candidates ranked by tokens-saved-per-turn against the floor above, each with its
verdict and failure mode, and the one number in BRIEF-02 you checked that was wrong.
