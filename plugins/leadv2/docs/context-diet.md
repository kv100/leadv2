# Worker context diet (WORKER-CONTEXT-DIET-01)

Every headless worker spawn (`claude-subsession.sh`, both the `--wait` critic/architect arm and
the backgrounded sonnet-arm dispatch path) pays for MCP tool schemas and the full skill catalog
it never uses, and every spawn pays for per-machine system-prompt sections (cwd, env info,
memory paths, git status) that break cross-spawn prompt-cache reuse. This doc covers the two
mechanisms that trim that, the measurement probe that proves the trim is real, and the lead
compaction change — plus what is deliberately **not** touched.

## 1. Per-role MCP allowlist (`LEADV2_SUBSESSION_SLIM_MCP`, default `0` (opt-in))

When enabled, `claude-subsession.sh` appends `--strict-mcp-config --mcp-config <resolved.json>`
to the spawned worker's CLI args, restricting it to the MCP servers its role actually uses —
in practice `repowise` only (`plugins/leadv2/config/mcp-role-<role>.json`).

**Why the config file is an allowlist of names, not server definitions:** `repowise` is
registered per-repo with a *different* command in each project's `.mcp.json`, and the
user-level `~/.claude/settings.json` definition is hard-pinned to a single repo path. A baked
definition would silently point a worker at the wrong repo's index — confidently wrong, not
merely fat. So `plugins/leadv2/config/mcp-role-<role>.json` holds only
`{"servers": ["repowise"]}`; `resolve_role_mcp_config()` in `claude-subsession.sh` resolves each
name against the live chain at spawn time, in order:

1. `$PROJECT_ROOT/.mcp.json` → `.mcpServers.<name>`
2. `$PROJECT_ROOT/.claude/settings.json` → `.mcpServers.<name>`
3. `$HOME/.claude/settings.json` → `.mcpServers.<name>`

The merged, resolved definition is written to
`docs/handoff/<task-id>/mcp-role-<role>.resolved.json` (inspectable next to the worker's stream,
disposed of with the task) and validated by a JSON round-trip before it is ever passed to
`claude`.

`mcp__codebase-memory-mcp__*` (the graph MCP) is deliberately **omitted** from every role
config: it is disabled in persona-engine, and a headless `claude -p` subsession has no MCP-graph
access regardless (`leadv2-subagent-protocol.md` §1b) — the omission is a decision, not an
oversight, and is noted in each config file's `_comment`.

**Roles covered:** `developer`, `critic`, `architect` each get a dedicated file; every other
role (`hack-detect`, templated `--role "${role...}"` call sites) falls back to
`mcp-role-default.json`.

**Fail-open, always.** Every non-zero return from `resolve_role_mcp_config()` means "append no
MCP flags" — a worker with the full MCP set beats a worker that never spawns:

| rc | Cause | Result |
|---|---|---|
| 0 | Allowlist resolved, ≥1 server, JSON round-tripped clean | `--strict-mcp-config --mcp-config <path>` appended |
| 10 | `LEADV2_SUBSESSION_SLIM_MCP=0` (kill-switch) | nothing appended, no WARN (deliberate operator choice) |
| 11 | No allowlist file for the role and no `mcp-role-default.json` | nothing appended, one WARN |
| 12 | Allowlist parsed but zero named servers resolved in any source | nothing appended, one WARN naming the unresolved server(s) |
| 13 | Malformed JSON or failed round-trip validation | nothing appended, one WARN |
| 14 | `python3` not on `PATH` | nothing appended, one WARN |
| 15 | Handoff dir/resolved-config write failure (missing/unwritable dir) | nothing appended, one WARN |

A malformed `--mcp-config` reaching `claude` would kill the process outright — on the
backgrounded sonnet arm that means `setsid_wrapper` still returns a PID, but the lane opens and
closes with no work produced. This is exactly why every failure path here appends nothing rather
than a partial or best-effort config.

`{"servers": []}` (explicit empty list) is distinct from a missing/malformed file: it is a
deliberate "no MCP at all" for that role, and still appends the flags with an empty
`mcpServers`.

## 2. Dynamic system-prompt section exclusion (`LEADV2_SUBSESSION_EXCLUDE_DYNAMIC`, default `0` (opt-in))

When enabled, `claude-subsession.sh` appends `--exclude-dynamic-system-prompt-sections`
unconditionally (it takes no argument and cannot fail to resolve). This moves per-machine
sections (cwd, env info, memory paths, git status) out of the cached system-prompt block and
into the first user message, improving cross-spawn prompt-cache reuse. It has no effect if a
future change ever passes `--system-prompt` (the flag is documented as ignored in that case).

Because this removes cwd/git-status from the system prompt, `claude-subsession.sh`'s
`PER_TASK_BOILERPLATE` (the uncached per-task suffix) now includes one line so workers keep
situational awareness without losing cache-prefix reuse:

```
- Worktree: <PROJECT_ROOT> @ base <short SHA>
```

Both gates are strict opt-in: enabled iff the value is exactly the literal `1`; every other
value — unset, empty, `0`, or a typo like `2`/`true` — leaves the gate off. Default is off for
both, per a live probe run 2026-08-23 (`leadv2-context-diet-probe.sh`) that measured
`cache_creation` delta ≈ 0 against the mission gate "delta <10K → no default-on". The failure
direction is still always toward fail-open-to-fat (§1); strict opt-in only changes which values
count as "on", not the fail-open guarantee.

## 3. Measurement probe

`plugins/leadv2/scripts/leadv2-context-diet-probe.sh` spawns four trivial one-turn `critic`
workers (mission: "reply DONE") via the real `claude-subsession.sh` in a scratch project root —
two with both flags on, two with both off — and parses each worker's stream-json for the first
turn's `cache_creation_input_tokens` / `cache_read_input_tokens`. It prints a 4-row table and the
on/off delta.

Each spawn is a **real, billed** `claude -p` call — this is deliberate; a `LEADV2_DRY_RUN=1` run
cannot measure real cache-creation tokens. Run it before deciding whether to change either
default:

```
bash plugins/leadv2/scripts/leadv2-context-diet-probe.sh
```

Exit codes: `0` = 4/4 rows parsed, table printed; `1` = fewer than 4 rows parsed (`PROBE
INCOMPLETE: <n>/4 rows`, no delta computed from a partial table); `2` = full table, but delta
< 10,000 tokens (`VERDICT: delta <10K — do NOT ship default-on`).

**The probe reports; it never flips a default itself.** If the measured delta is small, that is
a human decision recorded in the close notes — a script that silently rewrites its own feature
defaults is unreasonable to debug later.

## 4. What this does NOT cover

- **The skill catalog.** Neither flag touches the ~150-skill frontmatter block a worker still
  pays for on every spawn. Deliberately out of scope for this task — the probe's on-config
  baseline will still look large in absolute terms after a real delta; that residue is expected,
  not a failed fix.
- **`--bare`.** Forces API-key auth, silently leaving the subscription pool. Not used.
- **`--agent`.** Cache-prefix interaction with this file's cached-prefix scheme is unproven; left
  as a `# TODO` in `claude-subsession.sh`, not adopted.
- **The stray `~/.claude/scripts/claude-subsession.sh` copy.** A real, independently-drifting
  file (not a symlink), last touched before several canonical fixes including this one. Any
  dispatch path still routed through it gets none of this. `leadv2-claude-subsession.sh` now
  resolves the canonical script beside itself first and falls back to the stray copy only if
  canonical is absent, but the stray copy itself is not deleted or converted here — that is a
  separate one-copy cleanup for the founder (global CLAUDE.md shared-trees policy).

## 5. Lead-session compaction (`autoCompactWindow`)

For the founder's *interactive* lead session (not headless workers): `claude` v2.1.241 exposes
`--autocompact <auto|tokens>` on the CLI and the equivalent `autoCompactWindow` key (int,
100000–1000000) in `settings.json` — confirmed against the running binary's option parser and
zod settings schema (`--help` output and extracted schema literal, see
`docs/handoff/dispatch-9341e2eb-architect/architect.full.md` §0 E2). A value outside that range
is **silently ignored** (`.catch(void 0)` in the schema) — no error, so a typo like `15000` looks
like it worked and does nothing.

To compact a lead session earlier than the ~400–500K default, add to that repo's
`.claude/settings.json`:

```json
{
  "autoCompactWindow": 150000
}
```

Requires Auto-compact enabled in `/config` (a separate `autoCompactEnabled` boolean; the window
value is irrelevant if compaction is disabled). This is **not plugin-owned** — persona-engine,
m3-market, and respiro-ios each own their own `.claude/settings.json` per the global CLAUDE.md
shared-trees policy — so this file documents the exact change; the founder applies it per repo.
