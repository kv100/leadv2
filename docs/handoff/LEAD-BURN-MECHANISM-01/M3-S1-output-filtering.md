# Round 3 / S1 — deep research: filtering tool OUTPUT before it enters context

You are a research arm. Do not read other arms' files. Web research is the job — do it heavily.

## The measurement you are optimising against

- The bill is **98.9% `cache_read`**: total cost = sum of context size over turns. Average context
  **296,785** tokens per response.
- Tool RESULTS are **18%** of what grows the context; Bash results alone are 361k tokens over one
  session (68 tok/response). Every token added mid-cycle is re-read **~190x** before the next
  compaction, so 68 tok/response ≈ **13k of the 297k average context (4.4%)**.
- `repowise distill` is already installed here and was used **38 times out of 90,272 Bash calls**
  in 18 days. It is not on `PATH` in child sessions.

## The mechanism finding that decides most verdicts

Measured here against **375 real permission denials**: a `PreToolUse` hook that BLOCKS a call does
**not** save tokens. The blocked call was already emitted and billed, and the correction is a new
turn — 356 of the 375 produced a one-tool next response, 19 a zero-tool one, and **zero** produced
a batched correction. Only a mechanism that **rewrites or drops the RESULT** (`PostToolUse` with
`updatedToolOutput`, or a request-layer interceptor) actually reduces `cache_read`.

Classify every candidate by which of the two it is. That single distinction is worth more than any
savings claim in a README.

## Your job

**At least 10 distinct web searches, and fetch the PRIMARY SOURCE — the repo's own README, source,
or the official docs page — for every candidate you report.** A blog summary is a lead, never
evidence. If a repo's last commit is old or it has no real users, say so.

Cover at minimum, then go wider:

1. **`PostToolUse` hooks and `updatedToolOutput`** — the official Claude Code docs for the hook
   schema. Which tools support output replacement, what the size limits are, whether the hook's own
   latency is on the critical path, and what happens on hook failure.
2. **RTK / "Rust Token Killer"** (`github.com/rtk-ai/rtk`), and `openai/codex` issue **#19001**
   proposing to integrate it. Establish whether it is `PreToolUse` (rewrites the COMMAND) or
   post-execution (rewrites the OUTPUT) — the README language of "rewrites bash commands" suggests
   the former, which under our measurement is the weak class. Get this right; our round-2 arm
   rejected it as dominated by `repowise distill` and that verdict depends on the answer.
3. **Hook collections and plugin marketplaces that ship output filters** — e.g.
   `karanb192/claude-code-hooks`, and anything with a per-file or per-tool context-cost leaderboard.
   An instrument that ATTRIBUTES tokens to their source is worth reporting separately from a filter.
4. **Test / build / log output summarisers for agents** — anything that turns a 10,000-line build
   log into a 200-line error summary before it enters context.
5. **Large-file-read and search-result truncation** — tools that bound `Read`, `grep`, and `ls`
   results at the source.
6. **Anything that deduplicates identical tool results across turns.**

## What to return per candidate

Exact repo/URL · maintained? (last commit, stars) · **blocks-the-call vs rewrites-the-result** ·
claimed vs author-measured savings · **does it break prompt caching** (rewrites only the tail, or
arbitrary earlier positions — on a 98.9% cache_read bill this can invert the verdict) ·
dependencies and whether any data leaves the machine · **verdict adopt / trial / reject with
arithmetic against "tool results ≈ 13k of a 297k context"**.

Be honest about the ceiling: if the entire category caps at ~13k of 297k (4.4%), say so plainly in
the first line and rank accordingly. A correct "this category is small" is a better deliverable
than an enthusiastic list.

## Constraints

Analysis only. No installs, no `plugins/` edits, no code, no test suites. No destructive git.
Commit with `git commit -m "..." -- <your one path>`; do not push.

## Deliverable

`docs/handoff/LEAD-BURN-MECHANISM-01/RESEARCH-S1-output-filtering.md` — nothing else.

## Report back

Under 500 words: the candidate table, the RTK classification answer, the three worth acting on, and
one sentence on what this category structurally cannot fix.
