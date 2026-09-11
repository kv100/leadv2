# Fixed session floor: verified controls and remaining uncertainty

The largest **sized, addressable** pool is the supplied **21,300-token memory category**. A compact instruction core with references loaded when needed is the first implementation candidate. The potentially larger opportunity is the **100,794-token interactive/headless difference**, but that difference is not yet an attribution to hooks, and it is not a savings measurement.

Research snapshot: **2026-09-11 UTC / 2026-09-12 Kyiv at final verification**. Local `claude --version` returned **2.1.269**; the fetched upstream changelog also ends at 2.1.269. Version claims below distinguish a documented introduction from a later reliability fix. Current documentation establishes supported behavior, not a successful local configuration experiment. No settings, permission files, other research arms, or private Claude memory contents were inspected; no runtime A/B, installation, or test suite was run.

**Decision:** pursue memory restructuring and bounded skill descriptions; size hook payloads before changing them. Preserve MCP deferral. Reject wholesale feature disabling and prompt replacement for the interactive lead. **Approximately 140k tokens is a provisional capability-preserving engineering target, not a proved floor.** The conditional budget below spans 135,216–143,216; no lower floor has been demonstrated by this research.

## 1. Baseline and accounting

The local measurement source is [the R1 mission](M3-R1-floor-levers.md), supplied by the lead:

| Measurement | Tokens | Interpretation |
|---|---:|---|
| Interactive first turn | 157,216 | Optimization denominator; no itemized interactive payload supplied |
| Headless first turn | 56,422 | Separate observation, not a capability-equivalent replacement |
| Difference | 100,794 | Unattributed difference, not automatically removable text |
| Headless `/context` | Approximately 41,300 | Haiku, 200k window; another measurement surface |
| Sum of six listed paid categories | 41,398 | Rounded categories reconcile with 41.3k |
| Headless first-turn usage minus that sum | 15,024 | Unreconciled; cannot silently assign this to hooks |

The 41.3k breakdown cannot be subtracted from 157,216 as though it were an interactive census. Model/tokenizer, window size, flags, launch mode, attachments, and measurement boundary must match. In particular, published pricing documentation notes a tokenizer change in Claude 4.7 and later; same text need not have the same token count across the models used here. [S12]

`/context all` expands the item breakdown in the current terminal UI. It is an inventory/diagnostic, not a billing ledger. The official configuration guide identifies these categories; the loading semantics below come from the corresponding feature references. [S2, S3, S4, S5, S6, S9]

| Category in the mission | Meaning | Paid context now? |
|---|---|---|
| System prompt: 6,300 | Core behavior and environment instructions; active prompt customization can contribute | Yes |
| System tools: 4,400 | Loaded built-in tool definitions/instructions | Yes |
| Custom agents: 898 | Available custom-subagent descriptions/catalog; not every agent's entire work transcript | Yes; do not treat full agent files as this category's size |
| Memory files: 21,300 | Loaded instruction/memory text, including CLAUDE.md and applicable rules/auto memory | Yes; not every byte in a memory directory |
| Skills: 6,000 | Skill discovery listing; invoked bodies additionally enter conversation | Yes for the loaded listing; unopened bodies are not all prepaid |
| Messages: 2,500 | Conversation, results, attachments/reminders, including applicable hook output | Yes |
| MCP tools **(deferred)**: 85,800 | Definitions available for later discovery, not currently expanded into model context | **No for those deferred definitions** |
| System tools **(deferred)**: 16,100 | Same deferred-definition distinction for built-ins | **No for those deferred definitions** |
| Free space / compaction reserve, if shown | Capacity or reserved headroom | Not input tokens merely because the UI displays it |

**Deferral is confirmed.** The API accepts full definitions marked `defer_loading: true` but initially exposes only the search tool and non-deferred definitions to the model. Discovered definitions become input tokens when expanded. Thus network payload bytes are not identical to paid model context. Claude Code still pays for discovery names and server instructions; “deferred” does not make the entire integration free. Do not claim an additional 101,900-token saving by removing the two deferred rows. [S4, S5]

The cost model is also narrower than “sum of context over turns.” For API billing:

`cost = Σ(input × input_rate + cache_write × write_rate + cache_read × read_rate + output × output_rate) + applicable service charges`.

For Haiku 4.5, current per-million prices are $1 input, $1.25 five-minute cache write, $2 one-hour write, $0.10 cache read, and $5 output. A warm read of 157,216 tokens therefore costs approximately **$0.01572**; writing that entire prefix costs approximately **$0.19652** or **$0.31443**, respectively. These illustrate API rates, not a conversion from Max subscription usage to dollars. Other models have different rates. The mission's 98.9% cache-read share is a supplied observation, not a newly verified monetary percentage. [S12]

## 2. Ranked savings budget

All savings are against 157,216, but are **estimates or unknowns**, not fresh local results. An estimate is explicitly a planning assumption. `Trial` means a named experiment is needed before adoption. Pools overlap: the memory rows share 21.3k; the skill rows share 6k; plugin and hook changes may affect several pools simultaneously.

| Rank among sized candidates | Lever | Planning saving | Residual if applied alone | Verdict |
|---|---|---:|---:|---|
| 1 | Memory core + conditional/reference retrieval, M1–M3 combined | **12,000–16,000** | 141,216–145,216 | Trial; preserve mandatory rules and verify retrieval |
| 2 | Concise skill discovery, S1/S2 alternatives | **2,000–4,000** | 153,216–155,216 | Trial; automatic selection is the risk |
| 3 | Remove duplicated built-in git guidance/status, P1 | **0–2,000** | 155,216–157,216 | Trial; keep local git contract |
| 4 | Shorter custom-agent descriptions, A1 | **0–700** | 156,516–157,216 | Trial; bounded by supplied 898 category |
| Unranked | Hook payload selection and duplicate prevention, H1/H2 | **Unknown** | Unknown | Highest-priority attribution trial; do not book the 100,794 gap |
| Unranked | Exclusions, directory scope, unused plugin removal | **Unknown; overlapping** | Unknown | Trial only where capability remains available |
| Zero additional saving | Preserve working tool deferral | **0** | 157,216 | Adopt existing behavior |
| Zero fixed-floor saving | Rewind, compact, clear, fresh session | **0** | Same configuration floor | Use for history management, not startup reduction |

The memory estimate assumes retaining **5.3–9.3k** of the supplied 21.3k as the always-present core. The skill estimate assumes retaining **2–4k** of the supplied 6k listing. Those are explicit design budgets, not byte-count conversions or published results for this repository. Combined M + S + P gives **135,216–143,216**; use **about 140k** for planning only if the corresponding interactive categories and capability checks support it. Do not also add agent, plugin, exclusion, and hook estimates without reconciling the resulting payload.

If the *entire* 100,794 difference were subsequently proven redundant and removed, then applying the same 14–22k sized budget to 56,422 would imply **34,422–42,422**. That is arithmetic for a hypothesis, **not a forecast or a no-capability-loss promise**. The largest possible opportunity may be interactive injections; the largest presently defensible sized lever is memory.

## 3. Memory levers

### Loading rules that matter

Ancestor CLAUDE.md/CLAUDE.local.md files load at launch; nested files load when their directory is read. `@` imports expand with their containing file: splitting text into imports alone saves nothing. Unscoped `.claude/rules/*.md` loads at launch; `paths` scopes rules to matching file reads. Documented syntax applies to rule files, **not a documented conditional switch on root CLAUDE.md or the auto-memory index**. Merely importing a file does not make it lazy. [S6]

Example location: `.claude/rules/api.md`:

```yaml
---
paths:
  - "src/api/**/*.ts"
  - "tests/api/**/*.{ts,tsx}"
---
```

Use actual repository paths when implementing; these patterns are illustrative. “First touched” is too vague: documented triggering is a matching **read**, not an assurance that any Bash edit, filename mention, or tool event activates the rule. Root requirements that govern planning before reads must remain unconditional. Loading later postpones cost; it does not guarantee the text disappears after leaving that file.

**Syntax minimum matters:** the YAML-list form above requires **2.1.84**, whose release notes explicitly add list-valued `paths` to rules and skills. Earlier conditional support is not proof that this exact syntax works. The v2.1.217 changelog mentions a CLAUDE.md/SKILL.md paths-parser fix, but does not establish that root CLAUDE.md becomes lazy; do not base savings on that extrapolation. [S1]

**Open issue caveats:** [#90449](https://github.com/anthropics/claude-code/issues/90449) reports native-`Read`-only activation on **2.1.250**, with shell reads, Grep, Glob, Write, and Edit failing to activate nested memory/path rules. It remains open with no comments; no corresponding later fix was located. [#87217](https://github.com/anthropics/claude-code/issues/87217) reports user-level `paths` disappearing on **2.1.233**, but a commenter supplies working **2.1.241** examples. It also remains open: **disputed/reported improved**, not confirmed broken on 2.1.269. Keep M1 project-scoped and explicitly validate native Read, shell/search, and new-file paths. [S32, S33]

Auto-memory's `~/.claude/projects/<project>/memory/MEMORY.md` loads at most its first 200 lines or 25KB, whichever comes first; topic files load on demand. Therefore the supplied 25,258-byte disk size is not the loaded token size. CLAUDE.md does not have that truncation rule. [S6]

| ID | Exact control / file path | Minimum version evidence | Saving and sizing experiment | What breaks | Verdict |
|---|---|---|---|---|---|
| M1 | Retain a short project `CLAUDE.md`; move file-specific detail to `.claude/rules/<topic>.md` with `paths` | Rules introduced **2.0.64**; headless loading fixed **2.1.69**; **2.1.84 minimum for the YAML list shown**; symlink trigger fix **2.1.198** [S1] | Part of combined **12–16k** memory budget. Compare fresh interactive payload before reads, then matching/nonmatching native Read and shell/search/new-file cases | Missed globs or missing activation omit instructions; **#90449 remains open**, #87217 is version-disputed. Eventually touching all domains can consume savings | **Trial**, never unconditional adoption |
| M2 | Short index at `~/.claude/projects/<project>/memory/MEMORY.md`; details in sibling topic files, with explicit retrieval cues | Auto memory **2.1.59**; shared repository/worktree memory **2.1.63** [S1] | Unknown individual contribution within M1–M3; compare the actually loaded index before/after and verify recall of a moved fact | Weak index labels impair retrieval; old details may never be requested | **Trial** |
| M3 | Replace duplicate explanations in project/user `CLAUDE.md` with one precise rule; place workflow bodies in `.claude/skills/<workflow>/SKILL.md` and reference material outside eagerly imported files | No dated minimum for prose deduplication; skills supported in current **2.1.269** docs [S9] | Part of **12–16k** combined budget, net of any new skill descriptions. Measure retained rule tokens and startup usage with the same task | Overcompression can delete exceptions or weaken the lead's operating contract | **Trial** |
| M4 | `claude --settings '{"claudeMdExcludes":["**/other-team/CLAUDE.md"]}'` for a future isolated probe | Introduction not established; documented now. Symlink exclusions via link path fixed **2.1.239** [S1, S7] | Unknown, bounded by loaded matching files; compare `/context all` file list and first request using one verified irrelevant file | Exclusion removes guidance entirely; managed policy cannot be excluded | **Trial** |
| M5 | `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` or `autoMemoryEnabled: false` | **2.1.59** auto-memory baseline [S1, S7] | Unknown; only the loaded auto-memory share, not all 21.3k | Loses automatic cross-session recall and recording | **Reject** for capability preservation; a diagnostic only |
| M6 | Split `CLAUDE.md` using `@docs/large-reference.md` without changing load conditions | Imports documented currently; exact introduction not established [S6] | **0**; content remains eagerly expanded | Adds organizational complexity without lowering floor | **Reject** as a token lever |

No edit to `~/.claude-work/CLAUDE.md` is proposed in this lane. If the retained-core budget cannot be met without changing that protected file or dropping a required instruction, the budget fails; it is not permission to widen scope.

**Published numbers:** issue [#33464](https://github.com/anthropics/claude-code/issues/33464) reports manually reducing instructions from approximately **15,600 to 2,800 tokens**. It supplies neither a controlled path-frontmatter experiment nor a capability regression result. The author's real [germinai-skills repository](https://github.com/Blaise-g/germinai-skills) reports a broader **35k → 13k** cleanup; its [Claude Code reference](https://github.com/Blaise-g/germinai-skills/blob/main/skills/drop-the-bloat/references/claude-code.md) favors concise non-obvious instructions and procedures in skills. Neither isolates the savings from `paths`. **No reproducible, isolated before/after measurement for `paths` alone was located.** These observations support trying a diet, not transplanting their percentage into 157,216. [S19, S20]

## 4. Skills: old bugs, current behavior, and usable controls

| Issue | Report and current state fetched from GitHub | Finding |
|---|---|---|
| [#50631](https://github.com/anthropics/claude-code/issues/50631) | v2.1.114 user/project overrides failed to change prompt listing; closed completed May 4 | Historical broken prompt-construction path; UI appearance was not proof |
| [#54996](https://github.com/anthropics/claude-code/issues/54996) | v2.1.123 `off` still listed/invocable; auto-closed May 4 as duplicate of #50631 | Historical failure; closure itself is not the fix evidence |
| [#56494](https://github.com/anthropics/claude-code/issues/56494) | Says v2.1.129 added working behavior; documentation issue closed May 10 after author verification | **Not a runtime-stub report**; the brief's grouping is wrong |

Upstream **v2.1.129 release notes explicitly announce working overrides**. Current docs agree. It is therefore wrong to label these modes currently broken on v2.1.269 based on those three issues. It would also be wrong to claim this repository's effective overrides have been tested. [S1, S9, S16–S18]

For non-plugin skills, use the canonical skill name:

| `skillOverrides` value | Model listing | User invocation |
|---|---|---|
| `on` | Name and description | Available |
| `name-only` | Name without description | Available |
| `user-invocable-only` | Hidden | Available |
| `off` | Hidden | Disabled |

**Plugin skills are outside `skillOverrides` scope.** User/project/local entries also do not resolve bundled aliases to canonical names. v2.1.260 adds alias handling only for managed/flag settings; use canonical names to avoid that boundary. These are current documented limitations, not evidence that the v2.1.129 fix was reverted. [S9]

| ID | Exact control / file path | Minimum version evidence | Saving and sizing experiment | What breaks | Verdict |
|---|---|---|---|---|---|
| S1 | `claude --settings '{"skillOverrides":{"<canonical-skill-name>":"name-only"}}'` | **2.1.129** [S1] | Target **2–4k** across applicable entries; maximum is selected descriptions, less residual names, within supplied 6k. Inspect actual listing and invoke a selected skill; do not ask the model to estimate its tokens | Loses automatic trigger detail; **plugin entries do nothing** under this control | **Trial**, current supported feature |
| S2 | `claude --settings '{"skillListingMaxDescChars":250,"skillListingBudgetFraction":0.002}'`; preferably edit owned descriptions to retain useful triggers first | **2.1.105** documented description-budget controls; current reference fetched [S7, S9]; historical changelog records the raised cap [S1] | Alternative **2–4k** planning saving; budget fraction corresponds to 2k at 1M, 400 at 200k, before accounting for retained names/formatting. Compare all skill sources and a routing sample; caps are not guarantees of exact token use | Truncated cues can make skills undiscoverable in practice; a fixed fraction behaves differently across windows | **Trial**; do not stack with S1 savings |
| S3 | Owned `SKILL.md` frontmatter `disable-model-invocation: true`; or non-plugin `skillOverrides` mode `user-invocable-only` | Frontmatter introduction not established; overrides **2.1.129** [S9, S1] | Unknown selected subset of 6k; compare listing with the chosen manual-only skills and verify explicit slash invocation | Automatic invocation removed; `user-invocable: false` is the opposite visibility direction and does not save the model listing | **Trial** only for workflows already manually triggered |
| S4 | `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` or `disableBundledSkills: true` | **2.1.169** [S1] | Unknown bundled portion of 6k; compare category and command inventory in an isolated session | Removes bundled skills/workflows; built-in commands remain typable but hidden from model. Custom/plugin skills remain. `/doctor` remains typable [S7] | **Reject** as a capability-neutral change |
| S5 | `skillOverrides: {"<skill>":"off"}` | **2.1.129**; remote/SDK command-list hiding **2.1.199** [S9] | Unknown selected portion of 6k; inspect both listing and invocation failure | Removes the capability; not just its description | **Reject** unless the skill is independently established as unnecessary |
| S6 | Owned skill `SKILL.md` `paths: ["src/api/**"]`, or place package-specific skills under `<package>/.claude/skills/` | YAML-list skill paths **2.1.84**; nested skill discovery **2.1.6** [S1, S9] | Unknown, overlapping 6k pool. Compare startup listing, first relevant file access, and explicit invocation before/after activation | Path activation does not by itself prove description savings; nested skills are unavailable before discovery, including slash invocation | **Trial**, not a replacement for universally needed skills |

A capability-preserving skill trial must retain workflow invocation **and** correct task-to-skill routing. Name-only mode preserves the first, not a guarantee of the second. Prefer short, discriminating descriptions for frequently needed skills. The 2–4k budget is conditional on that check.

## 5. Hook-output levers

Hook registrations are executable configuration, not 174 prepaid prompt bodies. On successful `SessionStart`/`UserPromptSubmit`, plain-text stdout can enter context; `additionalContext` enters as a reminder. Multiple matching outputs all arrive. Current docs cap individual output strings at 10,000 characters, spilling longer text to a file with preview/path. This is not a combined budget across 14 startup hooks. [S10]

Historical mid-session injections are saved and replayed on resume; past hooks are not rerun for those old turns. New events execute again. Once-injected text can be read from prompt cache on later requests, yet remains paid input. Reprinting identical text adds a new copy; cache reuse is not semantic deduplication. Earlier hook context is summarized by compaction, and matching `SessionStart` hooks can inject again afterward. [S10, S11, S13]

| ID | Exact control / file path | Minimum version evidence | Saving and sizing experiment | What breaks | Verdict |
|---|---|---|---|---|---|
| H1 | Reduce output emitted by existing `hooks.SessionStart` handlers in the registration source, including plugin `hooks/hooks.json`; return concise `hookSpecificOutput.additionalContext` and a retrieval pointer | SessionStart **1.0.62** [S1] | **Unknown** startup saving. Capture each handler's actual emitted text and the first request; subtract retained pointer/summary tokens. Count payload, not registrations | Missing branch/worktree/task information if indispensable facts are removed; handlers may have side effects distinct from output | **Trial**, priority attribution |
| H2 | Existing `hooks.UserPromptSubmit` task-anchor handler: emit on content change / missing retained anchor, keyed to session and context generation; scheduled-decisions injector: relevant rows plus source path | UserPromptSubmit **1.0.54**, JSON additional context **1.0.59** [S1]; dedup is custom handler behavior, not a native setting | **0 first-turn saving from dedup alone** if the initial anchor is unchanged; later savings depend on anchor size `A`. For `n` prompts without compaction and one model request per prompt, repeated copies contribute `A·n(n+1)/2` input versus `A·n` for one retained copy; extra tool requests increase rereads. Measure two identical prompts and one changed anchor, then clear/compact/resume | Session-only sentinels can suppress required reinjection after clear/compact or rewind; recency-only decision pruning can hide a binding decision | **Trial** |
| H3 | `once: true` on a hook entry declared in skill frontmatter | **2.1.0** [S1] | Unknown for a genuinely skill-scoped hook; compare two matching events after skill activation | Applies only to skill frontmatter; **ignored in settings and agent frontmatter**. Not a native fix for the existing settings task-anchor hook [S10] | **Reject** as a global-hook fix; trial only within an already appropriate skill |
| H4 | `claude --settings '{"disableAllHooks":true}'` | Introduction not established; current documented control [S7] | Unknown diagnostic delta. A future fresh read-only A/B could separate much of hook-added context, but also affects other surfaces | Disables operational hooks and some custom UI commands; managed exceptions remain; not equivalent functionality | **Reject** for normal lead use; diagnostic only |
| H5 | `suppressOutput: true` on a hook | Current docs identify a no-op [S10] | **0** verified semantics; not a context suppression switch | Creates false confidence while text still enters its normal channel | **Reject** |

For H2, the **design recommendation** is a small always-present invariant plus a recoverable task pointer; refresh the full current anchor when it changes or is no longer represented in retained context. `startup|clear|compact` is a useful SessionStart matcher for bootstrap/recovery; resume/fork need their own refresh decision. Do not move required pre-action guidance behind a hook that only runs after the action.

A real precedent exists in [neo4j-labs/meta-knowledge-graph](https://github.com/neo4j-labs/meta-knowledge-graph/blob/main/README.md): its documented injector skips identical prompt content already served to the session, accounts for clear/compact, and tracks served learning IDs. [Floop](https://github.com/nvandessel/floop/blob/main/docs/CLI_REFERENCE.md) documents atomic session-level injection deduplication. These establish implementable patterns, **not measured savings for leadv2 or a reason to install another memory system**. A new retrieval layer can add its own fixed listing and hook costs. [S21, S22]

## 6. System prompt, tool, plugin, and launch controls

`--append-system-prompt` adds text; it does not subtract the default. `--exclude-dynamic-system-prompt-sections` moves environment-specific material into the first user message for cross-session cache reuse; it does not delete it. A custom system prompt replaces defaults. Custom output styles omit coding guidance unless `keep-coding-instructions: true`; this changes engineering behavior, not just wording. [S8, S14, S15]

| ID | Exact control / file path | Minimum version evidence | Saving and sizing experiment | What breaks | Verdict |
|---|---|---|---|---|---|
| P1 | `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1` or `includeGitInstructions: false` | **2.1.69** introduced; **2.1.78** fixes status suppression [S1, S7] | **0–2k planning allowance**, including removed git-status snapshot and commit/PR guidance; compare actual system/tool blocks and account for any replacement text | Loses built-in git workflow instructions and initial repo status. Only acceptable if local mandatory guidance and an on-demand status check replace them | **Trial** |
| P2 | `.claude/output-styles/<style>.md`, `keep-coding-instructions: false`; select using `outputStyle` | Styles **1.0.81**; field **2.0.37**; plugin field support **2.1.94** [S1, S15] | Unknown subset of supplied 6.3k minus custom style; compare prompt sections at startup | Removes coding guidance and introduces style reminders. Keeping coding instructions avoids that removal and may increase floor | **Reject** for unchanged coding capability; specialized noncoding trial only |
| P3 | `claude -p --exclude-dynamic-system-prompt-sections ...` | **2.1.98** [S1, S8] | **Approximately 0 total-context reduction**; measure cross-session cache-write/read mix, not just system category | Print-mode scope; environment becomes lower-priority message context | **Reject** as interactive-floor lever; **trial** for headless cache reuse |
| P4 | Remove redundant launcher `--append-system-prompt` / `--append-system-prompt-file` text | Interactive append **1.0.51**; file support documented by **2.1.69** [S1, S8] | Unknown, exactly removed text less any replacement; compare launch arguments and resulting prompt without exposing credentials | Dropping unique operating instructions breaks workflow | **Trial** only after proving redundancy; adding an append flag is not a saving |
| P5 | `--system-prompt` / `--system-prompt-file`; Agent SDK minimal/custom prompt | File override present **1.0.55**; interactive file support documented by **2.1.69** [S1, S14] | Unknown portion of 6.3k and other defaults; headless 56,422 is not proof for this change | Replaces behavioral scaffolding; SDK launch/config semantics differ | **Reject** for capability-equivalent lead |
| T1 | Main CLI `--tools "Read,Grep,Glob,Bash"`; child `.claude/agents/<agent>.md` `tools: Read, Grep, Glob, Bash` | Interactive `--tools` **2.1.0**; cold-start filter fix **2.1.186**; agent-field introduction not established [S1, S8, S23] | Main saving unknown, at most applicable loaded-tool share of 4.4k; child-only restriction saves **0** of parent startup. Measure actual schemas | Removes tools; Bash still permits writes, so this example is not a read-only guarantee. CLI flag does not restrict MCP; agent allowlist semantics differ | **Reject** broad lead restriction; **trial** for specialized workers |
| A1 | Shorten `description` in `.claude/agents/<name>.md`, preserving task triggers and agent body | Introduction not established; documented in current **2.1.269** [S23] | **0–700** planning allowance from supplied 898 catalog, leaving at least approximately 198; compare catalog and representative routing | Worse agent selection if key discriminators disappear | **Trial** |
| T2 | Keep `ENABLE_TOOL_SEARCH` unset on this supported path; avoid `.mcp.json` `alwaysLoad: true` unless essential | Auto deferral **2.1.7**; `alwaysLoad` **2.1.121** [S1, S4] | **0 incremental** here; the mission's unset experiment changed only 2 tokens. Check loaded versus deferred definitions, not total available schemas | Deferral requires a supported provider path; server-required always-loaded tools may be intentional | **Adopt** existing deferral |
| T3 | Shorten owned MCP server `instructions`; preserve deferred tools and names | Exact introduction not established; current MCP docs [S4] | Unknown small loaded discovery share; inspect server instruction text and discovery success | Vague descriptions impair discovery despite intact tools | **Trial**; no 85.8k savings claim |
| D1 | Keep `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` unset unless extra directory instructions are needed; distinguish `--add-dir` from `permissions.additionalDirectories` | Extra-dir memory opt-in **2.1.20**; extra-dir skills automatic **2.1.32** [S1, S6, S24] | Unknown; default memory opt-out means often **0**. Compare the additional directory's loaded memory/skill inventory | `--add-dir` also loads skills/commands/agents; the permissions setting grants access only and does not load those extensions [S9]. Removing access removes capability | **Trial** for irrelevant extra memory; no permission-file edits in this lane |
| D2 | `claude plugin disable <id>@<marketplace> --scope local`, reversible with enable; `enabledPlugins` controls load state | Exact minimum for this scope option not established; documented in current **2.1.269** [S25] | Unknown union of that plugin's loaded skills/agents/hooks, not its deferred-schema total. Compare one plugin at a time | Removes all that plugin's active capabilities; dependencies may prevent disable | **Trial** only for duplicates/unneeded plugins; **reject** disabling leadv2 wholesale |
| D3 | `.claudeignore` | **No supported minimum established**; v2.1.132 failure reported in #56997 [S26] | **0 defensible saving** | Unsupported file can be silently ignored; it is not a memory-loading control | **Reject** |
| D4 | `--bare` or narrow `--setting-sources` | Bare **2.1.81**; omitted project-source lazy-rule leak fixed **2.1.211** [S1, S8] | Unknown large deletion of features; compare only as a diagnostic baseline | Bare disables hooks/auto memory and changes authentication/loading; setting-source changes can omit required controls and instructions | **Reject** as capability-equivalent optimization |
| D5 | `.gitignore` / `.ignore` as instruction or skill-load suppressors | Discovery stopped respecting gitignore for commands/agents/styles in **2.0.28** [S1] | **0 guaranteed startup saving** | File search filtering is not an instruction-loading contract | **Reject**; use explicit memory/skill controls |

Source inconsistency worth preserving: the current output-style page still says `/output-style` was removed, but the newer **2.1.269 changelog reintroduces it**. Use `outputStyle` or `/config` in repeatable instructions rather than infer nonexistence from that stale paragraph. [S1, S15]

No general system-prompt “lite but identical capability” switch was established. Neither disabling telemetry nor increasing the context window removes fixed text; a larger window can actually permit a larger proportional skill listing. Output verbosity, tool-output truncation, and delegating large reads address subsequent conversation growth, not the supplied startup denominator. [S7, S13]

## 7. Rewind, compact, clear, and fresh-session cost

Official docs explicitly confirm that **rewind retains the earlier prefix**, which can hit cache; compaction creates a summary request and a new conversation suffix. Both may retain the system prefix. Therefore “rewind is cheaper” is supported for removing disposable history without summarization, but “compaction destroys the entire cache” is false. Cache expiration, changed configuration, and later context rebuilding still matter. [S11]

Current checkpoint UI calls the relevant action **Restore conversation**, not “Delete.” Choose that action to preserve code. Restore-code options have different filesystem effects; summarization choices inside `/rewind` also incur model work. [S27]

Let `F = 157,216` unchanged startup context, `H` be current history beyond it, `R` retained history after rewind, `S` summary/reinjection context, `N` next new prompt, and `c/w/i/o` the applicable per-token read/write/input/output rates. Define `K(X)` as the actual mixture of cache read, cache write, and uncached billing for `X`; it is not necessarily all cache creation.

| Action | Immediate model cost | Next useful request, excluding ordinary response output | Fixed-floor saving | Lost capability/state; verdict; version |
|---|---|---|---:|---|
| `/rewind` → Restore conversation | No summarizer; local history selection | Warm case approximately `c(F+R) + K(N)`; expired/changed prefix costs more | **0** | Loses removed reasoning/state while preserving current files. **Adopt** for discarded branches; **2.0.0** rewind baseline [S1, S27] |
| `/compact` | A separate summary call over `F+H`, appended instruction, and generated summary: approximately `K(F+H) + K(instruction) + o·summary_output` | Approximately `cF + K(S+N)` when unchanged project context still hits cache | **0** | Summary can lose detail; retains continuation. **Adopt** at a needed continuity boundary, not on every small task; original minimum not established, current documented [S11, S13] |
| `/clear` | No conversation summarizer; startup hooks can have their own execution/service costs | `K(F_clear + N)`; unchanged prefix portions may cache-hit, changed startup context will not | **0** from configuration itself | Conversation forgotten; project memory reloaded. **Adopt** between unrelated tasks. Original minimum not established; current documented [S3, S11] |
| Exit and launch a fresh `claude` session | No conversation summarizer; startup hooks run | `K(F_fresh + N)`; cache reuse requires matching prefix within lifetime/scope, not merely the same repo | **0** from configuration itself | Prior conversation not present; launch/environment may differ. **Adopt** for a new task/configuration baseline; base CLI behavior [S8, S11] |

For a warm Haiku 4.5 example with `R=0`, rewind's old-prefix read is **$0.01572**, plus new prompt/output. For `/clear` or fresh start, the same prefix would range from that warm-read cost to **$0.19652** at a full five-minute write, or **$0.31443** at a full one-hour write, before new prompt/output/hooks. These are explicit all-hit/all-write scenarios, not promises that every fresh session is cold. Compaction additionally reads current history and generates a summary; without `H`, summary length, model, TTL, and actual usage, an exact price would be fabricated. [S12]

## 8. Is an official fix coming?

Issue [#46526](https://github.com/anthropics/claude-code/issues/46526) is **closed as duplicate**, not a fix announcement. Its comments are automated duplicate/lock notices, with no human maintainer commitment. The chain is **#46526 → #46339 → #45188**. The last is closed **not planned**, following inactivity; that is not proof Anthropic rejects all token-efficiency work. No shipping milestone or forthcoming comprehensive floor fix was found in this chain. [S28–S30]

The chain also contains conflicting community attribution. #45188 reports a large first-cache increase; a commenter reports unchanged base system/tool bytes on a smaller setup. #46339 originally asks the model to estimate prompt size, which is not billing evidence. These reports justify controlled measurement, not attributing this repository's entire gap to an Anthropic regression.

**Specific fixes already shipped:** working skill overrides (2.1.129), bundled-skill disabling (2.1.169), resume/cache fixes, and recent tool-list stability changes (2.1.267–268). This repository's installed version is already newer. Adopt supported controls before considering a third-party request-rewriting interceptor. There is no evidence here that waiting for a promised fix will remove 100k tokens, nor a reason to install a historical workaround for the pre-2.1.129 stub. [S1]

The real community [token-optimization guide](https://github.com/leogallego/claude-skills-tokens/blob/main/reports/claude-code-token-optimization-guide.md) says skill descriptions are dropped after compaction and treats CLAUDE.md editing as immediate cache invalidation. Those blanket claims are wrong for current documented behavior: startup context is reinstated and CLAUDE.md changes take effect at reload boundaries. No blog or community percentage overrides the official loading/cache contract. [S31, S11, S13]

## 9. Acceptance experiment for the implementation round

This is a proposed bounded experiment, not work executed in this analysis lane:

1. Pin v2.1.269, exact model, effort, window, working directory, first prompt, environment/launch mode, and plugin set. Capture one **fresh interactive** baseline with `/context all` and its first model-request usage. Repeat three times to detect startup nondeterminism. Keep provider requests attributable by request/message ID so streamed chunks are not counted repeatedly.
2. Record `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` for each unique model request. Retain separate counters and monetary rates. Record headless independently; do not equate its `/context` estimate with interactive billed usage. Inspect payload component sizes without collecting secrets.
3. Attribute the 100,794 gap before adopting a removal: memory/listings versus emitted hook text versus launch/system differences. Record hook **outputs**, event/source, and whether each body was actually in the request. A registration count and an on-disk byte count are not sufficient.
4. Change one lever per variant, using reversible per-session overrides where applicable. For memory, verify matching/nonmatching reads and retrieval of moved facts. For skills, verify both explicit invocation and representative automatic selection. For hooks, exercise unchanged/changed task anchors and clear/compact/resume/rewind recovery.
5. Accept a lever only when its paid-input delta is visible and every required operating instruction, workflow, and recovery path remains available at the right time. Then run the combined variant to eliminate overlap. Keep headless and interactive results separate.

**Closure threshold:** a startup reduction alone cannot establish “without losing a capability.” If the 140k target requires removing mandatory context or breaks retrieval/routing, retain that context and report the higher measured floor. The only baseline currently established by the mission remains **157,216**.

## Sources

All sources below were fetched on 2026-09-11 UTC, with final checks after midnight in Kyiv. Official live pages generally omit a publication date; versions are attributed to release notes where available. GitHub issues are primary evidence of reports and discussion, not independent proof of the reported implementation diagnosis.

| ID | Publisher / source | Evidence used |
|---|---|---|
| S1 | Anthropic, [Claude Code changelog, pinned snapshot](https://github.com/anthropics/claude-code/blob/df52d04a4e65195c1621fe6222e0564bcccb1804/CHANGELOG.md), snapshot commit 2026-09-11 | Versions and shipped fixes; fetched raw changelog |
| S2 | Anthropic, [Debug your configuration](https://code.claude.com/docs/en/debug-your-config) | Context categories |
| S3 | Anthropic, [Commands](https://code.claude.com/docs/en/commands) | `/context all`, clear/compact behavior |
| S4 | Anthropic, [MCP](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search) | Deferred schemas, names/instructions, alwaysLoad |
| S5 | Anthropic, [Tool search tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool) | Definitions enter input accounting upon discovery/expansion; fetched primary HTML |
| S6 | Anthropic, [Memory](https://code.claude.com/docs/en/memory) | File loading, paths, auto-memory limit |
| S7 | Anthropic, [Settings reference](https://code.claude.com/docs/en/settings-reference) | Bundled skills, budgets, git instructions, exclusions, hooks; fetched full primary HTML when web reader size limit prevented parsing |
| S8 | Anthropic, [CLI reference](https://code.claude.com/docs/en/cli-reference) | Prompt, tools, bare, launch flags |
| S9 | Anthropic, [Skills](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings) | Override modes, plugin exception, aliases, invocation |
| S10 | Anthropic, [Hooks reference](https://code.claude.com/docs/en/hooks) | Context injection, output caps, replay, once/suppressOutput scope |
| S11 | Anthropic, [Prompt caching](https://code.claude.com/docs/en/prompt-caching) | Prefix matching, rewind/compact and reload behavior |
| S12 | Anthropic, [Pricing](https://platform.claude.com/docs/en/about-claude/pricing) | Haiku prices, model-specific rates/tokenization; fetched primary HTML |
| S13 | Anthropic, [Context window](https://code.claude.com/docs/en/context-window) | Compaction/reinjection lifecycle |
| S14 | Anthropic, [Modifying system prompts](https://code.claude.com/docs/en/agent-sdk/modifying-system-prompts) | SDK versus CLI and dynamic-section relocation |
| S15 | Anthropic, [Output styles](https://code.claude.com/docs/en/output-styles) | Coding-instruction removal and current documentation lag |
| S16 | anthropics/claude-code, [#50631](https://github.com/anthropics/claude-code/issues/50631), opened 2026-04-19 | v2.1.114 failure; issue and all API comments fetched |
| S17 | anthropics/claude-code, [#54996](https://github.com/anthropics/claude-code/issues/54996), reported v2.1.123 | Duplicate failure; issue and all API comments fetched |
| S18 | anthropics/claude-code, [#56494](https://github.com/anthropics/claude-code/issues/56494), opened 2026-05-06 | Working v2.1.129/docs correction; issue and all API comments fetched |
| S19 | anthropics/claude-code, [#33464](https://github.com/anthropics/claude-code/issues/33464), opened 2026-03-12 | Self-reported 15.6k→2.8k instruction compression |
| S20 | Blaise-g, [germinai-skills README](https://github.com/Blaise-g/germinai-skills/blob/main/README.md) and [Claude Code reference](https://github.com/Blaise-g/germinai-skills/blob/main/skills/drop-the-bloat/references/claude-code.md) | Author's 2026-08-04 35k→13k field report and actual recommendations |
| S21 | Neo4j Labs, [meta-knowledge-graph README](https://github.com/neo4j-labs/meta-knowledge-graph/blob/main/README.md) | Session/content dedup design, recovery boundaries |
| S22 | nvandessel, [Floop CLI reference](https://github.com/nvandessel/floop/blob/main/docs/CLI_REFERENCE.md) | Atomic injection dedup precedent |
| S23 | Anthropic, [Subagents](https://code.claude.com/docs/en/sub-agents) | Agent catalog, tools fields, parent/child boundary |
| S24 | Anthropic, [Environment variables](https://code.claude.com/docs/en/env-vars) | Additional-directory memory opt-in |
| S25 | Anthropic, [Plugins reference](https://code.claude.com/docs/en/plugins-reference#plugin-disable) | Disable/enable scopes and dependencies |
| S26 | anthropics/claude-code, [#56997](https://github.com/anthropics/claude-code/issues/56997), opened 2026-05-07; [#579](https://github.com/anthropics/claude-code/issues/579), opened 2025-03-21 | `.claudeignore` unsupported reports; contributor pointed to permission rules, not an ignore-file implementation; API bodies/comments fetched |
| S27 | Anthropic, [Checkpointing](https://code.claude.com/docs/en/checkpointing) | Current rewind actions and state effects |
| S28 | anthropics/claude-code, [#46526](https://github.com/anthropics/claude-code/issues/46526), opened 2026-04-11 | Automated duplicate closure; API body/comments fetched |
| S29 | anthropics/claude-code, [#46339](https://github.com/anthropics/claude-code/issues/46339) | Duplicate chain and weak token-estimation method; API body/comments fetched |
| S30 | anthropics/claude-code, [#45188](https://github.com/anthropics/claude-code/issues/45188) | Not-planned closure and conflicting community attribution; API body/comments fetched |
| S31 | leogallego, [Claude Code token optimization guide](https://github.com/leogallego/claude-skills-tokens/blob/main/reports/claude-code-token-optimization-guide.md) | Conflicting community guidance checked against official docs |
| S32 | anthropics/claude-code, [#90449](https://github.com/anthropics/claude-code/issues/90449), opened 2026-08-28 | v2.1.250 native-Read-only trigger report; open; full API body and empty comment list fetched |
| S33 | anthropics/claude-code, [#87217](https://github.com/anthropics/claude-code/issues/87217), opened 2026-08-16 | User-rule failure on 2.1.233 and contradictory 2.1.241 retest; open; API body/comments fetched |

## Search coverage record

Thirty distinct web queries were issued; primary documents were fetched separately. Queries are recorded to make the coverage and negative findings reviewable, not as substitute evidence for recommendations.

| # | Query |
|---:|---|
| 1 | `site:code.claude.com/docs context deferred tokens categories` |
| 2 | `site:code.claude.com/docs memory paths frontmatter rules` |
| 3 | `site:github.com/anthropics/claude-code skillOverrides 50631 54996 56494` |
| 4 | `site:code.claude.com/docs disableBundledSkills` |
| 5 | `site:github.com/anthropics/claude-code/issues/46526` |
| 6 | `site:github.com/anthropics/claude-code/issues/54996` |
| 7 | `site:github.com/anthropics/claude-code/issues/56494` |
| 8 | `site:code.claude.com/docs "exclude-dynamic-system-prompt-sections"` |
| 9 | `site:code.claude.com/docs rewind delete compact clear prompt cache` |
| 10 | `site:code.claude.com/docs hooks SessionStart UserPromptSubmit additionalContext once` |
| 11 | `site:code.claude.com/docs ".claudeignore"` |
| 12 | `Claude Code paths rules measured tokens before after context` |
| 13 | `site:code.claude.com/docs "disableBundledSkills" "Requires"` |
| 14 | `site:github.com/anthropics/claude-code "paths" "2.0.64"` |
| 15 | `site:github.com/anthropics/claude-code ".claudeignore"` |
| 16 | `site:code.claude.com/docs "/context" "deferred" "System"` |
| 17 | `site:code.claude.com/docs "System tools" "deferred"` |
| 18 | `site:code.claude.com/docs "disableBundledSkills" "workflows"` |
| 19 | `site:code.claude.com/docs "skillListingBudget"` |
| 20 | `site:github.com "paths" "tokens" "before" "rules" "CLAUDE.md" optimization` |
| 21 | `site:platform.claude.com/docs "Cache hits" "0.1x"` |
| 22 | `site:code.claude.com/docs "claudeMdExcludes" "Requires"` |
| 23 | `site:code.claude.com/docs "/context" "Memory files"` |
| 24 | `site:github.com "claude" "rewind" "Delete" "cache"` |
| 25 | `site:github.com "path-scoped" "before" "after" "tokens" Claude` |
| 26 | `site:github.com "SessionStart" "token" "dedup" hooks` |
| 27 | `site:code.claude.com/docs "deferred" "not" "context" "/context"` |
| 28 | `site:github.com/anthropics/claude-code "CLAUDE.md" "paths:" "frontmatter" root` |
| 29 | `site:code.claude.com/docs "skillListingMaxDescChars" "2.1.105"` |
| 30 | `site:github.com/anthropics/claude-code "/context" "deferred" "paid"` |
