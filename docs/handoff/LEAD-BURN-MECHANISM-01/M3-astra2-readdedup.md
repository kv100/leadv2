# Round 3 — astra-2: the duplicate-read problem, and the repos that claim to solve it

Read `docs/handoff/LEAD-BURN-MECHANISM-01/BRIEF-03-WHAT-WE-CARRY-AND-NEVER-USE.md` in this repo
first; it carries the measurement and the constraints. If it is absent, stop and say so.

You are a second `gpt-6-astra` arm. Three other arms work the apparatus, guard-cost, and
compaction-threshold halves; do not read their files or deliverables.

## The problem, stated exactly

Round 1 measured **1,557 assistant responses (10.4%) that are two bounded reads of the same file
in a row.** Round 2's fable arm then partially falsified it: in the reference session `fe5013c6`
the `Read` tool was used **14 times total** and consecutive same-path `Read`s were **0**. So if the
1,557 figure is real it is **Bash-mediated** — `sed -n '…p'`, `head -N`, `cat` — and the lead's
own global rule 2 ("keep every read bounded at the source") is what produced that shape.

The founder's position: «те самые 1 557 повторных чтений… я уверен, что на гите есть репо, которые
решают эту проблему». He is right that the class exists. Decide what we take.

## Task 1 — establish the real number and shape first

Do not evaluate tools against a number nobody has re-derived. Across the available transcripts
(`~/.claude/projects/**/**.jsonl`, `history.db` read-only/immutable):

- How many assistant responses read the same file twice **in a row**, and how many read a file the
  session had **already read at any earlier point**? These are different problems with different
  fixes; the second is much larger and is the one the tools below target.
- Split by mechanism: `Read` tool vs `Bash` (`sed -n`, `head`, `tail`, `cat`, `grep` on a path).
- How many of the repeats are **byte-identical** results? A repeat whose content changed is not
  waste. Estimate the token mass of the identical repeats, and remember the multiplier: a token
  added mid-cycle is re-read ~190x for the rest of that cycle.

If the 1,557 does not reproduce, **say so and give the number that does.** Three of the lead's
headline numbers have already failed this way.

## Task 2 — evaluate the candidates, adopt / trial / reject with arithmetic

Found by web search on 2026-09-11; verify each claim yourself, do not trust this list:

1. `github.com/cnighswonger/claude-code-cache-fix` — claims it deduplicates repeated `tool_result`
   blocks that reappear unchanged across turns, replacing later byte-identical ones with a pointer
   line, plus image stripping. Appears to work as a **request-layer interceptor** rather than a
   hook.
2. `read-once` (see `dev.to/boucle2026/read-once-a-claude-code-hook-that-stops-redundant-file-reads-4bjk`)
   — a hook with a TTL; reports 19 cache hits of 47 reads, ~38,400 tokens saved.
3. `github.com/flightlesstux/prompt-caching` — claims up to 90% cut "on repeated file reads".
4. `github.com/karanb192/claude-code-hooks` — includes a per-file context-cost leaderboard that
   attributes each tool result's tokens to the files it loaded.
5. `anthropics/claude-code` issue #49048 — a built-in read-caching / output-filtering request.
   Establish whether this is shipping upstream; if it is, adopting a third-party equivalent now may
   be wasted work.
6. Server-side context editing (`clear_tool_uses_20250919`, beta header
   `context-management-2025-06-27`; the `USE_API_CONTEXT_MANAGEMENT` flag exists in this build).

## The distinction that decides most of these verdicts

Round 1 measured, against **375 real permission denials**, that a `PreToolUse` deny produces a
one-tool or zero-tool corrective response and **never** a batched one: the denied call was already
emitted and billed, so *a hook that blocks a call costs tokens, it does not save them.* A mechanism
that rewrites or drops the **tool result** — post-execution, or at the request layer — is a
different thing and genuinely reduces `cache_read`. **Classify every candidate by which of the two
it is, and price it accordingly.** A TTL-based "stop the read from happening" hook is in the first
class and is probably a reject on our own measurement; say so with the arithmetic if it is.

## What it costs us, and weigh it honestly

A request-layer interceptor sits in front of **every** API call: a new failure point on every turn,
and it must not break prompt caching — a rewrite that changes an early block invalidates the cached
prefix after it, which on a 98.9%-cache_read bill can cost more than it saves. Establish whether
each candidate rewrites **only the tail** (cache-safe) or arbitrary positions (cache-hostile). No
repo contents may leave this machine. Do not install anything this round.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/ANALYSIS-astra2-readdedup.md` — nothing else. No `plugins/`
edits, no code, no test suites, no installs.

## Report back

Under 400 words: the re-derived duplicate-read numbers and their mechanism split, the
block-the-call vs rewrite-the-result classification per candidate, verdicts with tokens saved per
turn against a 297k average context, the cache-safety finding, and whether the 1,557 figure
survived.
