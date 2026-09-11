# ANALYSIS-fable-apparatus — the apparatus we pay for and never invoke

Arm: fable (round 3). Question: is "skills/MCP reach neither lead nor subagents" systemic, and per
surface — improve / start using / retire.

Method: one pass over every transcript under `~/.claude/projects` (7,937 `.jsonl`, 997,357 lines,
120,449 `tool_use` blocks, 1,191 sessions, window **2026-08-25 → 2026-09-11**, 18 days), scripts
`/tmp/apparatus-scan.py` + `/tmp/apparatus-scan2.py`; subagent transcripts (`/subagents/` paths and
`isSidechain`) counted as `sub`. `history.db` opened `mode=ro&immutable=1` as a cross-check only
(its `tools_json` covers 12,039 turns, ~10% of the transcript volume — it is not the census source).
Carry cost = frontmatter `name+description` chars / 3.5 (`/tmp/apparatus-cost.py`).

## 0. Verdict in one paragraph

The founder is right about the *mechanism* and wrong about the *scope*. Skills and code-intel MCP
are effectively unused: 72 `Skill` calls and 79 code-intel MCP calls against 90,272 `Bash` calls in
18 days (0.06% and 0.07%). Agents are the opposite — 1,157 spawns, used constantly. The zeros split
three ways, and only one of the three is a "we never use it" zero:
**never reachable** (every headless lane runs with an empty MCP config; `repowise` is not on PATH;
`developer`/`recon` have no MCP tools in their frontmatter), **surfaced the wrong way** (24 of 41
plugin skills are `[internal]` phase docs that the lead reads with `cat`, so `Skill=0` measures the
wrong surface), and **beaten by `Bash`** (the estimation case, the code-intel mandate). Retire the
listing cost, not the capability: move `[internal]` skills out of the skill listing, uninstall the
Vercel plugin, dedupe the doubled leadv2 listing, defer MCP schemas, and fix the three wiring gaps
before judging the two code-intel servers by their call count.

## 1. Census — what is installed (not documented)

| surface | leadv2-repo session | persona-engine session | source |
|---|---:|---:|---|
| skills, leadv2 plugin | 41 (42 dirs, one without SKILL.md) | 41 | `plugins/leadv2/skills` |
| skills, user-level | 6 | 6 | `~/.claude/skills` |
| skills, other plugins | 50 (vercel 35, slack 8, codex 3, telegram 2, frontend-design 1, glm-plan-usage 1) | 50 | `~/.claude/plugins/cache` |
| skills, repo-level | 0 | **46** | `.claude/skills` |
| skills, built-in (dataviz, code-review, loop, …) | ~13 | ~13 | harness |
| **skills listed to the model** | **~110 (+9 duplicates)** | **~156 (+9 duplicates)** | this prompt |
| agent definitions | 5 repo (+3 plugin = same inode) | 10 | `.claude/agents` |
| agent types offered to Agent tool | 24 (incl. vercel:3, codex:1, leadv2:3 dupes) | — | this prompt |
| MCP servers, project | repowise | codebase-memory-mcp, reddit, repowise, shadcn | `.mcp.json` |
| MCP servers, user | codebase-memory-mcp, mempalace (fails to connect) | same | `~/.claude.json` |
| MCP servers, account connectors | Gmail 29 tools, Drive 11, Slack 19, Calendar (needs auth), Linear (seen in PE transcripts) | same | this prompt / transcripts |
| MCP servers, plugin | vercel (needs auth), slack, telegram, claude-mem `mcp-search`, sqz (spawn fails) | same | plugin `.mcp.json` |
| hooks, leadv2 plugin | 87 entries / 10 events (SessionStart 14, UserPromptSubmit 7, PreToolUse 36, PostToolUse 16, Stop 7, SubagentStop 1, PreCompact 2, PostCompact 2, CwdChanged 1, TaskCreated 1) | same | `hooks/hooks.json` |
| commands | plugin 2, repo 1, user 2 | — | `commands/` |

The leadv2 plugin is listed **twice**: `leadv2:leadv2-audit` and `leadv2-audit` (8 workflow skills
+ `leadv2` itself) appear as separate entries in the skill list, and `architect`/`leadv2:architect`
in the agent list. Same bytes, paid twice.

## 2. Invocation, per surface, 18 days, all sessions incl. subagents

| surface | main | sub | total | share of 120,449 | last |
|---|---:|---:|---:|---:|---|
| Bash | 60,023 | 30,249 | 90,272 | 75.0% | 09-11 |
| Read / Write / Edit | 14,239 | 8,333 | 22,572 | 18.7% | 09-11 |
| Agent | 1,093 | 64 | 1,157 | 0.96% | 09-11 |
| mcp__* (all servers) | 1,489 | 311 | 1,800 | 1.5% | 09-11 |
| — claude-in-chrome | ~1,220 | ~125 | ~1,345 | 1.1% | 09-11 |
| — snovio (getmany bot) | ~85 | ~110 | ~195 | | |
| — claude.ai Gmail / Slack / Linear | ~100 | 6 | ~106 | | |
| — **repowise** | 33 | 16 | **49** | 0.04% | 09-11 |
| — **codebase-memory-mcp** | 9 | 21 | **30** | 0.02% | 09-11 |
| ToolSearch | 495 | 80 | 575 | 0.5% | 09-11 |
| **Skill** | 66 | 6 | **72** | 0.06% | 09-11 |
| SKILL.md read via `cat`/`Read` (skill bypass) | ~70 | ~90 | ~160 | 0.13% | |
| Workflow | 3 | 0 | 3 | | 09-04 |
| `repowise distill` inside Bash | 37 | 1 | **38 of 90,272** | 0.04% | |
| Bash commands mentioning `estimat` | 435 | 92 | 527 | | |

Sessions with ≥1 MCP call: **51 / 1,191 (4.3%)**. Sessions with ≥1 Skill call: 52 / 1,191.
Code-intel calls happened on 13 of 18 days; by project: persona-engine 23 (20 from subagents),
getmany-followup-bot 29, leadv2 + its worktrees ~25.

**Skill calls by name (72):** `leadv2-founder-question-router` 37 (forced by the UserPromptSubmit
task-anchor hook, not chosen), `leadv2-judge` 9, `m3-deploy-access` 7, `leadv2` 4, then one each:
leadv2-deploy, leadv2-plan, leadv2-init, leadv2-build, codex:setup, workflow-authoring, init,
token-discipline, liveops-diag-v3, local-setup, artifact-design, codebase-memory, claude-in-chrome
×2, and one invented name (`leadv2-founder-question-classify.sh`). Organic (non-hook-forced) Skill
use ≈ 35 calls in 18 days across 1,191 sessions.
Coverage: leadv2 plugin **7 / 41** invoked; user skills 3 / 6 (`model-routing`,
`leadv2-output-style`, `chunk-sidecar` = 0); vercel **0 / 35**; slack skills 0 / 8 (Slack *MCP
tools* are used); persona-engine repo skills **0 / 46** invoked, 7 read once each by subagents.

**SKILL.md reads via Bash/Read (the real consumption path for `[internal]` skills):** judge 10,
deploy 9, close 8, fork-session 5, plan 5, review 4, **supervise 4 (retired 2026-08-17, still
read)**, init 2, llm-judge 2, lead-reflect 2, outcome-watch 2, subagent-protocol 2, plus 81
glob-reads (`skills/*/SKILL.md`).

**Agent spawns (1,157):** developer 187, devops-engineer 185, general-purpose 132, Explore 109,
critic 101, 04-go-developer 95, architect 64, recon 42, codex-rescue 28, fork 11,
security-auditor 5. `model=` omitted in **371 / 1,157 (32%)** despite the CLAUDE.md rule —
the `model-routing` skill that carries the rule was invoked 0 times.

## 3. Why the zeros — attribution with named cases

| cause | surfaces | evidence |
|---|---|---|
| **(a) never reachable** | MCP in every headless lane; `repowise distill`; MCP for `developer`/`recon`; mempalace, sqz; leadv2 workflow-skills | `plugins/leadv2/config/mcp-role-{architect,critic,default,developer}.json` all have `mcpServers: {}`, and `claude-subsession.sh:665` passes `--strict-mcp-config --mcp-config "$MCP_CFG"` → **0 MCP tools in any `claude -p` worker or reviewer**. `which repowise` → not found (distill unreachable from a child shell; the 38 successes ran elsewhere). `developer.md`/`recon.md` frontmatter: 0 `mcp__` tools; developer = 187 spawns. mempalace CONNECTION_CLOSED, sqz ENOENT this session. The 8 workflow-type skills are invoked only through the opt-in `Workflow` tool: 3 calls total. |
| **(b) loaded, never surfaced** | 24 `[internal]` leadv2 skills; persona-engine's 46 repo skills; vercel's 35 | `[internal]` skills are phase docs the `leadv2` command tells the lead to *read*; they show up as `cat …/SKILL.md` (judge 10, close 8 …), never as `Skill`. Their listing cost is paid for a routing that is never meant to fire. persona-engine repo skills: 0 Skill calls, 7 single reads. vercel: no Vercel deploy path in these repos (deploys go through `deploy-latest.sh`), its MCP needs auth. |
| **(c) beaten by a cheaper habit** | code-intel MCP for the lead; `repowise distill`; `model-routing`; the estimation skill | Lead's own tools: 60,023 Bash + 5,164 Read vs 42 code-intel calls in main sessions. `CLAUDE.md` says "first call for any how/where/why question" — it measurably does not route; the `Bash`+`grep` habit wins every time because it is one call with no schema to load. |
| **(d) obsolete — job moved to a script/hook** | `leadv2-supervise` (retired, still read 4×), `lead-classify` (→ inline + `leadv2-cost-estimate.sh`), `leadv2-loop-detection` (→ `leadv2-loop-detect` hook), `leadv2-bg-spawn-protocol` (→ hook), `leadv2-premortem`/`-deploy` (→ `leadv2-premortem.sh`, `leadv2-premortem-haiku.sh`), `leadv2-token-discipline` (→ user skill + CLAUDE.md) | dirs and scripts both exist; the skill entry is the residue. `plugins/leadv2/docs/phases.md:85` still says "Run `lead-classify` skill FIRST". |

Not resolved: whether the ~15 `[internal]` skills with neither a Skill call nor a `cat` in the
window (hack-detection, doubt-driven, iterative-recovery, memory-gc, negative-memory, priors,
rag-intake, signatures, correction-detect, recovery, verify, founder-input, persona-meeting,
briefing-freshness-monitor, browser-check) are consumed via the `leadv2` command's inline prose
(cause b) or simply dead (cause d). The transcript cannot distinguish "the lead followed §X" from
"the lead ignored §X". Treat as **unresolved**, not as retire.

## 4. The estimation case, by name

**Skill:** `lead-classify` — persona-engine `.claude/skills/lead-classify/SKILL.md`, description
"Formal task classification for the /lead orchestrator. Runs BEFORE any other work on a
non-trivial task." Added **2026-04-24** (`15bfe8fb2`, "feat: /leadv2 R5 + R6 — autonomous
orchestrator"), last touched 2026-04-30, **deleted 2026-05-19** (`934f5b4c5`, "housekeeping —
remove legacy leadv2 skill stubs").
**Invocations:** 0 `Skill` calls in the window (it no longer exists in persona-engine or the
plugin); 1 `Read` of a stale copy by a subagent. Stale copies still live in
`m3-market/.claude/skills/lead-classify`, `getmany-followup-bot/…`, `respiro-ios/…`.
**What does the job now:** inline classification in `plugins/leadv2/commands/leadv2.md:145`
("inline classification (Trivial/Light/Standard/Heavy) → scope-creep check → cost-estimate") +
`plugins/leadv2/scripts/leadv2-cost-estimate.sh` (added **2026-05-15**, `68368d91`, four days before
the skill was deleted; last change 2026-09-10; called from `leadv2-dispatch-code.sh` and
`lib/leadv2-phase-policy-path.sh`) + `leadv2-fanout-classify.sh` (2026-07-16). 527 Bash commands
in the window mention `estimat` — the script route is the live one.
**Verdict on the instance:** the founder's memory is exact. Skill → "stub" → script, with a dangling
doc reference left behind. It is the pattern for causes (c)+(d): the moment a decision needed to be
*enforced* rather than *suggested*, it became a script, because a skill cannot gate a dispatch and a
script can.

## 5. Cost of carrying, tokens per turn

| surface | leadv2 session | persona-engine session | how measured |
|---|---:|---:|---|
| MCP schemas, project + user servers, when loaded upfront | repowise 6,354 + cbm 2,415 = **8,769** | + reddit 926 + shadcn ~1,000 = **~10.7k** | BRIEF-03 `tools/list` |
| MCP schemas, account connectors (Gmail 29, Drive 11, Slack 19 tools) | **UNVERIFIED: ~15–20k** | same | present in full in this subsession's functions block; estimate from schema text length, no `tools/list` possible (remote OAuth) |
| MCP schemas when **deferred** | ~10 / tool name ≈ 1k for ~100 names | same | harness "deferred tools" notice |
| skill listing (always in system prompt) | user 615 + leadv2 2,956 + other plugins 4,293 (vercel 2,883) + dup ~700 = **~8.5k** | + repo 3,596 = **~12k** | chars/3.5 |
| agent-type listing | ~1k | ~1.5k | descriptions |
| agent body + subagent-protocol appendix, **per spawn** | ~2.3k (architect 8.1 KB) + ~6k protocol = **~8–9k × 1,157 spawns** | same | this prompt |
| hooks | 0 schema; fire-time text: task-anchor ~330 tok per founder prompt, SessionStart digest ~170, guard denials ~100–150 each | same | this session's injected text |
| commands | negligible | | |

Note on deferral: the reference session `fe5013c6` has **0** "deferred tools" notices (schemas
upfront, brief is right for that session), but **46 other persona-engine transcripts carry 88
notices listing `mcp__repowise__*` as deferred** — so "every turn of every persona-engine session"
is not what the corpus shows; see §7.

## 6. Verdicts, ranked by tokens-per-turn carried

| # | surface | carried/turn | invoked | zero cause | verdict |
|---|---|---:|---:|---|---|
| 1 | account connectors Gmail/Drive/Slack/Calendar/Linear | ~15–20k (UNVERIFIED) | 106 / 18 d, lead-only | — | **Keep, force deferral.** Largest carry in the stack and absent from BRIEF-03. They are never needed in a code lane; with `ENABLE_TOOL_SEARCH` back at the default they cost ~50 names. Unset `auto:50` (already decided) and verify with a "deferred tools" notice in a fresh persona-engine session. |
| 2 | **repowise** MCP | 6,354 upfront / ~110 deferred | 49 | (c) for lead, (a) for lanes | **Start using, narrowly; retire the mandate wording.** Trigger: any question the lead is about to answer with a `Read` >100 lines or a `grep` fan-out over ≥3 files — route to `get_context(include=[skeleton])` / `get_answer`. Today that question is absorbed by Bash+Read (65k calls). The `CLAUDE.md` sentence "first call for any how/where/why" has 49 data points against 90k; replace it with the one concrete trigger above and a PreToolUse nudge on `Read` without `limit`. Keep the index; it is cheap once deferred. |
| 3 | **codebase-memory-mcp** (graph) | 2,415 upfront / ~140 deferred | 30 (21 from critic/architect subagents) | (a)+(c) | **Keep, deferred — it is the only MCP subagents actually reach for.** The founder asked if the graph should stay: yes while reviews run in `leadv2`, because "who calls X" has no Bash equivalent that is not a false-zero grep. Retire it from persona-engine's `.mcp.json` only if deferral cannot be restored there. Fix the false-zero trap documented in `code-intel-routing.md` rather than the tool. |
| 4 | skill listing, vercel plugin (35) | 2,883 | 0 | (b) | **Retire: uninstall the plugin.** No repo deploys through Vercel; its MCP needs auth it never gets. Founder call only if a Vercel project exists outside the four repos. |
| 5 | skill listing, persona-engine repo (46) | 3,596 | 0 Skill, 7 single reads | (b)/(d) | **Retire ~39, keep 7.** Keep those read in the window (migrate, dashboard-po-walkthrough, dashboard-frontend-qa, library-api-verify, postgrest-upsert-validator, anthropic-caching, bash-scripting); move the rest to `docs/skills-archive/` (same bytes, no listing). |
| 6 | skill listing, leadv2 plugin (41) | 2,956 (+~700 dup) | 7 invoked + ~12 read | (b)+(d) | **Improve the shape, not the text.** (i) Move the 24 `[internal]` skills to `plugins/leadv2/docs/phases/` — they are read with `cat`, never `Skill`, so the listing buys nothing; the `leadv2` command keeps pointing at them by path. (ii) Delete `leadv2-supervise` (retired, still read 4×), `leadv2-loop-detection`, `leadv2-bg-spawn-protocol`, `leadv2-premortem`, `leadv2-premortem-deploy` (hooks/scripts own them). (iii) Dedupe the `leadv2:x` / `x` double listing (~700 tok). (iv) Fix `docs/phases.md:85` (`lead-classify`). Keep as real skills: leadv2, founder-question-router, judge, plan, build, review, deploy, close, init, fork-session, subagent-protocol, grilling, writing-great-skills. |
| 7 | user skills (6) | 615 | 3 | (c) | **`model-routing` → hook.** 32% of spawns omit `model=`; a skill cannot enforce, a PreToolUse on `Agent` can. Keep token-discipline, codebase-memory, liveops. Retire `leadv2-output-style` and `chunk-sidecar` if no session invoked them (0 in window). |
| 8 | agent definitions | ~1k listing, ~8–9k per spawn | 1,157 | — | **Not the problem.** One improvement: `developer`/`recon` frontmatter has no MCP tools while the repo's CLAUDE.md says index-first; either grant `mcp__repowise__get_context` to developer or stop telling it to route there. |
| 9 | `repowise distill` | 0 | 38 / 90,272 | (a) PATH | **Fix or drop the line.** Put `repowise` on PATH for child sessions (`claude-subsession.sh` env) or delete the CLAUDE.md instruction; a mandate that fails silently trains the habit of ignoring mandates. |
| 10 | headless-lane MCP (`mcp-role-*.json` = `{}`) | 0 | 0, by construction | (a) | **Decide explicitly.** Either populate `mcp-role-architect/critic.json` with repowise + graph (the roles whose subagents *do* call them when spawned via Agent tool: 21 graph calls), or remove the MCP tool lists from those agents' frontmatter so the prompt stops promising tools that are not there. A worktree `WORKER-MCP-ALL-ARMS-01` already exists — this decision belongs to it. |
| 11 | leadv2 workflow-skills (8, listed twice) | ~1.4k incl. dup | 3 Workflow calls | (a) opt-in gate | **Unresolved → dedupe now, judge later.** The `Workflow` tool is opt-in by design; zero here is policy, not neglect. |
| 12 | hooks (87) | 0 schema | fire constantly | — | **Keep.** Three fired in this session alone; they are the enforcement layer the skills lacked. |

Net if all "retire" rows land: **~7.5k tokens/turn** off the skill listing (vercel 2.9k + PE repo
~3k + leadv2 internal/dup ~1.6k) plus **~9k → ~1k** on MCP schemas once deferral is on. That is
larger than the whole code-intel bill and costs no capability.

## 7. The one BRIEF-03 number that did not survive

"**~10k tokens on every turn of every persona-engine session for zero MCP calls.**" Two of its
three parts fail: (1) *every session* — 46 persona-engine transcripts carry `mcp__repowise__*` in
the harness's deferred-tools list (88 notices), where the schema is not in context; the reference
session is the no-deferral case, not the population; (2) *zero MCP calls* — persona-engine sessions
made 23 code-intel calls in the window, 20 of them from subagents, which is where the brief's
main-transcript count cannot see. And where schemas are upfront, ~10k is an undercount because the
account connectors (59 tool schemas, present in this subsession's own functions block) are not in
the brief's `tools/list` sum (UNVERIFIED exact size). Every other reference-session number
reproduced exactly: Bash 2151, Write 218, SendMessage 205, Monitor 43, Agent 33, Edit 31, Read 14,
ToolSearch 11 all built-ins, mcp 0, distill 0.

## 8. Constraints honoured

Read-only on `~/.claude/burn/history.db` (uri `mode=ro&immutable=1`); `~/.claude/settings.json`
not read (MCP server names came from `~/.claude.json` and `.mcp.json`); no plugin edits, no code,
no installs; no other arm's file read; this is the only file written for the mission.
