# RESEARCH-S1 — Filtering tool OUTPUT before it enters context

Arm: S1 (round 3). Date: 2026-09-12. Local runtime: Claude Code 2.1.269 (`claude --version`).
Method: 12 web searches, 22 primary-source fetches (repo READMEs, issues, official docs), 4 local probes.

## 0. Verdict in one line

**This category caps at roughly 13k of the 297k average context (4.4%) for Bash, ~9% if every tool
result of every kind were deleted outright; a realistic deployment recovers 3–5% of `cache_read`.**
It is worth doing because it is cheap and cache-safe, and it is not where the bill is.

Arithmetic used throughout:

| Quantity | Value | Source |
|---|---|---|
| Avg context per response | 296,785 tok | mission brief |
| Bash results, per-response growth | 68 tok × ~190 re-reads ≈ 13k | mission brief |
| Bash share of avg context | 13k / 297k = 4.4% | derived |
| All tool results share of growth | 18% | mission brief |
| Lead floor (system prompt + CLAUDE.md + tools) | ~153k | commit 46c2bf21 title, not re-measured here |
| Growth part of context | 297k − 153k ≈ 144k | derived |
| All tool results in avg context | 0.18 × 144k ≈ 26k = 8.7% | derived, upper bound |
| Best-case Bash-only filter (90% cut) | saves ~11.7k/turn = 3.9% | derived |
| Realistic all-tools filter (Bash 90%, Read/Grep 30%) | saves ~13–15k/turn = 4.4–5% | derived |

Nothing in this category touches the 153k floor or the ~190× re-read multiplier. See §7.

## 1. The three mechanism classes (decides every verdict)

| Class | What happens | Extra model turn? | Reduces `cache_read`? | Cache-safe? |
|---|---|---|---|---|
| **A. Blocks the call** (PreToolUse deny / exit 2) | call already emitted and billed; model must re-issue | **yes** (356/375 measured locally: one-tool correction, zero batched) | **no** | yes |
| **B. Rewrites the COMMAND** (PreToolUse `updatedInput` + `permissionDecision: allow`) | tool runs a smaller command; result is smaller at source | no (transparent) | **yes** | yes (edit is in the newest turn) |
| **C. Rewrites the RESULT** (PostToolUse `hookSpecificOutput.updatedToolOutput`) | tool runs as issued; hook replaces the result text | no | **yes** | yes (only the newest `tool_result` changes) |
| D. Edits EARLIER positions (session-history compressors, API `clear_tool_uses`) | earlier `tool_result` blocks replaced | no | yes | **no** — invalidates from the edit point |

The mission's suspicion that "rewrites bash commands" puts RTK in the weak class is **incorrect**:
class B is not class A. Class A costs a turn; class B does not. B and C are equivalent for the bill;
they differ in coverage (B needs a per-command filter table; C sees any output) and in fidelity
risk (B swaps the tool the model asked for; C keeps it).

Class D is not automatically wrong on a 98.9% `cache_read` bill. Break-even for editing earlier
history: one cache write of the suffix after the edit point (2× base rate on the 1h TTL) against
0.1× base × removed tokens × remaining turns. With suffix ≈ removed tokens that is ~20 turns; a
compaction cycle here is ~190 turns, so an edit early in a cycle pays. No shipped tool does this
live, though — every class-D tool found edits the on-disk JSONL and needs a resume (§4).

## 2. The substrate: Claude Code `PostToolUse` + `updatedToolOutput`

Primary source: <https://code.claude.com/docs/en/hooks.md> (fetched 2026-09-12).

| Fact | Evidence |
|---|---|
| Input key that carries the result is `tool_response` (object; Bash example `{type:"text", text:...}`), plus `tool_use_id`, `tool_input`, `cwd`, `transcript_path` | docs PostToolUse input example, quoted verbatim in fetch |
| `hookSpecificOutput.updatedToolOutput` replaces what the model sees, for standard tools (Bash, Edit, Write…); MCP tools use `updatedMCPToolOutput` | docs decision-control table |
| Built-in-tool support landed in **v2.1.121 (2026-04-28)**; previously MCP-only | UNVERIFIED: version from three secondary changelog mirrors (claudeupdates.dev, claudefa.st, agentpatterns.ai); the raw CHANGELOG.md fetch did not surface the line. Issue anthropics/claude-code#32105 (opened 2026-03-08) requested exactly this and is Closed. Local 2.1.269 is past either candidate version. |
| Hook is **synchronous on the critical path**; default timeout 600 s for command hooks; `"async": true` exists but an async hook cannot replace output (result would arrive after the turn) | docs timeout section; the async limitation is inferred, UNVERIFIED |
| Failure is **fail-open**: invalid JSON or non-zero exit (≠2) → "non-blocking error", original output kept; exit 2 → stderr fed to the model (a class-A outcome) | docs: "exit 0 with a parsed object that fails schema validation is a non-blocking error: the action proceeds" |
| **No size limit** documented on `updatedToolOutput` or on hook stdout | UNVERIFIED: absence in docs, not a tested bound |
| Multiple matching hooks "run in parallel"; composition of two `updatedToolOutput` values is **undocumented** | docs; practical rule: one rewriting hook per matcher |
| Built-in Bash cap: `BASH_MAX_OUTPUT_LENGTH`, default 30,000 chars, middle-truncation | anthropics/claude-code#19901 (docs gap issue), #32105 ("10-25× too large") |
| Large results are persisted to disk with a preview; 2.1.265 added "a 1 GB cap on tool results saved to disk" | CHANGELOG.md line (fetched) |
| Anthropic's own class-D: "cached microcompact" clears old tool results via `cache_edits` to keep the cache; GrowthBook-gated, no hook fires, no user control | anthropics/claude-code#42542 |
| API-level `clear_tool_uses_20250919` "Invalidates cached prompt prefixes when content is cleared" — not exposed in Claude Code | platform docs context-editing, quoted |
| Cache rule: "a change anywhere in the prefix recomputes everything after it… New content is appended at the end" — so a class-C rewrite of the newest result is cache-safe by construction | code.claude.com/docs/en/prompt-caching, quoted |

**Local finding (probe, not web):** the plugin already ships a PostToolUse Bash hook,
`plugins/leadv2/hooks/leadv2-bash-output-cap.sh` (30 lines). It is class "advisory": it reads
`.tool_output // .tool_response.output`, and on >8 KB writes a nudge to **stderr with exit 0**. Two
problems: (1) per the docs, exit-0 stderr goes to the transcript, not to the model, so the nudge
never reaches the lead; (2) the docs' payload key is `tool_response` (object), so `.tool_output`
is null and `.tool_response.output` is the wrong sub-key for the documented shape — the same
field-name bug that silently disabled agentmemory's compressor (rohitg00/agentmemory#539:
"Claude Code's PostToolUse hook payload uses the field name `tool_response`", 53%→100% after fix).
UNVERIFIED which sub-key Bash actually carries on 2.1.269; probe: a temporary hook that
`jq -c 'keys, (.tool_response|keys?)' >> /tmp/hook-shape.log`. Either way the hook is a no-op
for the bill today and is the natural place for a class-C rewriter. `grep -rl updatedToolOutput
plugins/leadv2` → no file: nothing in the plugin rewrites results yet.

## 3. Candidate table

| # | Candidate | Maintained? | Class | Claimed vs measured | Cache | Deps / egress | Verdict (against 13k/297k) |
|---|---|---|---|---|---|---|---|
| 1 | **Native `updatedToolOutput`** (Claude Code ≥2.1.121; local 2.1.269) | Anthropic | C | n/a — substrate | safe | none | **ADOPT** as the substrate for any filter. |
| 2 | **squeez** <https://github.com/claudioemmanuel/squeez> | v1.46.0 recent; 200★ | B+C (PreToolUse wraps `squeez wrap <cmd>`, PostToolUse rewrites Read/Grep/Glob/Monitor via `updatedToolOutput`; requires CC ≥2.1.119) | 91.2% (229k→20k) over 46 synthetic scenarios, chars/4 calibrated vs tiktoken; no session-level number | safe (dedup "only modifies the new result; prior messages untouched") | Rust, zero deps, no LLM, no egress | **TRIAL** in one lane. If its 91% held on our Bash mix: −11.7k/turn ≈ 3.9%. Its cross-call dedup (FNV-1a exact + MinHash ≥0.85, 16-call window) is the only shipped answer to §6. Caveat: benign outputs get 2× threshold; Agent return values un-rewritable. |
| 3 | **RTK** <https://github.com/rtk-ai/rtk> | v0.49.0 on 2026-09-11; README claims 80k★ (other pages say 28–39k) | **B** — PreToolUse returns `{"permissionDecision":"allow","updatedInput":{"command":"rtk git status"}}`; empty JSON = passthrough; **no PostToolUse hook** (mintlify.wiki/rtk-ai/rtk/integration/hooks; rtk-ai/rtk#1771) | "60–90% of bash output", explicitly "not the same as cutting your bill by 90%" (README); `rtk gain` = bytes/4 estimate. **Counter-measurement rtk-ai/rtk#582 (2026-03-13): +18% cost, +50% output tokens, +26% duration on a pytest-debugging task** — model saw compressed output as incomplete and compensated; closed, no fix visible | safe | Rust, zero deps; telemetry opt-in (salted device hash, counts) | **TRIAL, not reject.** Round-2's "dominated by `repowise distill`" is wrong on mechanism: distill is instruction-dependent (model must type it; 38 of 90,272 Bash calls; not on child PATH), RTK is hook-transparent. Distill wins on fidelity (recoverable `[repowise#ref]` markers); RTK wins on coverage. Risk: transcript shows `rtk …`, model learns the prefix and emits `rtk cd` (rtk-ai/rtk#3331). |
| 4 | **chop** <https://github.com/AgusRdz/chop> | 44★ | B (`chop init --global`, PreToolUse prepend) | 50–90% self-tracked (`chop gain`) | safe | Go, no egress | **REJECT** — strictly dominated by RTK (same class, 1/1000 the users). |
| 5 | **contextzip** <https://github.com/jee599/contextzip> | 26★, RTK fork | B live; **D** for `contextzip compact <session>` (edits `~/.claude/projects` JSONL, `.bak`, needs resume) | 61% weighted over 102 tests (326k→127k chars); session compact measured **6.7%** on a 55 MB session (152 repeated reads, 43 noisy Bash) | live: safe; compact: full rebuild on resume | Rust; anonymous telemetry on by default (`CONTEXTZIP_TELEMETRY_DISABLED=1`) | **REJECT** — RTK fork with telemetry default-on; its own class-D number (6.7%) bounds the dedup prize. |
| 6 | **context-mode** <https://github.com/scottconverse/context-mode> (port of mksglu/context-mode, ~2.5k★ upstream per skillsllm listing) | port 1★, v1.6.0 | B→C hybrid: PreToolUse redirects Bash/Read/Grep/WebFetch/Agent into an MCP sandbox, returns via `updatedToolOutput` | "30–60% typical", "98% (315 KB→5.4 KB)" research-heavy; no controlled measurement | safe | Node ≥18, SQLite FTS5, no LLM, no egress; Elastic License 2.0 | **REJECT for the lead** — anthropics/claude-code#31279 documents its circular-redirect breakage of subagent permissions; our lead is a dispatcher. Revisit for read-only recon arms only. |
| 7 | **claude-code-thrifty / cache-cow** <https://github.com/soonswan-study/claude-code-thrifty> (from anthropics/claude-code#49048, closed not-planned) | 1★ | **A** for re-reads and >1000-line files (PreToolUse block); B for tests (awk pipe via `updatedInput`) and logs (`\| tail -100`) | "3–5 re-reads per session"; "200+ lines → ~8" test filter; no session number | safe | bash ≥4 (**not macOS 3.2**), jq | **REJECT** as a package (class A for the read half, bash-4). **Steal** the awk test-filter and the `tail` rule as class-C filters. |
| 8 | **karanb192/claude-code-hooks · context-hogs** <https://github.com/karanb192/claude-code-hooks> | 509★, active | **Instrument, not filter**: async PostToolUse observer, per-file token attribution leaderboard (`/context-hogs:leaderboard`); no hook in the collection truncates output | none claimed ("no quantified savings published") | safe (observational) | Node ≥18, local | **REJECT as filter; unnecessary as instrument** — the census that produced the 18%/13k numbers already attributes from the transcript JSONL, which is exact (`usage` fields) where context-hogs estimates. Hook path 404'd; estimation method UNVERIFIED. |
| 9 | **tarekziade/claude-tools · trace compactor** <https://github.com/tarekziade/claude-tools> | 8★, 7 commits | C (PostToolUse Bash + UserPromptSubmit; regex traceback → ranked frames) | 250→40 tok per traceback example | safe | pure Python | **REJECT as dependency; copy the pattern** into our own filter for Python tracebacks. |
| 10 | **`repowise distill`** (`~/.repowise-venv/bin/repowise`, local) | installed; not on PATH in child sessions | **instruction-dependent** (model must type it) — effectively class A in outcome when forgotten | 38 uses / 90,272 Bash calls in 18 days | safe | Python venv | **RE-WRAP** — run it (or its filter logic) from a class-C hook so the model never has to remember it. UNVERIFIED whether it has a stdin/filter mode; `--help` shows only run-mode (`repowise distill COMMAND…`). |
| 11 | **Built-in caps**: `BASH_MAX_OUTPUT_LENGTH` (30k chars), `MAX_MCP_OUTPUT_TOKENS`, Read default 2000 lines; Codex `tool_output_token_limit` ("Token budget for storing individual tool/function outputs in history", learn.chatgpt.com config reference) | Anthropic / OpenAI | source-bound truncation | none | safe | none | **ADOPT (config only)**: set `BASH_MAX_OUTPUT_LENGTH` for lead sessions to ~12,000 chars (~3k tok). Bounds the tail of the distribution, not the median. Risk: middle-truncation confabulation (dev.to "Tool-Result Truncation" report, secondary) — mitigated because CC persists the full result to disk. |
| 12 | **Anthropic context editing `clear_tool_uses`** (platform API) | Anthropic | D | n/a | **breaks cache** at the clear point (docs, quoted §2) | n/a | **N/A** — not exposed in Claude Code; Anthropic's cached-microcompact already does the cache-preserving variant server-side (#42542). |
| 13 | **anthropics/claude-code#31279** agent-based large-output summarisation | closed not-planned (stale) | would be C with an LLM call | pytest 500→20 lines | safe | LLM call per large result | **REJECT** — an LLM summariser adds a billed request per big result; deterministic filters (2, 3, 9) get most of the win at zero calls. |
| 14 | **openai/codex#19001** "Add RTK directly into Codex CLI" | open since 2026-04-22; labels `context`, `enhancement`; no maintainer resolution visible | proposes **post-execution output filtering** ("filter and compress shell command output before adding it to the model context") | 60–90% (RTK's number) | n/a | n/a | **WATCH** — no code. Codex hook surface today: PreToolUse/PostToolUse for Bash + `apply_patch` only, and the runtime rejects `updatedInput` ("PreToolUse hook returned unsupported updatedInput", openai/codex#18491). UNVERIFIED whether Codex PostToolUse can rewrite output (squeez marks it "Soft"). Consequence: on Codex arms, RTK is instruction-driven (`rtk init -g --codex`), i.e. class A when the model gets the prefix wrong (#3331). |

## 4. RTK classification — the answer

RTK is **class B: PreToolUse command rewrite via `updatedInput` + `permissionDecision: allow`**,
with no PostToolUse component. Evidence: RTK hook-architecture doc (JSON quoted in table row 3),
rtk-ai/rtk#1771 (permission prompts until `permissionDecision: allow` was added), rtk-ai/rtk#1773
("returns empty output when no rewrite available" = passthrough), README "PreToolUse hook (native
binary)". Under the local measurement this is **not** the weak class: no denial, no correction
turn; the result is smaller at source exactly as a PostToolUse rewrite would make it.

So the round-2 rejection ("dominated by `repowise distill`") does not hold as stated. What does
hold against RTK is different: rtk-ai/rtk#582's author-measured **+18% cost** on a debugging task,
because lossy, unmarked compression made the model re-fetch. That is a fidelity argument, and it
favours a class-C rewriter that keeps recoverable markers (the `[repowise#ref]` idea) over RTK's
opaque rewrite. On Codex arms RTK degrades to instruction-following (class A when wrong).

## 5. Test / build / log summarisers

Everything found is deterministic and local: squeez's four-stage pipeline (ANSI strip → ≥3 identical
lines → `[×N]` → timestamp/hash templating → relevance-aware head/tail, heuristic "top errors,
files, test result, tail" for >50 lines), RTK's per-command tables (~100 commands: cargo/pytest/
jest/go test/tsc/ruff/eslint…), cache-cow's awk (session start, collected count, FAIL/ERROR lines,
summary), and `repowise distill`'s elide-with-marker. No maintained tool uses an LLM for this;
the one proposal that did (#31279) was closed not-planned. For our suites the awk/`distill` shape
is the right one: the lead needs FAIL lines, the rc, and a pointer to the full log, nothing else.

## 6. Dedup of identical results across turns

Only squeez ships it (row 2): hash/MinHash over the last 16 results, replacing a repeat with a
one-line pointer to the earlier `bash#N`. It is class C and cache-safe because it never touches
the earlier copy. cache-cow does the class-A version (block the re-read), which costs a turn.
contextzip's offline dedup measured **6.7%** of one session — a fair upper bound for what dedup
alone is worth here, and consistent with the 4–5% ceiling above.

## 7. What this category structurally cannot fix

Filters shrink the **increment**; they do not touch the ~153k floor (system prompt, CLAUDE.md,
tool definitions, skills) that is re-read on every one of the ~190 turns, nor the turn count, nor
the re-read multiplier itself. `cache_read` = Σ(context size per turn); this category can move
the "tool results" term (~13–26k) and nothing else. Even a perfect filter leaves >90% of the bill.

## 8. Three actions worth taking (design, no code here)

1. **Turn `leadv2-bash-output-cap.sh` into a class-C rewriter.** Keep the matcher (`Bash`), read
   `tool_response` (probe the sub-key first, §2), run a deterministic filter (squeez pipeline or a
   `distill`-style elide-with-marker), and return `hookSpecificOutput.updatedToolOutput` with a
   pointer to the full output on disk. Fail-open is native. Expected: −9…−12k per turn ≈ 3–4% of
   `cache_read`. One rewriter per matcher; do not add a second `updatedToolOutput` hook on `.*`.
2. **Set `BASH_MAX_OUTPUT_LENGTH` ≈ 12,000 for lead sessions** (env in plugin settings). Zero
   code, bounds the worst single result at ~3k tokens instead of ~7.5k. Pair with (1) so the
   truncated tail carries the disk pointer.
3. **One-week A/B of squeez (preferred) or RTK on one lane**, measured from transcript `usage`
   fields per tool (the census method), never from `rtk gain`/`squeez` self-reports (chars/4).
   Kill criterion: any rise in tool calls per task (the #582 failure mode).

## 9. Sources (primary unless marked)

- code.claude.com/docs/en/hooks.md; code.claude.com/docs/en/prompt-caching; platform.claude.com/docs/en/build-with-claude/context-editing
- github.com/anthropics/claude-code: CHANGELOG.md (raw), issues #32105, #31279, #49048, #42542, #19901
- github.com/rtk-ai/rtk (README, releases, issues #582, #1771, #1773, #3331); mintlify.wiki/rtk-ai/rtk/integration/hooks (secondary mirror of repo docs)
- github.com/openai/codex issues #19001, #18491; learn.chatgpt.com/docs/config-file/config-reference
- github.com/claudioemmanuel/squeez; github.com/jee599/contextzip; github.com/AgusRdz/chop; github.com/scottconverse/context-mode; github.com/soonswan-study/claude-code-thrifty; github.com/karanb192/claude-code-hooks; github.com/tarekziade/claude-tools; github.com/rohitg00/agentmemory/issues/539
- Secondary (version-date claims only): claudeupdates.dev/version/2.1.121, claudefa.st changelog, agentpatterns.ai PostToolUse page
- Local probes: `claude --version`; `plugins/leadv2/hooks/hooks.json` (20 matchers, PostToolUse block at line 432); `plugins/leadv2/hooks/leadv2-bash-output-cap.sh`; `~/.repowise-venv/bin/repowise distill --help`; `which repowise` → not on PATH
