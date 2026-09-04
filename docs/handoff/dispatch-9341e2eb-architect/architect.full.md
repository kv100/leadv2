# WORKER-CONTEXT-DIET-01 — architect prepass (mechanism-closed design)

Task: dispatch-9341e2eb-architect · Role: architect · authored 2026-08-23T19:36:00Z
`docs/handoff/dispatch-9341e2eb-architect/context.yaml` does not exist on disk (checked); no
`decisions:` / `off_limits:` bind this prepass. Mission constraints are treated as the binding set.

---

## 0. Evidence artifacts (external-system claims)

All four CLI flags the mission names were verified against the **running** binary, not the nvm
copy. `command -v claude` resolves through a shell function to
`/Users/kostiantyn.vlasenko/.local/bin/claude -> ~/.local/share/claude/versions/2.1.241`; the
`@anthropic-ai/claude-code` package under `~/.nvm/.../cli.js` is a *stale, non-running* install
whose bundle does not even contain the `--autocompact` help string (`grep -c` → help text absent).
Any probe run against the nvm copy is invalid.

```
$ claude --version
2.1.241 (Claude Code)

$ claude --help | grep -nE "strict-mcp-config|mcp-config|exclude-dynamic|autocompact|--bare|--agent "
12:  --agent <agent>
27:  --autocompact <auto|tokens>           Auto-compact window size (auto, or 100k–1M tokens)
35:  --bare                                Minimal mode: skip hooks, LSP, plugin …
48:                                        (CLAUDE.md dirs), --mcp-config,
77:  --exclude-dynamic-system-prompt-sections
121:  --mcp-config <configs...>
195:  --strict-mcp-config                   Only use MCP servers from --mcp-config,
```

**E1 — `--exclude-dynamic-system-prompt-sections` applies on our spawn path.** Full help text:

```
  --exclude-dynamic-system-prompt-sections
      Move per-machine sections (cwd, env info, memory paths, git status) from
      the system prompt into the first user message. Improves cross-user
      prompt-cache reuse. Only applies with the default system prompt (ignored
      with --system-prompt). (default: false)
```

The disqualifier is `--system-prompt`. `claude-subsession.sh` passes its whole prefix via
`-p "$FINAL_PROMPT"` (a **user** prompt, `claude-subsession.sh:409`) and passes neither
`--system-prompt` nor `--append-system-prompt`. The flag therefore takes effect. Binary string
confirms the plumbing exists and is a real option, not a no-op:
`excludeDynamicSections: t.excludeDynamicSystemPromptSections || void 0`.

**E2 — `--autocompact` HAS a settings.json equivalent: `autoCompactWindow`.** Extracted from the
running binary's settings zod schema (same object literal as `advisorModel` and `fastMode`, both
known settings.json keys):

```
autoCompactWindow: Je().int().min(1e5).max(1e6).optional().catch(void 0)
                     .describe("Auto-compact window size"),
advisorModel:      H().optional().describe("Advisor model for the server-side advisor tool."),
fastMode:          Bt().optional().describe("When true, fast mode is enabled. …"),
```

and the CLI option that parses into the same value:

```
t.addOption(new wp("--autocompact <auto|tokens>","Auto-compact window size (auto, or 100k–1M tokens)")
  .argParser((c)=>{ let u=n6n(c); if(u===void 0) throw new o6t("It must be 'auto', or between 100k and 1M …") }))
```

`150000` is inside `[1e5, 1e6]`. **This kills the mission's fallback branch** ("if ONLY a flag
exists … document precisely and stop"): a settings key exists, so F3 ships as a one-line
settings.json note, not a launch wrapper. `autoCompactEnabled` is a *separate* boolean stored in
the global config (`b1().autoCompactEnabled`, toggled by the `/config` "Auto-compact" row) and
must be left `true` for the window to matter.

UNVERIFIED: that `autoCompactWindow` from settings.json survives `--continue` / `--resume`. Settings
are re-read at process start on every launch including resume, and no per-session persistence of
this value appears in the binary, so it should — but I did not run a resumed session and read
`/context`. **This is the one live check the implementing lane must run** (see acceptance).

**E3 — repowise is registered per-repo, with a different command per repo.** This is the finding
that breaks the mission's literal design:

```
~/Projects/persona-engine/.mcp.json
  mcpServers.repowise = {"command": ".../persona-engine/.repowise/repowise-mcp.sh", "args": []}
~/Projects/persona-engine/.claude/settings.json
  enabledMcpjsonServers = ["shadcn", "repowise"]
~/.claude/settings.json
  mcpServers.repowise = {"command": "~/.repowise-venv/bin/repowise",
                         "args": ["mcp", "/Users/kostiantyn.vlasenko/Projects/leadv2", "--transport", "stdio"]}
```

The user-level definition is **hard-pinned to the leadv2 repo path**. A static
`mcp-role-<ROLE>.json` baked into the plugin can only contain one of these. Ship the persona-engine
one and every leadv2-repo worker queries persona-engine's index; ship the user-level one and every
persona-engine worker queries the leadv2 index. Both are *silently wrong answers* — strictly worse
than fat context, and undetectable from the stream. See D-A.

---

## 1. CALLERS / CALLEES

### 1a. Every caller of `claude-subsession.sh` (the file the diff touches)

| # | Caller | Line | Mode | Role | Affected by this change? |
|---|---|---|---|---|---|
| 1 | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | 3023 (`SUBSESSION_BIN=…`), spawn 3326–3377 | background, **no `--wait`** → `setsid_wrapper claude` (`claude-subsession.sh:1092`) | `developer` (sonnet arm) | **YES** — the primary hot path, ~302 spawns/day |
| 2 | `plugins/leadv2/scripts/leadv2-review-run.sh` | 374 | `--wait` → `run_subsession()` (`claude-subsession.sh:427`) | `critic` | **YES** |
| 3 | `plugins/leadv2/scripts/leadv2-review-run.sh` | 374, via `LEADV2_DISPATCH_ARCHITECT_BIN` override | `--wait` | `architect` | **YES** |
| 4 | `plugins/leadv2/scripts/leadv2-claude-subsession.sh` | 50 | wrapper — forwards all args | any | **NO — and that is the defect. See 1b.** |
| 5 | `plugins/leadv2/scripts/leadv2-status-surface.sh` | 2517–2518 | argv **parser**, not a spawner | n/a | NO — it matches on *our script's* argv (`--task-id`, `--model`); `CLAUDE_ARGS` is internal and never appears in the process argv it scans |
| 6 | `plugins/leadv2/tests/test-sonnet-arm-detach-01.sh` | 38, 50–58, 132 | extracts `setsid_wrapper()` **body by name** from the live file and re-executes it | n/a | NO **provided `setsid_wrapper()` is not renamed or moved**. It fails loudly (`could not extract setsid_wrapper()`), not silently. Do not touch that function. |

Roles observed in `--role` across the plugin: `developer`, `critic`, `architect`, `hack-detect`,
plus two templated call sites (`--role "${role…`, `--role {{role…`). **`hack-detect` is a real
fourth role the mission's config list omits** — it falls to `mcp-role-default.json`, which is
correct only if `default` is defined as "repowise-only", not "empty".

### 1b. The independent copy nobody named — **BLOCKING for this lane**

`plugins/leadv2/scripts/leadv2-claude-subsession.sh:50` reads:

```
REAL_SUBSESSION="${HOME}/.claude/scripts/claude-subsession.sh"
```

```
$ ls -la ~/.claude/scripts/claude-subsession.sh
-rwxr-xr-x  1 … 51491 Aug 17 16:43 /Users/kostiantyn.vlasenko/.claude/scripts/claude-subsession.sh
```

That is a **real file, not a symlink**, last written 2026-08-17, and materially smaller than
canonical (canonical `plugins/leadv2/scripts/claude-subsession.sh` is 1158 lines). It is a stale
independent copy — a direct violation of the global CLAUDE.md one-copy policy, and exactly the
2026-07-29 defect class (a gate landed in canonical, the running path never received it). Any
worker dispatched through `leadv2-claude-subsession.sh` gets **none** of this task's slimming and
none of the last six days of canonical fixes.

**Design ruling:** do not "also patch the copy" — that entrenches the drift. The lane must convert
`~/.claude/scripts/claude-subsession.sh` to a symlink onto canonical, or (safer inside the plugin
repo, which cannot write `~/.claude` as its own deliverable) change
`leadv2-claude-subsession.sh:50` to resolve canonical relative to its own `SCRIPT_DIR` and fall
back to `$HOME/.claude/scripts/…` only if that is absent. The second is a plugin-repo-local edit
and is what this design specifies (`LANE_WRITES` includes it). Flag the stray `~/.claude` copy to
the founder as a separate one-copy cleanup; do not delete it in this lane.

### 1c. Callees inside `claude-subsession.sh` that the new code touches

| Callee | Line | Relationship |
|---|---|---|
| `build_cached_prefix(ROLE)` | 284–295, called 384 | Builds the **cached stable prefix** (role body + protocol boilerplate) keyed by checksum → `/tmp/leadv2-cache/prefix-<role>.<sum>.md`. New flags must NOT enter this prefix; they are argv, so they do not. Untouched. |
| `PER_TASK_BOILERPLATE` | 274–282 | Uncached task suffix. **This is where the cwd + base-SHA line goes** (§ D-C). |
| `CLAUDE_ARGS=( … )` | 408–420 | The array to extend. |
| `EFFORT` append | 421 | Precedent for conditional appends — new appends go immediately after, before `export CLAUDE_ROLE`. |
| `run_subsession()` | 426–428 | `--wait` path. Consumes `CLAUDE_ARGS` by reference; no change needed. |
| `setsid_wrapper claude "${CLAUDE_ARGS[@]}"` | 1092 | background path. Same. **Do not edit `setsid_wrapper()` itself** (test #6 above extracts it by name). |
| T8 `--model` rebuild loop | 883–885 | Self-locates `--model` **by value**, then writes index `i+1`. Appending new flags **after** index 420 keeps this correct. Appending anything whose *value* is the literal string `--model` would corrupt it — none of ours can. |
| max-turns truncation detector | 1037–1041, 1142 | Compares `num_turns` to `$MAX_TURNS`. Unaffected. |
| `LEADV2_DRY_RUN=1` | 969 | Logs `[DRY_RUN] subsession spawn …` and exits 0 **before** the spawn. The unit test drives the resolver through this path. |

Both spawn sites share one `CLAUDE_ARGS`, so a single append point covers both arms. There is no
second, independent CLAUDE_ARGS construction in the file.

---

## 2. STATES AND RETURN CODES

### 2a. `resolve_role_mcp_config()` — the new function (D-A)

Signature: `resolve_role_mcp_config <role> <handoff_dir>` → prints resolved config path on stdout,
returns rc.

| rc | State reached | What the caller (`claude-subsession.sh` CLAUDE_ARGS block) does | Terminal user-visible consequence |
|---|---|---|---|
| 0 | Allowlist file found for role (or `default`), ≥1 named server resolved to a definition, merged JSON written and `python3 -c json.load` round-tripped clean | appends `--strict-mcp-config --mcp-config <path>` | Worker starts with repowise only. **Human sees:** the worker's deliverable still cites repowise-grounded file/line answers, and the probe table shows the on-config first-turn base tens of K lower. |
| 10 | `LEADV2_SUBSESSION_SLIM_MCP=0` (kill-switch) | appends nothing; no WARN (this is a deliberate operator choice, not a failure) | Identical behaviour to today. Nothing in the log changes. |
| 11 | No allowlist file for role **and** no `mcp-role-default.json` | **FAIL OPEN** — appends nothing, writes one WARN line to stderr | Worker starts fat, exactly as today, and the log carries `claude-subsession: WARN context-diet: no mcp allowlist for role=<r> — spawning with full MCP set`. No worker dies. |
| 12 | Allowlist parsed, but **no** named server resolved in any of the three config sources | **FAIL OPEN** — appends nothing, one WARN naming the unresolved server(s) | Fat worker + `WARN context-diet: role=<r> servers=repowise unresolved in .mcp.json/.claude/settings.json/~/.claude/settings.json — spawning with full MCP set`. This is the mission's explicit "a worker with fat context beats a worker without repowise". |
| 13 | Merged JSON written but failed the round-trip validation, **or** the handoff dir is unwritable | **FAIL OPEN** — appends nothing, one WARN, best-effort `rm -f` the partial file | Fat worker. Never a `claude` that dies on a malformed `--mcp-config` (which would be rc≠0 at spawn and, on the background arm, a lane that produces nothing). |
| 14 | `python3` absent from PATH | **FAIL OPEN**, one WARN | Fat worker. |

**Every non-zero rc is fail-open.** The function must be invoked so that its failure cannot abort
the script: call it as `MCP_CFG=$(resolve_role_mcp_config … || true)` and branch on `-n "$MCP_CFG"`,
because `claude-subsession.sh` runs under `set -e`-style discipline elsewhere in the file and an
unguarded non-zero would kill the spawn — the single worst outcome available here.

**Terminal trace for the worst realistic case (rc=13 on the background arm, if it were NOT
fail-open):** `resolve_…` returns 13 → `CLAUDE_ARGS` gains a `--mcp-config` pointing at truncated
JSON → `claude` exits non-zero within a second → `setsid_wrapper` (line 1092) still prints a PID →
`leadv2-dispatch-code.sh` (3360) parses the handle, `kill -0` succeeds once then fails →
the lane is scored as an arm that produced nothing → **no diff is produced for that task, and the
founder sees a lane that opened and closed with no work.** This is precisely why rc 11–14 append
nothing rather than a partial config.

### 2b. `--exclude-dynamic-system-prompt-sections` (D-B)

| State | Behaviour | Consequence |
|---|---|---|
| `LEADV2_SUBSESSION_EXCLUDE_DYNAMIC=1` (default) | flag appended unconditionally — it takes no argument and cannot fail to resolve | cwd/git-status move to the first user message; cross-spawn cache prefix reuse |
| `=0` | not appended | today's behaviour |
| any other value (`""`, `yes`, `2`) | treated as **not 1** → not appended | conservative; documented |

There is no failure mode: the flag is a boolean with `(default: false)` and the binary ignores it
silently if a `--system-prompt` is ever introduced later. **Second-order risk:** the worker loses
its system-prompt-level cwd/git-status. Mitigated by D-C, not by the flag.

### 2c. `leadv2-context-diet-probe.sh` (D-D)

| rc | State | Human-visible |
|---|---|---|
| 0 | 4 spawns done, all four first-turn `cache_creation_input_tokens` parsed | prints the 4-row table + delta % |
| 1 | any spawn produced no parseable first-turn usage block | prints the rows it has and `PROBE INCOMPLETE: <n>/4 rows` — never prints a delta computed from missing rows |
| 2 | `delta < 10000` tokens | prints the table **and** `VERDICT: delta <10K — do NOT ship default-on` (mission's honesty clause). The probe reports; it never edits the defaults itself. |

---

## 3. CONFIGURATION BOUNDARIES

### 3a. `plugins/leadv2/config/mcp-role-<ROLE>.json` (new)

Schema (D-A): **an allowlist of server names, not server definitions.**
`{"servers": ["repowise"], "_comment": "…"}`

| Input state | Behaviour | Rationale |
|---|---|---|
| **absent** for the requested role | fall back to `mcp-role-default.json` | `hack-detect` and the two templated roles depend on this |
| **absent** for role *and* `default` absent | rc=11, fail open + WARN | never blocks a spawn |
| **empty file** (0 bytes) | rc=13 (parse failure) → fail open + WARN | an empty file is a truncated write, not "no servers" |
| **`{"servers": []}`** — explicit empty | rc=0, config written as `{"mcpServers":{}}`, flags **appended** | this is a legitimate, deliberate "no MCP at all" for a role. Distinguished from the empty-file case on purpose. |
| **minimum** — one name | normal path | |
| **maximum / over-cap** — N names, any N | resolve each independently; unresolved names are **skipped with a WARN each**, resolved ones are kept. rc=12 only if *zero* resolve. | An over-cap or partly-bogus allowlist must degrade to "fewer servers", never take down the spawn — a malformed entry that killed the whole worker would be the defect the prompt warns about. |
| **malformed JSON** | rc=13, fail open + WARN | |
| **name not a string / duplicate names** | non-strings skipped with WARN; duplicates deduped | |

`ROLE` itself is attacker-adjacent input (it reaches a filename). Sanitise:
`[[ "$ROLE" =~ ^[a-z0-9-]+$ ]]` else use `default`. Never interpolate `$ROLE` into a path
unvalidated — `--role ../../etc` must not read outside `plugins/leadv2/config/`.

### 3b. Server-definition source chain (read, in order; first hit wins per name)

1. `$PROJECT_ROOT/.mcp.json` → `.mcpServers.<name>`
2. `$PROJECT_ROOT/.claude/settings.json` → `.mcpServers.<name>`
3. `$HOME/.claude/settings.json` → `.mcpServers.<name>`

| Input state | Behaviour |
|---|---|
| all three absent | rc=12, fail open |
| a file present but malformed JSON | skip that source with a WARN, continue to the next — **one bad `.mcp.json` must not blind the whole chain** |
| present, valid, name missing | continue to next source |
| `PROJECT_ROOT` unset or not a dir | skip sources 1–2, try 3 only |
| definition present but not an object / no `command` | treat as unresolved (skip + WARN) |

`enabledMcpjsonServers` is **read only as a filter, never as a source**: a name in the allowlist
that is present in `.mcp.json` but *absent* from `enabledMcpjsonServers` is still emitted, because
`--strict-mcp-config` bypasses the enable list anyway and the allowlist is the stricter gate. Note
this in a comment so a later reader does not "fix" it.

### 3c. Env vars

| Var | Default | absent | empty | `0` | `1` | anything else |
|---|---|---|---|---|---|---|
| `LEADV2_SUBSESSION_SLIM_MCP` | `1` | on | on (`${VAR:-1}`) | off, rc=10, silent | on | **on** — only the literal `0` disables, so a typo fails toward the flag being applied. *Chosen deliberately:* the failure mode of "applied" is fail-open-to-fat anyway (§2a), so there is no unsafe direction. |
| `LEADV2_SUBSESSION_EXCLUDE_DYNAMIC` | `1` | on | on | off | on | on |

Naming: both use the `LEADV2_SUBSESSION_*` prefix already established by
`LEADV2_SUBSESSION_MAX_TURNS` (`claude-subsession.sh:406`). No `LEAD_V2_*` drift. Neither name
collides with anything in the repo (`grep -rn LEADV2_SUBSESSION_` returns only `MAX_TURNS`).

### 3d. `autoCompactWindow` in a repo's `.claude/settings.json` (F3)

| Input | Behaviour |
|---|---|
| absent | today's behaviour (compaction at the model's default window) |
| `150000` | valid; inside `[1e5, 1e6]` |
| `< 100000` or `> 1000000` | rejected by the zod schema (`.min(1e5).max(1e6)`) → `.catch(void 0)` → **silently ignored**, no error. A typo'd `15000` therefore looks like it worked and does nothing. The doc note must state the range explicitly. |
| non-integer / string | `.catch(void 0)` → silently ignored |
| `autoCompactEnabled: false` in global config | window is irrelevant; compaction never fires |

The three live repos' `.claude/settings.json` are **not plugin-owned** (global CLAUDE.md
shared-trees policy). F3 therefore ships as: (i) the exact one-line change documented in
`plugins/leadv2/docs/context-diet.md`, and (ii) nothing written outside `~/Projects/leadv2`.

---

## 4. COUNTEREXAMPLE

After every finding in this mission is fixed, the invariant "a headless worker pays only for
context it can use" is **still violated on three fronts, and one of them is the larger half of the
measured burn.** First, neither flag touches the **skill catalog** — the mission's own problem
statement bundles "MCP tool schemas + skill catalog" as the ~90–110K, but `--strict-mcp-config`
bounds only the MCP half and `--exclude-dynamic-system-prompt-sections` only relocates per-machine
sections; the skill frontmatter block (the binary tracks it as `skills.totalSkills /
includedSkills / skillFrontmatter`, and this session's own listing carries ~150 skills) is
unaffected, so a worker still pays for every plugin skill it will never invoke. Deliberately
out of scope here, but the probe will show it as an on-config base that is still large in absolute
terms even after a large delta — do not read that residue as a failed fix. Second, D-B's cache-prefix
win is real only if the *rest* of the prefix is byte-identical across spawns, and
`build_cached_prefix()` (`claude-subsession.sh:284–295`) already varies by role while
`PER_TASK_BOILERPLATE` varies by task — adding a base-SHA line (D-C) makes the suffix change on
**every commit**, which is correct for the worker and irrelevant to the cache only because the
suffix was already uncached; if an implementer "helpfully" moves the SHA into the cached prefix to
save bytes, cross-spawn reuse dies silently and the probe will not catch it because the probe
measures a single spawn pair. Third, and least comfortable: `~/.claude/scripts/claude-subsession.sh`
is a live independent copy (§1b) that this lane can mitigate but not delete, so until the founder
lands the one-copy cleanup, *some* dispatch path can still spawn a worker with none of this
applied — the invariant is repaired on the canonical path, not on every path.

What I checked and found clean: the T8 `--model` rebuild loop (883–885) is index-safe under
appends; `leadv2-status-surface.sh`'s argv parser reads our argv, not `claude`'s; no test in
`plugins/leadv2/scripts/tests/` or `plugins/leadv2/tests/` asserts on the contents of `CLAUDE_ARGS`
(`grep -n "CLAUDE_ARGS" test-claude-subsession-{turncap,sentinel}.sh` → no hits), so appending
flags breaks no existing assertion.

---

## 5. Design decisions

**D-A — `mcp-role-<ROLE>.json` holds an allowlist of server NAMES, not server definitions.**
*This contradicts the mission's literal wording and is the right call; designing against the code.*
The mission says "Contents: ONLY the MCP servers that role's agent frontmatter tools list
references" and, in the same breath, "must be copied from what a target repo's .mcp.json actually
uses — resolve it dynamically if per-repo". Evidence E3 settles it: repowise **is** per-repo, with
two mutually incompatible definitions on this machine, one of them path-pinned to `leadv2`.
A baked definition is not merely stale — it silently points a worker at the wrong repository's
index, producing confident, wrong, file:line-cited answers. The static file therefore carries only
the role→names policy (which is genuinely plugin-owned and repo-independent); the definitions are
resolved at spawn time from the live config chain (§3b) into
`$HANDOFF_DIR/mcp-role-<ROLE>.resolved.json`. Writing it into the handoff dir (not `/tmp`) makes it
inspectable next to the stream and disposed of with the task.

**D-B — graph MCP (`mcp__codebase-memory-mcp__*`) is omitted from every role config.** The
`developer` frontmatter in target repos references it, but it is disabled in persona-engine, and
the subagent protocol states flatly that a `claude -p` subsession has no MCP-graph access anyway.
Carry this as a `_comment` inside each JSON so the omission reads as a decision, not an oversight.

**D-C — the base-SHA/cwd line goes in `PER_TASK_BOILERPLATE` (274–282), not in the mission body.**
Verified: that block currently lists TASK_ID, ROLE, deliverables, mcp-cache, context file, question
proxy, skills — **no cwd and no base SHA**. Since D-B moves cwd/git-status out of the system prompt,
the worker would otherwise lose situational awareness entirely. Add exactly one line:
`- Worktree: ${PROJECT_ROOT} @ base ${BASE_SHA}` where `BASE_SHA` is
`git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown`. It lands in the
**uncached** suffix, so it costs no cache reuse. Do not put it in `build_cached_prefix()`.

**D-D — the probe reports; it never flips a default.** Mission: "if delta < 10K, say so honestly —
do not ship default-on". The probe exits 2 with an explicit VERDICT line; flipping
`LEADV2_SUBSESSION_SLIM_MCP` / `_EXCLUDE_DYNAMIC` defaults to 0 is a human decision made from the
table, recorded in the close notes. A script that silently rewrites its own feature defaults is
exactly the kind of mechanism that is impossible to reason about later.

**D-E — no `--bare`, no `--agent`.** `--bare` skips hooks/LSP/plugins and forces API-key auth,
leaving the subscription pool (findings F1); the whole leadv2 dispatch mechanism is hooks. `--agent`
is left as a `# TODO(F1): --agent cache-prefix interaction unproven` comment only.

---

## 6. Files, exactly

| File | Change |
|---|---|
| `plugins/leadv2/scripts/claude-subsession.sh` | + `resolve_role_mcp_config()` (near `build_cached_prefix`, ~line 296); + one line in `PER_TASK_BOILERPLATE` (D-C, 274–282); + two conditional appends immediately after line 421. **Do not touch** `setsid_wrapper()`, the T8 loop (883–885), or `run_subsession()`. |
| `plugins/leadv2/config/mcp-role-{developer,critic,architect,default}.json` | new; `{"servers":["repowise"], "_comment": "…graph MCP omitted: disabled in persona-engine + no MCP in headless -p …"}`. `default` covers `hack-detect` and templated roles. |
| `plugins/leadv2/scripts/leadv2-context-diet-probe.sh` | new; 4 spawns (2 configs × 2), scratch dir, parses first-turn `cache_creation_input_tokens` + `cache_read_input_tokens` from each `<role>.stream.jsonl`, prints table + delta, rc per §2c. |
| `plugins/leadv2/scripts/leadv2-claude-subsession.sh` | line 50 — resolve canonical via `SCRIPT_DIR` first, `$HOME/.claude/scripts/…` only as fallback (§1b). |
| `plugins/leadv2/scripts/tests/test-subsession-context-diet.sh` | new; house style of the dir, registered in `run-core-offline.sh`. Cases: role→file mapping (4 roles + unknown role→default); `hack-detect`→default; missing config→fail-open, zero flags, WARN present; malformed JSON→fail-open; `{"servers":[]}`→flags present, `{"mcpServers":{}}` written; unresolvable server→fail-open + WARN; `SLIM_MCP=0`→no flags, **no** WARN; `EXCLUDE_DYNAMIC=0`→flag absent; `ROLE=../../evil`→coerced to default. Driven through `LEADV2_DRY_RUN=1` (line 969) so no `claude` is spawned. |
| `plugins/leadv2/docs/phases.md` | short section beside the existing `LEADV2_SUBSESSION_*` knobs: the two new envs, one line each. |
| `plugins/leadv2/docs/context-diet.md` | new; full detail — both envs, the probe, the `--bare` trap (API-key auth / leaves subscription pool), the `--agent` TODO, and the F3 note: *add `"autoCompactWindow": 150000` to the repo's `.claude/settings.json` (valid range 100000–1000000; out-of-range values are silently ignored; requires Auto-compact enabled in `/config`)* — flagged as **not plugin-owned, founder applies per repo**. |

**Non-goals (implementer: ignore these).** Trimming the skill catalog. `--agent`. `--bare`. Deleting
or rewriting `~/.claude/scripts/claude-subsession.sh` (report it; separate one-copy task). Editing
any `.claude/settings.json` in persona-engine / m3-market / respiro-ios. Touching the GLM/Codex/Kimi
dispatch arms. Changing `MAX_TURNS`, `setsid_wrapper()`, or the T8 `--model` rebuild.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Wrong-repo repowise index (E3) | D-A: resolve at spawn from the live chain; never bake a definition |
| Malformed `--mcp-config` kills a background lane (§2a trace) | every rc 11–14 appends **nothing**; round-trip-validate the written JSON before appending |
| Worker loses cwd/git awareness under D-B | D-C adds cwd + base SHA to the uncached task suffix |
| `resolve_…` non-zero aborts the script under `set -e` | call as `$( … || true )` and branch on emptiness |
| Stale `~/.claude` copy bypasses the whole fix | §1b — repoint `leadv2-claude-subsession.sh:50`; escalate the copy |
| `autoCompactWindow: 15000` typo silently no-ops | doc note states the 100000–1000000 range and the silent-ignore behaviour |
| Probe measures noise, not signal | 2 spawns per config, report per-row, refuse to print a delta on an incomplete table (rc=1) |

---

```yaml
acceptance:
  - surface: log_line
    observable: >-
      With the kill-switches unset, a dispatched worker's stderr shows no
      "context-diet" WARN line at all, and the worker's own deliverable still
      quotes repowise-grounded file-and-line answers about the repo it was
      spawned in — not about a different repo.
    authored_at: 2026-08-23T19:36:00Z
  - surface: file_artifact
    observable: >-
      The probe's printed table shows four rows — flags-on and flags-off, two
      runs each — and the flags-on rows' first-turn fresh-context number is
      visibly tens of thousands smaller than the flags-off rows'. If it is not,
      the table's last line reads that the delta is under ten thousand and that
      the feature must not be shipped on by default.
    authored_at: 2026-08-23T19:36:00Z
  - surface: log_line
    observable: >-
      With a role's config file deleted, a spawned worker still starts and
      finishes normally, and one warning line appears saying the worker was
      launched with the full MCP set because no allowlist was found. No lane
      opens and closes without producing work.
    authored_at: 2026-08-23T19:36:00Z
  - surface: rendered_line
    observable: >-
      In a founder session launched normally in a repo whose settings carry the
      new key, /context shows the auto-compact threshold at 150k rather than the
      previous 400-500k figure, and it still shows 150k after that session is
      resumed with --continue.
    authored_at: 2026-08-23T19:36:00Z
```

LANE_WRITES: plugins/leadv2/scripts/claude-subsession.sh, plugins/leadv2/scripts/leadv2-claude-subsession.sh, plugins/leadv2/scripts/leadv2-context-diet-probe.sh, plugins/leadv2/config/mcp-role-developer.json, plugins/leadv2/config/mcp-role-critic.json, plugins/leadv2/config/mcp-role-architect.json, plugins/leadv2/config/mcp-role-default.json, plugins/leadv2/scripts/tests/test-subsession-context-diet.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/docs/phases.md, plugins/leadv2/docs/context-diet.md

DELIVERABLE_COMPLETE
