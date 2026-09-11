# R4 — External research: shrinking Claude Code's startup context floor

Target: measured floor 178.3k tokens (MCP tool defs 115.3k, memory 28.2k, skills 16k, system tools 11.1k,
system prompt 3k, custom agents 1.3k). Founder wants <100k. This doc is raw research evidence, quoted
with links. Verdicts/recommendations are in the 400-word summary returned to the caller.

---

## 1. `ENABLE_TOOL_SEARCH` / tool-search deferral

**Is the schema actually absent, or still counted?**

Primary source — [Anthropic tool-search-tool API docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool):

> "`defer_loading` controls what enters the context window, not what you send in the request:
> * You still send every tool's full definition in the `tools` array on every request, including the
>   deferred ones. The API needs them server-side to run the search and expand `tool_reference` blocks.
> * Tools without `defer_loading` load into context immediately.
> * Tools with `defer_loading: true` load only when Claude discovers them through search."

> "Internally, the API excludes deferred tools from the system-prompt prefix... The prefix is untouched,
> so prompt caching is preserved."

> "Tool search isn't metered as a separate server tool... and the tool definitions that search loads
> into context count as input tokens like any other tool definition."

So: the full schema is sent over the wire on **every** API call (server-side requirement), but it is
**not counted against the context window / not billed as input tokens** unless/until Claude's search
discovers it and it gets expanded into the visible conversation. `/context`'s reported "MCP tools" number
reflects only what's been expanded, not the full deferred catalog. This resolves the founder's question:
deferred ≠ absent from the wire, but deferred = absent from the *context window and token bill* until used.

**Valid `ENABLE_TOOL_SEARCH` values** — [Claude Code docs, Scale to many tools with tool search](https://code.claude.com/docs/en/agent-sdk/tool-search):

| Value | Behavior (quoted) |
|---|---|
| unset | "Tool search is on. Tool definitions are deferred and discovered on demand." (falls back to upfront loading on old GCP Agent Platform models, non-first-party `ANTHROPIC_BASE_URL`, or Azure Foundry) |
| `true` | "Tool search is always on" except Azure Foundry / old GCP models; "sends the beta header through proxies, and requests fail on proxies that don't support `tool_reference` blocks" |
| `auto` | "Counts the tokens in the tool definitions that tool search can defer and compares the total against the model's context window. When the total reaches 10% of the window, tool search activates. Below that, the SDK loads every tool definition into context upfront." |
| `auto:N` | "Same as `auto` with a custom percentage. `auto:5` activates when those definitions reach 5% of the context window. Lower values activate sooner." |
| `false` | "Tool search is off. All tool definitions are loaded into context on every turn." |

N is a **percentage of the model's context window**, not a token count or tool count. This is a trap: on
a 1M-token context (e.g. some Sonnet configs), `auto:5` = 50,000 tokens, so a 40k-token deferrable set
would NOT trigger deferral and everything loads upfront anyway — confirmed empirically below.

Also load-bearing: "the SDK counts every definition that tool search can defer toward one combined
threshold: each MCP tool that isn't marked `alwaysLoad`... plus built-in tools that load on demand. The
SDK always loads core built-in tools such as Bash, Read, and Edit upfront and doesn't count them."

Gotcha found in docs: **"The SDK also disables tool search when `ANTHROPIC_BASE_URL` points to a
non-first-party host, since most proxies don't forward `tool_reference` blocks."** — anyone routing
through a local logging/measurement proxy (e.g. for `/context`-style introspection) silently loses tool
search unless they set `ENABLE_TOOL_SEARCH=true` explicitly, which then risks breaking on proxies that
don't support `tool_reference`.

**GitHub issue evidence** — [anthropics/claude-code#40314](https://github.com/anthropics/claude-code/issues/40314)
(closed as not planned, no maintainer technical reply in visible content):

> "`ENABLE_TOOL_SEARCH` does not defer tools from HTTP transport MCP servers. All ~250 tool schemas are
> loaded inline into context on every session, consuming 120K tokens (60% of Sonnet 200K context) before
> the first user message."
> Without gateway: "MCP tools: 290 tokens (0.1%) / Total context: 34k/200k (17%)"
> With HTTP MCP gateway: "MCP tools: 120.2k tokens (60.1%) / Total context: 155k/200k (77%)"
> Setting used: `{ "env": { "ENABLE_TOOL_SEARCH": "auto:5" } }`, confirmed present via `env | grep ENABLE`.
> "HTTP/Streamable HTTP MCP tools should be deferred behind ToolSearch the same way stdio MCP tools are."

This is directly relevant to persona-engine's setup: **it has many HTTP-transport MCP servers** (all the
`claude_ai_*` connectors — Gmail, Linear, Slack, Notion, Braze, etc. — plus `pf3-mcp`, `circleci`,
`claude-in-chrome`). If any of those are HTTP/Streamable-HTTP transport (the `claude_ai_*` ones almost
certainly are, since they're OAuth-backed cloud connectors), **issue #40314's bug may directly explain why
115.3k tokens of MCP tool defs are NOT being deferred** despite tool search nominally being on. This is
UNVERIFIED for persona-engine specifically — needs a live `/context` check with `ENABLE_TOOL_SEARCH=auto:1`
or `true` forced, and checking whether the HTTP-transport servers' tools shrink.

**Empirical measurement** — [dev.to: "Tool search hid 40,170 tokens... auto:5 put them all back"](https://dev.to/rulestack/tool-search-hid-40170-tokens-from-our-first-request-auto5-put-them-all-back-2jin):

> First-request input tokens: default (unset) 20,819 / `ENABLE_TOOL_SEARCH=false` 60,989 /
> `ENABLE_TOOL_SEARCH=auto:5` 62,319 (i.e. `auto:5` behaved almost identically to `false` — it loaded
> everything upfront).
> "the difference between default and `false`... equals approximately 40,170 tokens representing 88
> deferred tool definitions."
> Root cause: "On this machine's 1M-token context, 5% equals 50,000 tokens. Since the 40,000-token
> definition set fell under this threshold, `auto:5` loaded everything upfront." — i.e. `auto:5` is a
> **weaker** deferral setting than leaving it unset (which uses the true default, effectively acting like
> `auto:0`-ish / always-defer) on large-context models. **Actionable trap: setting `auto:N` explicitly can
> make things WORSE than leaving the variable unset.**

**Verdict for persona-engine**: leave `ENABLE_TOOL_SEARCH` unset (the true default already defers
maximally); do NOT set `auto:5` per the CODE-INTEL-BOTH-01-style advice floating around blogs — it can
backfire on large context windows. The 115.3k MCP figure most likely means either (a) tool search isn't
actually engaging for the HTTP-transport connectors (per #40314), or (b) `alwaysLoad`/non-deferred tools
dominate, or (c) the `/context` number already reflects post-search-discovery expansion from a long
session. Needs a fresh-session `/context` check to disambiguate — not done here (out of scope: this is
external research, not a live repo audit).

---

## 2. Disabling an MCP server per-project without deleting it

Primary source — [Claude Code settings-reference docs](https://code.claude.com/docs/en/settings-reference) (fetched directly):

- **`disabledMcpjsonServers`** — "Reject specific servers from a project's `.mcp.json`" (any settings file)
- **`enabledMcpjsonServers`** — "Approve specific servers from a project's `.mcp.json`" (any settings file)
- **`enableAllProjectMcpServers`** — "Approve every server in project `.mcp.json` files without a prompt"

Example shape (from secondary source, consistent with docs):
```json
{
  "enableAllProjectMcpServers": false,
  "enabledMcpjsonServers": ["shopify", "github"],
  "disabledMcpjsonServers": ["filesystem"]
}
```
These live in `.claude/settings.json` (project) or `~/.claude/settings.json` (user), NOT in `.mcp.json`
itself — `.mcp.json` only defines servers; these keys gate which of them actually start.

**CLI flag**: `--strict-mcp-config` — "tells Claude to use only the servers passed with `--mcp-config`
and ignore every other MCP configuration." Combined with an empty config: `claude --strict-mcp-config
--mcp-config '{}'` disables all MCP servers for that invocation.
[Known bug] — [anthropics/claude-code#14490](https://github.com/anthropics/claude-code/issues/14490):
`--strict-mcp-config` does not override the `disabledMcpServers` list stored in `~/.claude.json`
(a *different* per-user-per-project store from `.claude/settings.json`'s `disabledMcpjsonServers` — note
the naming collision: `disabledMcpServers` vs `disabledMcpjsonServers` are two different keys in two
different files).

**Trust-dialog gotcha** — one source claims: "As of v2.1.196, `claude mcp list` and `claude mcp get` read
`.mcp.json` approvals from checked-in settings files only after you run `claude` interactively in the
workspace and accept the trust dialog. Until then, `enableAllProjectMcpServers` and
`enabledMcpjsonServers` values committed to the project's `.claude/settings.json` are ignored." —
UNVERIFIED against primary source (blog claim only), but consistent with the general "project MCP
approval" security model Anthropic documents at `/docs/en/mcp#project-server-approvals-and-workspace-trust`.

**Feature requests still open** (i.e. NOT yet supported):
- [#20873](https://github.com/anthropics/claude-code/issues/20873) "CLI flags to disable MCP, plugins,
  and agents (`--no-mcp`, `--no-plugins`, `--no-agents`)" — open, meaning no single flag exists to nuke
  all MCP servers at CLI level other than the `--strict-mcp-config --mcp-config '{}'` combo above.
- [#44845](https://github.com/anthropics/claude-code/issues/44845) "Global `disabledMcpServers` support
  (user-level, not just per-project)" — open, meaning today disabling is project-scoped only via
  `disabledMcpjsonServers`; there's no one user-level switch to disable a server across all projects
  short of removing it from every `.mcp.json` / global MCP config.
- [#22301](https://github.com/anthropics/claude-code/issues/22301) "Add setting to disable cloud MCP
  connectors from claude.ai" — open. **This is exactly persona-engine's situation**: the large
  `claude_ai_*` block (Gmail, Slack, Linear, Notion, Braze, Figma, Atlassian, Stripe, Supermetrics,
  monday.com, Krisp, Granola, Google Calendar/Drive, SEON) is almost certainly injected by a claude.ai
  account-level connector registration, NOT by this repo's own `.mcp.json`. If so, **`disabledMcpjsonServers`
  in this project's settings.json may not even apply to them** — they may not be "project MCP servers"
  in the sense the docs describes. UNVERIFIED — worth testing: add all `claude_ai_*` names to
  `disabledMcpjsonServers` and re-check `/context`; if unchanged, the disable path for these specific
  servers likely doesn't exist yet (per #22301) and the only lever is deactivating the connector in the
  claude.ai account settings (outside Claude Code entirely).

---

## 3. Skills — what controls listing visibility

Primary sources: [Claude Code skills docs](https://code.claude.com/docs/en/skills) + corroborating blogs.

- **`display: false`** in a skill's YAML frontmatter — "hide a skill from the `/` menu — the skill
  becomes background knowledge only, intended for agent preloading." This is the closest thing to "keep
  installed but hidden from the listing," though it still costs the frontmatter tokens at session start
  per the token-cost findings below (it's hidden from the `/` slash-command menu, not necessarily from
  the model's tool/skill catalogue used by auto-invocation — the two "listings" are different surfaces;
  this distinction is UNVERIFIED at the token-cost level and should be treated cautiously).
- **`disable-model-invocation: true`** in frontmatter — stops Claude auto-invoking it; "the skill is
  still registered and can be called explicitly." Does NOT remove it from context cost.
- **`skillOverrides`** (installation-level, doesn't require forking the skill file): setting a skill to
  `"off"` — "hides it everywhere — it's not listed to Claude, not in the `/` menu, and invoking it
  directly returns the skillOverrides error instead of running." This is the strongest lever: `off` in
  `skillOverrides` is confirmed (by the same source) to remove BOTH the model-visible listing AND the
  `/` menu entry, which should also remove its frontmatter tokens from the session-start prompt. UNVERIFIED
  primary-source confirmation (this came from a secondary "getclaudeskills.com" blog, not code.claude.com
  docs) — the official docs page didn one search) 
- **Settings-level bulk kill**: `disableBundledSkills` (settings.json key, confirmed in primary docs
  fetch) — "Turn off the skills and workflows included with Claude Code" — i.e. **this only removes
  Anthropic's own bundled catalogue** (dataviz, review, init, etc.), not project-local or plugin skills
  like the ~150 `leadv2:*` / `vercel:*` / `slack:*` skills seen in this session's listing. Confirmed
  wording differs slightly from a blog's claim ("removes... the dataviz, review, init catalogue") — the
  official doc text bundles skills+workflows together under one flag, contradicting the blog's separate
  `disableWorkflows` framing; **`disableWorkflows`** IS separately confirmed in the primary fetch as its
  own key: "Turn dynamic workflows off for everyone; use `enableWorkflows` for yourself."

**Token cost of the skill listing itself** — [DEV: "Skills Cost Tokens Even When They Don't Fire"](https://dev.to/kenimo49/claude-code-skills-cost-tokens-even-when-they-dont-fire-i-measured-5-skills-across-7-hours-the-8jo)
and corroborating sources:
> "At startup Claude reads only the YAML frontmatter, roughly 60 tokens of name and description per
> Skill" — one source; another says "roughly 100 tokens per skill, regardless of how large the skill
> itself is." "a project with eight Skills costs about 500 tokens at startup, where loading every body
> up front would cost around 70,000."

Given persona-engine's listing shows on the order of ~150 skills (built-in + `leadv2:*` + `vercel:*` +
`slack:*` + `codex:*` families), at 60-100 tokens each that lands at **9,000-15,000 tokens** — this
matches the measured 16k figure closely and confirms the skill listing itself (not skill bodies) is the
whole cost. **The single biggest skill-side lever is reducing the number of INSTALLED skill-providing
plugins** (vercel's ~35 skills and slack's ~9 skills are plugins likely irrelevant to a Python/Supabase
backend project) rather than fighting frontmatter size, since it's a flat per-skill tax regardless of
body length.

---

## 4. Memory / CLAUDE.md conditional loading (`.claude/rules/*.md` with `paths:`)

**Feature exists** (multiple corroborating sources) but is **buggy as of the versions tested**:

- [anthropics/claude-code#22170](https://github.com/anthropics/claude-code/issues/22170) — "paths field
  in `~/.claude/rules/` frontmatter not working - rules with paths are not loaded." Version affected:
  **2.1.27**, macOS. Quoted test table from the issue: a rule file with `paths:` frontmatter never loads;
  the SAME file loads fine when the `paths:` key is commented out. Status: **closed as duplicate**, no
  visible maintainer reply confirming a fix version.
- [anthropics/claude-code#16299](https://github.com/anthropics/claude-code/issues/16299) — "[BUG]
  Path-scoped rules in `.claude/rules/` load into context globally regardless of `paths:` frontmatter" —
  i.e. the opposite failure mode (everything loads unconditionally, defeating the entire point of
  path-scoping for context reduction).
- [anthropics/claude-code#23478](https://github.com/anthropics/claude-code/issues/23478) — "Path-based
  rules... are not loaded on Write tool — only on Read" — a narrower bug: even when path-scoping works,
  it only triggers on Read, not Write/Edit, so a rule meant to apply "whenever you touch `*.sql`" won't
  fire if Claude creates a new SQL file without reading an existing one first.

Net: **`.claude/rules/*.md` with `paths:` is the documented mechanism for conditional/path-scoped memory
loading**, syntax:
```yaml
---
paths:
  - "**/*.ts"
  - "src/**/*"
---
```
— but as of the versions in these three open/duplicate-closed issues, it is **not reliable** for the
purpose of reducing the ALWAYS-loaded memory floor: files without `paths:` load unconditionally at the
same priority as root `CLAUDE.md`, and files WITH `paths:` have had bugs in three different directions
(never loads, always loads anyway, or only loads on Read not Write). **Cannot be recommended today as a
dependable lever to shrink the 28.2k memory floor** without live-testing on the exact installed Claude
Code version first (`claude --version`, not captured in this research — out of scope for external
research). One source suggests a verification method: run `/memory` to check whether a rule is actually
in the loaded list before trusting the `paths:` scoping.

**Issues #90449 and #87217** (asked for by name in the task): **could not locate either issue via search
or direct guess** — GitHub search for these exact numbers returned no matching results in this session
(searches only surfaced unrelated issues/PRs, and a direct fetch was not attempted per-issue since no
URL could be confirmed to exist). **UNVERIFIED / NOT FOUND.** These issue numbers may be from a different
repo, may have been deleted/renumbered, or may not exist. Flagging rather than guessing.

**General CLAUDE.md/memory cost findings**:
- [Claude Code memory docs](https://code.claude.com/docs/en/memory) + corroborating blogs: CLAUDE.md and
  its `@path` imports "load into the context window at the start of every session... never lazy-loaded or
  evicted." A 5,000-token CLAUDE.md "costs 5,000 tokens on every single turn."
- `@path/to/file` imports: **still load their full content at session start** — "imported files load at
  launch without reducing context." Only a **plain path reference** (no `@`) defers reading: "A plain
  path pointer works differently—it tells Claude where the file lives without importing its contents at
  launch, and Claude reads the file later when the task needs it." **This is a real, immediately
  actionable lever**: any `@path` import inside CLAUDE.md that isn't needed on every single turn should
  become a plain markdown link/path reference instead (e.g. `docs/foo.md` prose mention, not `@docs/foo.md`).
- One blog reports a benchmark: 3,847-token CLAUDE.md → 312-token version = 91.9% reduction "with no
  quality regression," target guidance "under 200 lines per CLAUDE.md file."
- `/context` breakdown terminology (per [xda-developers](https://www.xda-developers.com/claude-code-using-fifty-thousand-tokens-before-typed-prompt-fixed-it/)
  and others): "Memory Files include your CLAUDE.md files (project and global) and the first 200 lines of
  your auto-memory index" — i.e. the auto-memory MEMORY.md topic index (as seen in this very session,
  the huge bulleted list of memory topic links) is capped at 200 lines but still counts fully toward the
  Memory Files bucket. **persona-engine's MEMORY.md is exactly this shape** — a ~100+ entry hub-and-link
  index. Given it's already near/at the 200-line cap, the lever here is pruning the index itself (fewer,
  more consolidated hub entries) rather than a config flag.

**Env vars relevant to memory** (from a GitHub gist inventory, cross-checked against official docs
naming conventions where possible):
- `CLAUDE_CODE_DISABLE_AUTO_MEMORY` — "Disable the automatic memory system; set to '0'/false to
  force-enable it" — this is the MEMORY.md auto-memory mechanism specifically.
- `CLAUDE_CODE_DISABLE_CLAUDE_MDS` — "Disable loading of CLAUDE.md instruction files (also forced on in
  safe mode)."
- `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` — loads CLAUDE.md from additional dirs.
These three are from a community gist (**secondary source, unverified against Anthropic's own env-var
reference page** — flagging accordingly), but internally consistent with the official settings-reference
page's confirmed `includeGitInstructions`/`disableBundledSkills` naming style, so plausibly accurate.

---

## 5. `github.com/rtk-ai/rtk` — what it actually does

Fetched directly: [`rtk/CLAUDE.md`](https://github.com/rtk-ai/rtk/blob/master/CLAUDE.md).

- Description: "a high-performance CLI proxy that minimizes LLM token consumption by filtering and
  compressing command outputs," reducing "bash output by 60-90% on common development operations through
  smart filtering, grouping, truncation, and deduplication."
- Hook mechanism: [dev.to/rulestack summary of a different rtk discussion] "Running `rtk init --global`
  installs a PreToolUse hook in Claude Code that automatically rewrites Bash commands to rtk equivalents
  at the proxy layer... RTK intercepts and compresses the output before it enters the context window."
- **Critical scoping fact, in rtk's own words**: "All percentages in this repo measure bash output, not
  your bill." And: "RTK ships no tokenizer (`src/core/tracking.rs` estimates tokens as `bytes / 4`), so
  the ratios are reliable but the absolute token counts are approximate."
- **Answering the task's direct question**: rtk reduces tokens a **tool RETURNS** (the stdout/stderr of
  bash commands you run — `git diff`, `npm test`, `find`, etc.), via output filtering/truncation/dedup.
  It does **NOT** touch tokens SENT as prompt/system-prompt/tool-definition overhead — it has no
  mechanism that could: it's a Bash-output-shaping PreToolUse hook, not a system-prompt or MCP-schema
  intercept. **It is therefore irrelevant to the 178.3k startup floor** (which is entirely prompt/schema
  overhead, before any Bash command has even run) — it would only help with the *conversation-growth*
  side (Bash/Read tool-result tokens accumulating turn over turn), which is a different problem from the
  one this research was scoped to.
- Real-world efficacy data point found separately: a Kilo-Org discussion claims "I saved 10M tokens (89%)"
  using an rtk-like CLI proxy — but a rebuttal/benchmark noted in the rtk-ai search results states
  "measured on real agent work showed +7.6% more expensive at low reasoning effort (p=0.004), ±0% at high
  effort" — i.e. **the advertised 60-90% figure did not replicate in an independent controlled benchmark**
  on end-to-end task cost; UNVERIFIED whose methodology is right, both are cited blog/discussion sources,
  not Anthropic-official.
- Install: `cargo install --path .` (also `cargo deb`, `cargo generate-rpm` packages mentioned; standard
  Rust binary install, single binary, zero dependencies, Apache-2.0, no API key/account).

**Verdict**: rtk is a real, working tool for a DIFFERENT problem (conversation-growth from noisy command
output) than the one asked about (fixed startup floor from tool-defs/memory/skills). Not a lever for the
178.3k number.

---

## 6. Other tool aggregators / gateways / dynamic-loading approaches

- **MetaMCP** — [github.com/metatool-ai/metamcp](https://github.com/metatool-ai/metamcp) — "MCP
  Aggregator, Orchestrator, Middleware, Gateway in one docker." Combines multiple MCP servers behind one
  endpoint with tool filtering. Generic MCP-protocol-level gateway — should work with any MCP client
  including Claude Code (since Claude Code just sees it as one more MCP server), but **no Claude-Code-
  specific integration notes found**; would require standing up and maintaining a Docker service.
  UNVERIFIED whether it's been run against Claude Code specifically by anyone in the sourced material.
- **Cloudflare "Code Mode"** (`portal_codemode_search` / `portal_codemode_execute`) — described in
  [focused.io: "Stop Eager-Loading MCP Tools Into the Context Window"](https://focused.io/lab/stop-eager-loading-mcp-tools):
  collapses N MCP servers/tools into exactly 2 meta-tools; the agent writes JS to search/invoke tools
  on demand instead of the client loading every schema. Concrete number quoted: "4 internal MCP servers
  exposing 52 tools would normally consume 9,400 tokens just for definitions. Code Mode drops that to
  600 tokens. A 94% reduction," and for Cloudflare's own full API surface, "99.9%... from over 2 million
  tokens." This is architecturally similar to Anthropic's own tool-search (deferred loading + on-demand
  discovery) but goes further by not even keeping N tool schemas resident — it's a code-execution
  sandbox pattern. **Not confirmed as a drop-in for Claude Code** (Cloudflare's own product, tied to their
  Workers/Agents platform) — would need custom MCP-server wrapping work to adopt here; flagged as an
  architecture pattern to imitate, not an installable fix.
- **Arcade "MCP Gateway" / LangSmith Fleet** — mentioned in the same focused.io piece: "centralizes
  7,500+ tools with optimized language-model-specific descriptions." Third-party hosted product,
  not evaluated for Claude Code compatibility in sourced material — UNVERIFIED.
- **Skills-as-lazy-tool-catalog pattern** — same article, concrete before/after numbers: "Browser
  automation: 13,600 → 2,000 tokens," "GitHub operations: 18,000 → 500 tokens," "Web search: 14,100 → 550
  tokens" — this is exactly the mechanism Claude Code's own Skills feature already implements (frontmatter
  now, body on invocation), so no separate tool is needed to get this benefit inside Claude Code — but it
  argues for converting **heavy always-loaded MCP tool surfaces into a thin Skill that shells out / calls
  the MCP tool only when invoked**, rather than keeping every MCP server registered and hoping tool-search
  defers it correctly (relevant given the #40314 HTTP-transport deferral bug above).
- **Baseline data point**: "One developer measured 67,300 tokens consumed before typing a single
  question. Seven MCP servers." (same article) — consistent with this project's own 115.3k for a larger
  connector set.

No dedicated "token-counting dashboard" product specific to Claude Code was found beyond Claude Code's
own built-in `/context` (and `/context all` for a fully expanded per-item breakdown) — this appears to be
the primary tool people actually use, per multiple independent blog sources describing it in detail.

---

## 7. Non-obvious env vars / flags / tricks

Collected from a community gist (secondary, cross-checked for internal consistency against the one
official settings-reference fetch) plus two blog investigations. Flagging provenance per item.

**Confirmed via official docs fetch (code.claude.com/docs/en/settings-reference), so PRIMARY:**
- `includeGitInstructions` (settings.json) — "Remove the built-in commit and PR instructions from the
  system prompt" — direct, documented lever on the "system prompt" 3k bucket.
- `includeCoAuthoredBy` — "Deprecated; use `attribution` to hide or change commit and PR attribution."
- `disableBundledSkills`, `disableWorkflows`, `outputStyle`, `permissions.deny`, the three
  `*McpjsonServers` keys — all as quoted in sections 2-3 above.

**From a community gist (SECONDARY, unverified against Anthropic's own docs):**
- `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` — "forces the simple system prompt"; corroborated independently by
  a different blog: `CLAUDE_CODE_SIMPLE=1` "runs with a minimal system prompt and only the Bash, file
  read, and file edit tools; MCP tools from `--mcp-config` remain available, while auto-discovery of
  hooks, skills, plugins, MCP servers, auto memory... [is disabled]" (source text was truncated on
  fetch; treat the full scope claim as UNVERIFIED beyond what's quoted).
- `SLASH_COMMAND_TOOL_CHAR_BUDGET` — "Character budget for the slash-command tool listing."
- `CLAUDE_CODE_SKIP_PLUGIN_MCP_SERVERS` — "when set, plugin-provided MCP servers are not launched" —
  **directly relevant**: persona-engine's `leadv2`, `vercel`, `slack`, `codex` skill/tool families are
  plugin-provided; if any plugin also registers MCP servers (not just skills), this variable could shed
  MCP weight without touching `.mcp.json`.
- `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` (env-var form, distinct from the `disableBundledSkills`
  settings.json key, though likely equivalent) — "Hide bundled skills from the model (they stay typable);
  plugins, `.claude/skills` unaffected" — confirms bundled-skill disabling does NOT touch plugin skills
  (the ~150-skill listing here is almost entirely plugin skills, so this lever would NOT meaningfully
  shrink the measured 16k).
- `MAX_THINKING_TOKENS=0`, `CLAUDE_CODE_ATTRIBUTION_HEADER=0` (improves cache hit rate per one source).

**Empirical flag combo** — [mykolaaleksandrov.dev investigation](https://www.mykolaaleksandrov.dev/posts/2026/06/claude-code-huge-prompt-investigation/),
measured with a local logging proxy (`ANTHROPIC_BASE_URL=http://localhost:8787`):
> Baseline request: 130,971 bytes (~28,856 tokens) for a "7+5" prompt; tool definitions alone: 94,028
> bytes (~23,393 tokens, 81% of payload).
> `claude --tools "Read,Glob,Grep,PowerShell" --strict-mcp-config --disallowedTools "mcp__*"` → 34,821
> bytes, a **73.4% reduction**.
> Daily-coding profile `claude --tools "Read,Write,Edit,Glob,Grep,PowerShell,TodoWrite" --strict-mcp-config
> --disallowedTools "mcp__*"` → 61.5% reduction.
> Explicit finding: "`/clear` did not fix it" — `/clear` only wipes conversation history, not the
> per-turn tool/system-prompt contract.

**Note on `--tools` flag**: this is the first evidence found of a CLI flag that does an **allowlist**
of tools by name (rather than only denylisting via `permissions.deny` or `disallowedTools`) — if accurate
and current, `claude --tools "Read,Edit,Bash,Grep,Glob,TodoWrite" --strict-mcp-config` (or equivalent in
settings.json, if such a key exists) would be the single highest-leverage lever available, since it
would suppress ALL MCP tool schemas AND all non-core built-in tool schemas in one shot. **UNVERIFIED
against official docs** — could not find `--tools` documented on code.claude.com's CLI reference in this
research pass; flagging as promising but needs a live version check (`claude --help`) before relying on it,
since flag names/availability drift between CLI versions and this may be older/newer than what's
installed here.

**`permissions.deny` and tool-definition removal** — one blog (aihero.dev) claims: "a bare name
(`"NotebookEdit"`) removes the tool [definition]" while "a scoped rule (`"Bash(rm *)"`) blocks the
matching call but leaves the definition in the payload." This is **plausible but UNVERIFIED against
Anthropic's own docs** — the official settings-reference text for `permissions.deny` only says it
"Blocks listed tool uses," without explicitly stating whether a bare (unscoped) deny entry additionally
suppresses the tool's *schema* from the request (as opposed to merely refusing to execute it at
call-time). This distinction matters enormously for the 11.1k "system tools" bucket and deserves a live
test: add `"NotebookEdit"` (unscoped) to `permissions.deny` and diff `/context`'s system-tools number
before/after.

---

## Sources index (all links used above)

- https://github.com/anthropics/claude-code/issues/40314
- https://code.claude.com/docs/en/agent-sdk/tool-search
- https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool
- https://dev.to/rulestack/tool-search-hid-40170-tokens-from-our-first-request-auto5-put-them-all-back-2jin
- https://github.com/anthropics/claude-code/issues/24657
- https://code.claude.com/docs/en/mcp
- https://loadout.migsilva.dev/guides/disable-mcp-server-claude-code/
- https://github.com/anthropics/claude-code/issues/22301
- https://github.com/anthropics/claude-code/issues/20873
- https://github.com/anthropics/claude-code/issues/14490
- https://github.com/anthropics/claude-code/issues/44845
- https://code.claude.com/docs/en/managed-mcp
- https://code.claude.com/docs/en/skills
- https://github.com/anthropics/claude-code/issues/12633
- https://www.getclaudeskills.com/blog/claude-code-skilloverrides-setting
- https://www.developersdigest.tech/guides/disable-model-invocation
- https://github.com/rtk-ai/rtk
- https://github.com/rtk-ai/rtk/blob/master/CLAUDE.md
- https://github.com/Kilo-Org/kilocode/discussions/5848
- https://github.com/anthropics/claude-code/issues/22170
- https://github.com/anthropics/claude-code/issues/16299
- https://github.com/anthropics/claude-code/issues/23478
- https://code.claude.com/docs/en/memory
- https://medium.com/@cem.karaca/my-claude-md-was-eating-42-000-tokens-per-conversation-heres-how-i-fixed-it-85ffba809bd4
- https://www.xda-developers.com/claude-code-using-fifty-thousand-tokens-before-typed-prompt-fixed-it/
- https://code.claude.com/docs/en/settings-reference
- https://github.com/anthropics/claude-code/issues/47218
- https://github.com/anthropics/claude-code/issues/53259
- https://focused.io/lab/stop-eager-loading-mcp-tools
- https://github.com/metatool-ai/metamcp
- https://dev.to/kenimo49/claude-code-skills-cost-tokens-even-when-they-dont-fire-i-measured-5-skills-across-7-hours-the-8jo
- https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt
- https://gist.github.com/unkn0wncode/f87295d055dd0f0e8082358a0b5cc467
- https://www.mykolaaleksandrov.dev/posts/2026/06/claude-code-huge-prompt-investigation/

## Not found / could not verify

- GitHub issues #90449 and #87217 (asked for by number in the task) — no matching issues located via
  search in this session. Do not cite these numbers as confirmed bugs without a direct URL check.
- Whether `--tools` (allowlist) CLI flag exists in the currently-installed Claude Code version.
- Whether `permissions.deny` with a bare (unscoped) tool name actually strips the tool's JSON schema from
  the request, vs. only blocking execution.
- Whether persona-engine's `claude_ai_*` HTTP-transport connectors are subject to `disabledMcpjsonServers`
  at all, or are claude.ai-account-level and outside Claude Code's own MCP config surface entirely.
